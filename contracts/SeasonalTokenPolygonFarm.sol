//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import './utils/structs/EnumerableSet.sol';
import './security/ReentrancyGuard.sol';
import "./interfaces/ERC20.sol";
import "./interfaces/ERC721TokenReceiver.sol";
import "./interfaces/INonFungiblePositionManager.sol";
import "./interfaces/TransferHelper.sol";
import "./libraries/SafeTransferFrom.sol";

/*
 * Seasonal Token Farm
 *
 * This contract receives donations of seasonal tokens and distributes them to providers of liquidity
 * for the token/MATIC trading pairs on Uniswap v3.
 *
 * Warning: Tokens can be lost if they are not transferred to the farm contract in the correct way.
 *
 * Seasonal tokens must be approved for use by the farm contract and donated using the 
 * receiveSeasonalTokens() function. Tokens sent directly to the farm address will be lost.
 *
 * Contracts that deposit Uniswap liquidity tokens need to implement the onERC721Received() function in order
 * to be able to withdraw those tokens. Any contracts that interact with the farm must be tested prior to 
 * deployment on the main network.
 * 
 * The developers accept no responsibility for tokens irretrievably lost in accidental transfers.
 * 
 */

struct LiquidityToken {
    address owner;
    address seasonalToken;
    uint256 depositTime;
    uint256 initialCumulativeSpringTokensFarmed;
    uint256 initialCumulativeSummerTokensFarmed;
    uint256 initialCumulativeAutumnTokensFarmed;
    uint256 initialCumulativeWinterTokensFarmed;
    uint256 liquidity;
    uint256 position;
}


