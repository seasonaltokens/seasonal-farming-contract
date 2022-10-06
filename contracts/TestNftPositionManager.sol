// Seasonal Token Farm Test NFT Position Manager

//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/PositionKey.sol';
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
import "./interfaces/ERC721TokenReceiver.sol";
import "./interfaces/INonFungiblePositionManager.sol";
import "./base/ERC721Permit.sol";

abstract contract TestNftPositionManager is INonFungiblePositionManager, ERC721Permit {

    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // how many uncollected tokens are owed to the position, as of the last computation
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    address public immutable factory;
    uint256 public numberOfTokens;
    mapping(uint256 => Position) private _positions;

    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'Not approved');
        _;
    }

    constructor(address _factory) {
        factory = _factory;
    }

    function createLiquidityToken(
        address _operator,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity)
    public returns (uint256) {
        uint256 tokenId = numberOfTokens;
        _positions[tokenId] = Position({
            nonce : 0,
            operator : _operator,
            token0 : _token0,
            token1 : _token1,
            fee : _fee,
            tickLower : _tickLower,
            tickUpper : _tickUpper,
            liquidity : _liquidity,
            feeGrowthInside0LastX128 : 0,
            feeGrowthInside1LastX128 : 0,
            tokensOwed0 : 0,
            tokensOwed1 : 0
        });
        numberOfTokens++;
        return tokenId;
    }

    function positions(uint256 tokenId) external view override returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    )
    {
        Position memory position = _positions[tokenId];
        return (
            position.nonce,
            position.operator,
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function collect(CollectParams calldata params) external payable override isAuthorizedForToken(params.tokenId) returns (uint256 amount0, uint256 amount1)
    {
        require(params.amount0Max > 0 || params.amount1Max > 0);
        // allow collecting to the nft position manager address with address 0
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        Position storage position = _positions[params.tokenId];

        PoolAddress.PoolKey memory poolKey;
        poolKey.token0 = position.token0;
        poolKey.token1 = position.token1;
        poolKey.fee = 100;

        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

        // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
        if (position.liquidity > 0) {
            pool.burn(position.tickLower, position.tickUpper, 0);
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, ,) =
            pool.positions(PositionKey.compute(address(this), position.tickLower, position.tickUpper));

            tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );
            tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }

        // compute the arguments to give to the pool#collect method
        (uint128 amount0Collect, uint128 amount1Collect) =
        (
        params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
        params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
        );

        // the actual amounts collected are returned
        (amount0, amount1) = pool.collect(
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        // sometimes there will be a few less wei than expected due to rounding down in core, but we just subtract the full amount expected
        // instead of the actual amount so we can burn the token
        (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);

        emit Collect(params.tokenId, recipient, amount0Collect, amount1Collect);
    }

    function selfSafeTransferFrom(address _from, address _to, uint256 _tokenId) external override {
        bytes memory data;
        require(_from == _positions[_tokenId].operator, "Only owner can transfer");
        _positions[_tokenId].operator = _to;
        if (isContract(_to))
            require(ERC721TokenReceiver(_to).onERC721Received(_positions[_tokenId].operator, _from, _tokenId, data)
                == bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")),
                "onERC721Received failed.");
    }

    function isContract(address _addr) private returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}