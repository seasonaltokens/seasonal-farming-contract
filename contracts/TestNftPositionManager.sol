//SPDX-License-Identifier: MIT
pragma solidity 0.8.5;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./interfaces/INonfungiblePositionManager.sol";

contract TestNftPositionManager is INonfungiblePositionManager {

    uint256 public numberOfTokens;
    
    mapping(uint => address) public operators;
    mapping(uint => address) public token0s;
    mapping(uint => address) public token1s;
    mapping(uint => uint24) public fees;
    mapping(uint => int24) public tickLowers;
    mapping(uint => int24) public tickUppers;
    mapping(uint => uint128) public liquidities;

    function createLiquidityToken(address _operator,
                                  address _token0,
                                  address _token1,
                                  uint24 _fee,
                                  int24 _tickLower,
                                  int24 _tickUpper,
                                  uint128 _liquidity) public returns (uint256) {

        uint256 tokenId = numberOfTokens;

        operators[tokenId] = _operator;
        token0s[tokenId] = _token0;
        token1s[tokenId] = _token1;
        fees[tokenId] = _fee;
        tickLowers[tokenId] = _tickLower;
        tickUppers[tokenId] = _tickUpper;
        liquidities[tokenId] = _liquidity;

        numberOfTokens++;

        return tokenId;
    }

    function positions(uint256 _tokenId)
        external override 
        view
        returns (uint96 nonce,
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
                 uint128 tokensOwed1) {

        operator = operators[_tokenId];
        token0 = token0s[_tokenId];
        token1 = token1s[_tokenId];
        fee = fees[_tokenId];
        tickLower = tickLowers[_tokenId];
        tickUpper = tickUppers[_tokenId];
        liquidity = liquidities[_tokenId];

        return (0, operator, token0, token1, fee,
                tickLower, tickUpper, liquidity, 0, 0, 0, 0);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external override {
        bytes memory data;
        require(_from == operators[_tokenId], "Only owner can transfer");
        operators[_tokenId] = _to;
        if (isContract(_to))
            require(IERC721Receiver(_to).onERC721Received(operators[_tokenId], _from, _tokenId, data)
                      == bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")), 
                    "onERC721Received failed.");
    }

    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}