contract SeasonalTokenFarm is ERC721TokenReceiver, ReentrancyGuard {

    // The Seasonal Token Farm runs on voluntary donations.

    // Incoming donated tokens are distributed to liquidity providers for the ETH/Token trading pairs.
    // Each trading pair has an allocationSize. Incoming tokens are allocated to trading pairs in
    // proportion to their allocationSizes. The fraction of tokens allocated to a trading pair is
    // equal to that trading pair's allocationSize divided by the sum of the allocationSizes.

    // The initial allocationSizes are 5, 6, 7 and 8 for Spring, Summer, Autumn and Winter.
    // Four months after each token's halving, the allocationSize for the ETH/Token trading pair
    // doubles. 
    //
    // When the doubling of the Winter allocation occurs, the allocationSizes become 10, 12, 14 and 16,
    // which are simplified to 5, 6, 7, 8, and then the cycle repeats.

    // Initially, the allocationSizes will be 5, 6, 7 and 8.
    //
    // After the Spring halving, they will be 10, 6, 7 and 8.
    // After the Summer halving, they will be 10, 12, 7 and 8.
    // After the Autumn halving, they will be 10, 12, 14 and 8.
    // After the Winter halving, they will be 5, 6, 7 and 8 again.

    // The reduction of the allocationSizes from 10, 12, 14, 16 to 5, 6, 7, 8 doesn't change the
    // payouts received. The fraction of farm rewards allocated to Spring, for example, 
    // is 10/(10+12+14+16) = 5/(5+6+7+8).

//    using UintSet for UintSet.Set;
//    UintSet.Set uintSet;

    uint256 public constant REALLOCATION_INTERVAL = (365 * 24 * 60 * 60 * 3) / 4; // 9 months
    address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // Liquidity positions must cover the full range of prices

    int24 public constant REQUIRED_TICK_UPPER = 887272;     // 0.01% fee level
    int24 public constant REQUIRED_TICK_LOWER = -887272;


    // Liquidity tokens can be withdrawn for 7 days out of every 37.
    //
    // This means that about one fifth of the liquidity can be withdrawn at any given time,
    // preventing liquidity from disappearing in a panic, but liquidity providers can withdraw
    // to adjust their positions monthly.

    uint256 public constant WITHDRAWAL_UNAVAILABLE_DAYS = 30;
    uint256 public constant WITHDRAWAL_AVAILABLE_DAYS = 7;


    // Each liquidity token deposited adds a specific amount of liquidity to the ETH/Seasonal Token
    // trading pair. Incoming tokens allocated to that trading pair are distributed to liquidity
    // token owners in proportion to the liquidity they have provided.

    mapping(address => uint256) public totalLiquidity;
    mapping(address => uint256[]) public tokenOfOwnerByIndex;
    mapping(uint256 => LiquidityToken) public liquidityTokens;

    address public immutable springTokenAddress;
    address public immutable summerTokenAddress;
    address public immutable autumnTokenAddress;
    address public immutable winterTokenAddress;
    address public immutable wethAddress;

    INonFungiblePositionManager public immutable nonFungiblePositionManager;

    uint256 public immutable startTime;


    // We keep track of the cumulative number of farmed (donated and allocated) tokens of each type per unit
    // liquidity, for each trading pair. This allows us to calculate the payout for each liquidity token.
    // 
    // When a liquidity token is deposited, the value of the cumulative number of farmed tokens per unit
    // liquidity is recorded. The number of tokens farmed by that liquidity position is given by the
    // amount of liquidity multiplied by the increase in the cumulative number of tokens farmed per
    // unit liquidity.
    //
    // cumulativeTokensFarmedPerUnitLiquidity[trading_pair_token][farmed_token] = farmed tokens/liquidity

    mapping(address => mapping(address => uint256)) public cumulativeTokensFarmedPerUnitLiquidity;

    event Deposit(address indexed from, uint256 liquidityTokenId);
    event Withdraw(address indexed tokenOwner, uint256 liquidityTokenId);
    event Donate(address indexed from, address seasonalTokenAddress, uint256 amount);
    event Harvest(address indexed tokenOwner, uint256 liquidityTokenId,
                  uint256 springAmount, uint256 summerAmount, uint256 autumnAmount, uint256 winterAmount);
    event Collect(uint256 tokenId, address recipient, uint128 amount0Collect, uint128 amount1Collect);

    constructor (INonFungiblePositionManager _nonFungiblePositionManager,
                 address _springTokenAddress,
                 address _summerTokenAddress,
                 address _autumnTokenAddress,
                 address _winterTokenAddress,
                 address _wethAddress,
                 uint256 _startTime) public {

        require(_startTime >= block.timestamp, 'Not validate start_time');
        nonFungiblePositionManager = _nonFungiblePositionManager;

        springTokenAddress = _springTokenAddress;
        summerTokenAddress = _summerTokenAddress;
        autumnTokenAddress = _autumnTokenAddress;
        winterTokenAddress = _winterTokenAddress;
        wethAddress = _wethAddress;

        startTime = _startTime;
    }

    function balanceOf(address _liquidityProvider) external view returns (uint256) {
        return tokenOfOwnerByIndex[_liquidityProvider].length;
    }

    function numberOfReAllocations() internal view returns (uint256) {
        if (block.timestamp < startTime + REALLOCATION_INTERVAL)
            return 0;
        uint256 timeSinceStart = block.timestamp - startTime;
        return timeSinceStart / REALLOCATION_INTERVAL;
    }
    function hasDoubledAllocation(uint256 _tokenNumber) internal view returns (uint256) {
        if (numberOfReAllocations() % 4 < _tokenNumber) {
            return 0;
        }
        return 1;
    }

    function springAllocationSize() public view returns (uint256) {
        return 5 * 2 ** hasDoubledAllocation(1);
    }

    function summerAllocationSize() public view returns (uint256) {
        return 6 * 2 ** hasDoubledAllocation(2);
    }

    function autumnAllocationSize() public view returns (uint256) {
        return 7 * 2 ** hasDoubledAllocation(3);
    }

    function winterAllocationSize() public pure returns (uint256) {
        return 8;
    }

    function getEffectiveTotalAllocationSize(uint256 _totalSpringLiquidity,
                                             uint256 _totalSummerLiquidity,
                                             uint256 _totalAutumnLiquidity,
                                             uint256 _totalWinterLiquidity) internal view returns (uint256) {
        uint256 effectiveTotal = 0;

        if (_totalSpringLiquidity > 0)
            effectiveTotal += springAllocationSize();
        if (_totalSummerLiquidity > 0)
            effectiveTotal += summerAllocationSize();
        if (_totalAutumnLiquidity > 0)
            effectiveTotal += autumnAllocationSize();
        if (_totalWinterLiquidity > 0)
            effectiveTotal += winterAllocationSize();

        return effectiveTotal;
    }

    function allocateIncomingTokensToTradingPairs(address _incomingTokenAddress, uint256 _amount) internal {

        uint256 totalSpringLiquidity = totalLiquidity[springTokenAddress];
        uint256 totalSummerLiquidity = totalLiquidity[summerTokenAddress];
        uint256 totalAutumnLiquidity = totalLiquidity[autumnTokenAddress];
        uint256 totalWinterLiquidity = totalLiquidity[winterTokenAddress];

        uint256 effectiveTotalAllocationSize = getEffectiveTotalAllocationSize(totalSpringLiquidity,
                                                                               totalSummerLiquidity,
                                                                               totalAutumnLiquidity,
                                                                               totalWinterLiquidity);

        require(effectiveTotalAllocationSize > 0, "No liquidity in farm");

        uint256 springPairAllocation = (_amount * springAllocationSize()) / effectiveTotalAllocationSize;
        uint256 summerPairAllocation = (_amount * summerAllocationSize()) / effectiveTotalAllocationSize;
        uint256 autumnPairAllocation = (_amount * autumnAllocationSize()) / effectiveTotalAllocationSize;
        uint256 winterPairAllocation = (_amount * winterAllocationSize()) / effectiveTotalAllocationSize;

        if (totalSpringLiquidity > 0)
            cumulativeTokensFarmedPerUnitLiquidity[springTokenAddress][_incomingTokenAddress]
                += (2 ** 128) * springPairAllocation / totalSpringLiquidity;

        if (totalSummerLiquidity > 0)
            cumulativeTokensFarmedPerUnitLiquidity[summerTokenAddress][_incomingTokenAddress]
                += (2 ** 128) * summerPairAllocation / totalSummerLiquidity;

        if (totalAutumnLiquidity > 0)
            cumulativeTokensFarmedPerUnitLiquidity[autumnTokenAddress][_incomingTokenAddress]
                += (2 ** 128) * autumnPairAllocation / totalAutumnLiquidity;

        if (totalWinterLiquidity > 0)
            cumulativeTokensFarmedPerUnitLiquidity[winterTokenAddress][_incomingTokenAddress]
                += (2 ** 128) * winterPairAllocation / totalWinterLiquidity;
    }

    function receiveSeasonalTokens(address _from, address _tokenAddress, uint256 _amount) public nonReentrant {

        require(_tokenAddress == springTokenAddress || _tokenAddress == summerTokenAddress
                || _tokenAddress == autumnTokenAddress || _tokenAddress == winterTokenAddress,
                "Only Seasonal Tokens can be donated");

        require(msg.sender == _from, "Tokens must be donated by the address that owns them.");

        SafeERC20.safeTransferFrom(ERC20Interface(_tokenAddress), _from, address(this), _amount);

        allocateIncomingTokensToTradingPairs(_tokenAddress, _amount);
        emit Donate(_from, _tokenAddress, _amount);

    }

    function onERC721Received(address _operator, address _from, uint256 _liquidityTokenId, bytes calldata _data)
                             external override returns(bytes4) {

        require(msg.sender == address(nonFungiblePositionManager),
                "Only Uniswap v3 liquidity tokens can be deposited");

        LiquidityToken memory liquidityToken = getLiquidityToken(_liquidityTokenId);

        liquidityToken.owner = _from;
        liquidityToken.depositTime = block.timestamp;

        liquidityToken.position = tokenOfOwnerByIndex[_from].length;
        tokenOfOwnerByIndex[_from].push(_liquidityTokenId);

        liquidityToken.initialCumulativeSpringTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[liquidityToken.seasonalToken][springTokenAddress];

        liquidityToken.initialCumulativeSummerTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[liquidityToken.seasonalToken][summerTokenAddress];

        liquidityToken.initialCumulativeAutumnTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[liquidityToken.seasonalToken][autumnTokenAddress];

        liquidityToken.initialCumulativeWinterTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[liquidityToken.seasonalToken][winterTokenAddress];

        liquidityTokens[_liquidityTokenId] = liquidityToken;
        totalLiquidity[liquidityToken.seasonalToken] += liquidityToken.liquidity;

        emit Deposit(_from, _liquidityTokenId);

        _data; _operator; // suppress unused variable compiler warnings
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    function getLiquidityToken(uint256 _tokenId) internal view returns(LiquidityToken memory) {

        LiquidityToken memory liquidityToken;
        address token0;
        address token1;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidity;
        uint24 fee;

        (token0, token1, fee, tickLower, tickUpper, liquidity) = getPositionDataForLiquidityToken(_tokenId);
        liquidityToken.liquidity = liquidity;

        if (token0 == wethAddress)
            liquidityToken.seasonalToken = token1;
        else if (token1 == wethAddress)
            liquidityToken.seasonalToken = token0;

        require(liquidityToken.seasonalToken == springTokenAddress ||
                liquidityToken.seasonalToken == summerTokenAddress ||
                liquidityToken.seasonalToken == autumnTokenAddress ||
                liquidityToken.seasonalToken == winterTokenAddress,
                "Invalid trading pair");

        require(tickLower == REQUIRED_TICK_LOWER && tickUpper == REQUIRED_TICK_UPPER,
                "Liquidity must cover full range of prices");

        require(fee == 100, "Fee tier must be 0.01%");

        return liquidityToken;
    }

    function getPositionDataForLiquidityToken(uint256 _tokenId) internal view
      returns (address, address, uint24, int24, int24, uint256)
    {
        address token0;
        address token1;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidity;
        uint24 fee;

        (,, token0, token1, fee, tickLower, tickUpper, liquidity,,,,)
            = nonFungiblePositionManager.positions(_tokenId);

        return (token0, token1, fee, tickLower, tickUpper, liquidity);
    }

    function setCumulativeSpringTokensFarmedToCurrentValue(uint256 _liquidityTokenId, address _seasonalToken) internal {
        liquidityTokens[_liquidityTokenId].initialCumulativeSpringTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[_seasonalToken][springTokenAddress];
    }

    function setCumulativeSummerTokensFarmedToCurrentValue(uint256 _liquidityTokenId, address _seasonalToken) internal {
        liquidityTokens[_liquidityTokenId].initialCumulativeSummerTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[_seasonalToken][summerTokenAddress];
    }

    function setCumulativeAutumnTokensFarmedToCurrentValue(uint256 _liquidityTokenId, address _seasonalToken) internal {
        liquidityTokens[_liquidityTokenId].initialCumulativeAutumnTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[_seasonalToken][autumnTokenAddress];
    }

    function setCumulativeWinterTokensFarmedToCurrentValue(uint256 _liquidityTokenId, address _seasonalToken) internal {
        liquidityTokens[_liquidityTokenId].initialCumulativeWinterTokensFarmed
            = cumulativeTokensFarmedPerUnitLiquidity[_seasonalToken][winterTokenAddress];
    }

    function getPayoutSize(uint256 _liquidityTokenId, address _farmedSeasonalToken,
                           address _tradingPairSeasonalToken) internal view returns (uint256) {

        uint256 initialCumulativeTokensFarmed;

        if (_farmedSeasonalToken == springTokenAddress)
            initialCumulativeTokensFarmed = liquidityTokens[_liquidityTokenId].initialCumulativeSpringTokensFarmed;
        else if (_farmedSeasonalToken == summerTokenAddress)
            initialCumulativeTokensFarmed = liquidityTokens[_liquidityTokenId].initialCumulativeSummerTokensFarmed;
        else if (_farmedSeasonalToken == autumnTokenAddress)
            initialCumulativeTokensFarmed = liquidityTokens[_liquidityTokenId].initialCumulativeAutumnTokensFarmed;
        else
            initialCumulativeTokensFarmed = liquidityTokens[_liquidityTokenId].initialCumulativeWinterTokensFarmed;

        uint256 tokensFarmedPerUnitLiquiditySinceDeposit
            = cumulativeTokensFarmedPerUnitLiquidity[_tradingPairSeasonalToken][_farmedSeasonalToken]
              - initialCumulativeTokensFarmed;

        return (tokensFarmedPerUnitLiquiditySinceDeposit
                * liquidityTokens[_liquidityTokenId].liquidity) / (2 ** 128);
    }

    function getPayoutSizes(uint256 _liquidityTokenId) external view returns (uint256, uint256, uint256, uint256) {

        address tradingPairSeasonalToken = liquidityTokens[_liquidityTokenId].seasonalToken;

        uint256 springPayout = getPayoutSize(_liquidityTokenId, springTokenAddress, tradingPairSeasonalToken);
        uint256 summerPayout = getPayoutSize(_liquidityTokenId, summerTokenAddress, tradingPairSeasonalToken);
        uint256 autumnPayout = getPayoutSize(_liquidityTokenId, autumnTokenAddress, tradingPairSeasonalToken);
        uint256 winterPayout = getPayoutSize(_liquidityTokenId, winterTokenAddress, tradingPairSeasonalToken);

        return (springPayout, summerPayout, autumnPayout, winterPayout);
    }

    function harvestSpring(uint256 _liquidityTokenId, address _tradingPairSeasonalToken) internal returns(uint256) {

        uint256 amount = getPayoutSize(_liquidityTokenId, springTokenAddress, _tradingPairSeasonalToken);
        setCumulativeSpringTokensFarmedToCurrentValue(_liquidityTokenId, _tradingPairSeasonalToken);
        return amount;
    }

    function harvestSummer(uint256 _liquidityTokenId, address _tradingPairSeasonalToken) internal returns(uint256) {

        uint256 amount = getPayoutSize(_liquidityTokenId, summerTokenAddress, _tradingPairSeasonalToken);
        setCumulativeSummerTokensFarmedToCurrentValue(_liquidityTokenId, _tradingPairSeasonalToken);
        return amount;
    }

    function harvestAutumn(uint256 _liquidityTokenId, address _tradingPairSeasonalToken) internal returns(uint256) {

        uint256 amount = getPayoutSize(_liquidityTokenId, autumnTokenAddress, _tradingPairSeasonalToken);
        setCumulativeAutumnTokensFarmedToCurrentValue(_liquidityTokenId, _tradingPairSeasonalToken);
        return amount;
    }

    function harvestWinter(uint256 _liquidityTokenId, address _tradingPairSeasonalToken) internal returns(uint256) {

        uint256 amount = getPayoutSize(_liquidityTokenId, winterTokenAddress, _tradingPairSeasonalToken);
        setCumulativeWinterTokensFarmedToCurrentValue(_liquidityTokenId, _tradingPairSeasonalToken);
        return amount;
    }

    function harvestAll(uint256 _liquidityTokenId, address _tradingPairSeasonalToken)
            internal returns (uint256, uint256, uint256, uint256) {

        uint256 springAmount = harvestSpring(_liquidityTokenId, _tradingPairSeasonalToken);
        uint256 summerAmount = harvestSummer(_liquidityTokenId, _tradingPairSeasonalToken);
        uint256 autumnAmount = harvestAutumn(_liquidityTokenId, _tradingPairSeasonalToken);
        uint256 winterAmount = harvestWinter(_liquidityTokenId, _tradingPairSeasonalToken);

        return (springAmount, summerAmount, autumnAmount, winterAmount);
    }

    function sendHarvestedTokensToOwner(address _tokenOwner, uint256 _springAmount, uint256 _summerAmount,
                                        uint256 _autumnAmount, uint256 _winterAmount) internal {

        if (_springAmount > 0)
            ERC20Interface(springTokenAddress).transfer(_tokenOwner, _springAmount);
        if (_summerAmount > 0)
            ERC20Interface(summerTokenAddress).transfer(_tokenOwner, _summerAmount);
        if (_autumnAmount > 0)
            ERC20Interface(autumnTokenAddress).transfer(_tokenOwner, _autumnAmount);
        if (_winterAmount > 0)
            ERC20Interface(winterTokenAddress).transfer(_tokenOwner, _winterAmount);
    }

    function harvest(uint256 _liquidityTokenId) external {

        LiquidityToken storage liquidityToken = liquidityTokens[_liquidityTokenId];
        require(msg.sender == liquidityToken.owner, "Only owner can harvest");

        (uint256 springAmount,
         uint256 summerAmount,
         uint256 autumnAmount,
         uint256 winterAmount) = harvestAll(_liquidityTokenId, liquidityToken.seasonalToken);

        emit Harvest(msg.sender, _liquidityTokenId, springAmount, summerAmount, autumnAmount, winterAmount);

        sendHarvestedTokensToOwner(msg.sender, springAmount, summerAmount, autumnAmount, winterAmount);
    }

    function canWithdraw(uint256 _liquidityTokenId) public view returns (bool) {

        uint256 depositTime = liquidityTokens[_liquidityTokenId].depositTime;
        uint256 timeSinceDepositTime = block.timestamp - depositTime;
        uint256 daysSinceDepositTime = timeSinceDepositTime / (24 * 60 * 60);

        return (daysSinceDepositTime) % (WITHDRAWAL_UNAVAILABLE_DAYS + WITHDRAWAL_AVAILABLE_DAYS)
                    >= WITHDRAWAL_UNAVAILABLE_DAYS;
    }

    function nextWithdrawalTime(uint256 _liquidityTokenId) external view returns (uint256) {

        uint256 depositTime = liquidityTokens[_liquidityTokenId].depositTime;
        uint256 timeSinceDepositTime = block.timestamp - depositTime;
        uint256 withdrawalUnavailableTime = WITHDRAWAL_UNAVAILABLE_DAYS * 24 * 60 * 60;
        uint256 withdrawalAvailableTime = WITHDRAWAL_AVAILABLE_DAYS * 24 * 60 * 60;

        if (timeSinceDepositTime < withdrawalUnavailableTime)
            return depositTime + withdrawalUnavailableTime;

        uint256 numberOfWithdrawalCyclesUntilNextWithdrawalTime
                    = 1 + (timeSinceDepositTime - withdrawalUnavailableTime)
                          / (withdrawalUnavailableTime + withdrawalAvailableTime);

        return depositTime + withdrawalUnavailableTime
                           + numberOfWithdrawalCyclesUntilNextWithdrawalTime
                             * (withdrawalUnavailableTime + withdrawalAvailableTime);
    }

    function withdraw(uint256 _liquidityTokenId) external {

        require(canWithdraw(_liquidityTokenId), "This token cannot be withdrawn at this time");

        LiquidityToken memory liquidityToken = liquidityTokens[_liquidityTokenId];

        require(msg.sender == liquidityToken.owner, "Only owner can withdraw");

        (uint256 springAmount,
         uint256 summerAmount,
         uint256 autumnAmount,
         uint256 winterAmount) = harvestAll(_liquidityTokenId, liquidityToken.seasonalToken);

        totalLiquidity[liquidityToken.seasonalToken] -= liquidityToken.liquidity;
        removeTokenFromListOfOwnedTokens(msg.sender, liquidityToken.position, _liquidityTokenId);

        emit Harvest(msg.sender, _liquidityTokenId, springAmount, summerAmount, autumnAmount, winterAmount);
        emit Withdraw(msg.sender, _liquidityTokenId);

        sendHarvestedTokensToOwner(msg.sender, springAmount, summerAmount, autumnAmount, winterAmount);
        nonFungiblePositionManager.selfSafeTransferFrom(address(this), liquidityToken.owner, _liquidityTokenId);
    }

    function removeTokenFromListOfOwnedTokens(address _owner, uint256 _index, uint256 _liquidityTokenId) internal {

        // to remove an element from a list efficiently, we copy the last element in the list into the
        // position of the element we want to remove, and then remove the last element from the list

        uint256 length = tokenOfOwnerByIndex[_owner].length;
        if (length > 1) {
            uint256 liquidityTokenIdOfLastTokenInList = tokenOfOwnerByIndex[_owner][length - 1];
            LiquidityToken memory lastToken = liquidityTokens[liquidityTokenIdOfLastTokenInList];
            lastToken.position = _index;
            tokenOfOwnerByIndex[_owner][_index] = liquidityTokenIdOfLastTokenInList;
            liquidityTokens[liquidityTokenIdOfLastTokenInList] = lastToken;
        }
        tokenOfOwnerByIndex[_owner].pop();
        delete liquidityTokens[_liquidityTokenId];
    }

    function collectAllFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position, meaning it must be a deposit

        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonFungiblePositionManager.CollectParams memory params =
        INonFungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonFungiblePositionManager.collect(params);
        _sendToOwner(tokenId, amount0, amount1);
    }


    function _sendToOwner(
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        // get owner of contract
        address token0;
        address token1;
        address owner = liquidityTokens[_tokenId].owner;
        ( token0, token1,,,, ) = getPositionDataForLiquidityToken(_tokenId);

        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, _amount0);
        TransferHelper.safeTransfer(token1, owner, _amount1);
    }

}
