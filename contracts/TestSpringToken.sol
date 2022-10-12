//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./interfaces/ERC20.sol";
import "./interfaces/ERC918.sol";
import "./interfaces/Owned.sol";
import "./interfaces/ApproveAndCallFallBack.sol";
import "./libraries/SafeMath256.sol";

// ----------------------------------------------------------------------------

// Test Spring Token contract - same as Spring Token except:

//

// Added setters for variables and a new variable to record allowance notifications

//

// Most internal functions have been made public to allow testing

//

// contractCreationTime not declared immutable

//

// Increased MINIMUM_TARGET to test upper limit of difficulty

//

// Allowed transfers to the contract address to test the ability to rescue those funds

// ----------------------------------------------------------------------------



contract TestSpringToken is ERC20Interface, ERC918, Owned {

    using SafeMath256 for uint256;

    uint256 public notifiedAllowance;

    string private constant SYMBOL = "SPRING";

    string private constant NAME = "Spring Token";

    uint256 public constant TOKEN_IDENTIFIER = 1;

    uint8 public constant DECIMALS = 18;

    uint256 public constant TOTAL_SUPPLY = 33112800 * 10 ** 18;

    uint256 public constant INITIAL_REWARD = 168 * 10 ** 18;

    uint256 public constant MAX_REWARDS_AVAILABLE = 72; // no more than 72 rewards per mint

    uint256 public constant REWARD_INTERVAL = 600; // rewards every ten minutes on average

    uint256 public constant DURATION_OF_FIRST_ERA = (365 * 24 * 60 * 60 * 3) / 4; // 9 months

    uint256 public constant DURATION_OF_ERA = 3 * 365 * 24 * 60 * 60; // three years

    uint256 public constant MINIMUM_TARGET = (2 ** uint256(233) * 9) / 13; // was 2**16

    uint256 public constant MAXIMUM_TARGET = 2 ** 234;

    uint256 public contractCreationTime;

    uint256 public lastRewardBlockTime;

    uint256 public maxNumberOfRewardsPerMint;

    bytes32 private challengeNumber;

    uint256 private miningTarget;

    uint256 public tokensMinted;

    mapping(address => uint256) internal balances;

    mapping(address => mapping(address => uint256)) internal allowed;



    constructor() public {

        miningTarget = MAXIMUM_TARGET.div(2 ** 19);

        contractCreationTime = block.timestamp;
        lastRewardBlockTime = block.timestamp;

        maxNumberOfRewardsPerMint = 1;

        challengeNumber = _getNewChallengeNumber(0);

    }

    function name() public pure returns (string memory) {
        return NAME;
    }

    function symbol() public pure returns (string memory) {
        return SYMBOL;
    }

    function mint(uint256 nonce) override public returns (bool success) {

        uint256 _lastRewardBlockTime = lastRewardBlockTime;

        uint256 singleRewardAmount = _getMiningReward(_lastRewardBlockTime);

        // no more minting when reward reaches zero
        if (singleRewardAmount == 0) revert("Reward has reached zero");

        // the PoW must contain work that includes the challenge number and the msg.sender's address
        bytes32 digest = keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce));

        uint256 _miningTarget = miningTarget;
        // the digest must be smaller than the target
        if (uint256(digest) > _miningTarget) revert("Digest is larger than mining target");

        uint256 _previousMaxNumberOfRewards = maxNumberOfRewardsPerMint;
        uint256 numberOfRewardsToGive = _numberOfRewardsToGive(_miningTarget.div(uint256(digest)),
            _lastRewardBlockTime,
            _previousMaxNumberOfRewards,
            block.timestamp);
        uint256 totalRewardAmount = singleRewardAmount.add(numberOfRewardsToGive);

        uint256 _tokensMinted = _giveRewards(totalRewardAmount);

        _setNextMaxNumberOfRewards(numberOfRewardsToGive, _previousMaxNumberOfRewards);

        miningTarget = _adjustDifficulty(_miningTarget, _lastRewardBlockTime,
            numberOfRewardsToGive, block.timestamp);

        bytes32 newChallengeNumber = _getNewChallengeNumber(_tokensMinted);
        challengeNumber = newChallengeNumber;

        lastRewardBlockTime = block.timestamp;

        emit Mint(msg.sender, totalRewardAmount, _scheduledNumberOfRewards(block.timestamp),
            newChallengeNumber);

        return true;
    }

    function _numberOfRewardsAvailable(uint256 _lastRewardBlockTime,
        uint256 _previousMaxNumberOfRewards,
        uint256 currentTime) public pure returns (uint256) {

        uint256 numberAvailable = _previousMaxNumberOfRewards;
        uint256 intervalsSinceLastReward = (currentTime.sub(_lastRewardBlockTime)).div(REWARD_INTERVAL);

        if (intervalsSinceLastReward > numberAvailable)
            numberAvailable = intervalsSinceLastReward;

        if (numberAvailable > MAX_REWARDS_AVAILABLE)
            numberAvailable = MAX_REWARDS_AVAILABLE;

        return numberAvailable;
    }

    function _numberOfRewardsToGive(uint256 numberEarned, uint256 _lastRewardBlockTime,
        uint256 _previousMaxNumberOfRewards,
        uint256 currentTime) public pure returns (uint256) {

        uint256 numberAvailable = _numberOfRewardsAvailable(_lastRewardBlockTime,
            _previousMaxNumberOfRewards,
            currentTime);
        if (numberEarned < numberAvailable)
            return numberEarned;

        return numberAvailable;
    }

    function _giveRewards(uint256 totalReward) public returns (uint256) {

        balances[msg.sender] = balances[msg.sender].add(totalReward);
        uint256 _tokensMinted = tokensMinted.add(totalReward);
        tokensMinted = _tokensMinted;
        return _tokensMinted;
    }

    function _setNextMaxNumberOfRewards(uint256 numberOfRewardsGivenNow,
        uint256 _previousMaxNumberOfRewards) public {

        // the value of the rewards given to this miner presumably exceed the gas costs
        // for processing the transaction. the next miner can submit a proof of enough work
        // to claim up to the same number of rewards immediately, or, if gas costs have increased,
        // wait until the maximum number of rewards claimable has increased enough to overcome
        // the costs.

        if (numberOfRewardsGivenNow != _previousMaxNumberOfRewards)
            maxNumberOfRewardsPerMint = numberOfRewardsGivenNow;
    }

    // backwards compatible mint function
    function mint(uint256 _nonce, bytes32 _challengeDigest) external returns (bool) {

        bytes32 digest = keccak256(abi.encodePacked(challengeNumber, msg.sender, _nonce));
        require(digest == _challengeDigest, "Challenge digest does not match expected digest on token contract");

        return mint(_nonce);
    }

    function _getNewChallengeNumber(uint256 _tokensMinted) public view returns (bytes32) {

        // make the latest ethereum block hash a part of the next challenge

        // xor with a number unique to this token to avoid merged mining

        // xor with the number of tokens minted to ensure that the challenge changes
        // even if there are multiple mints in the same ethereum block

        return bytes32(uint256(blockhash(block.number.sub(1))) ^ _tokensMinted ^ TOKEN_IDENTIFIER);
    }


    function _scheduledNumberOfRewards(uint256 currentTime) public view returns (uint256) {
        return (currentTime.sub(contractCreationTime)).div(REWARD_INTERVAL);
    }

    function _adjustDifficulty(uint256 _miningTarget,
        uint256 _lastRewardBlockTime,
        uint256 rewardsGivenNow,
        uint256 currentTime) public pure returns (uint256){

        uint256 timeSinceLastReward = currentTime.sub(_lastRewardBlockTime);

        // we target a median interval of 10 minutes multiplied by log(2) ~ 61/88
        // this gives a mean interval of 10 minutes per reward

        if (timeSinceLastReward.mul(88) < rewardsGivenNow.mul(REWARD_INTERVAL).mul(61))
            _miningTarget = _miningTarget.mul(99).div(100);
        // slow down
        else
            _miningTarget = _miningTarget.mul(100).div(99);
        // speed up

        if (_miningTarget < MINIMUM_TARGET)
            _miningTarget = MINIMUM_TARGET;

        if (_miningTarget > MAXIMUM_TARGET)
            _miningTarget = MAXIMUM_TARGET;

        return _miningTarget;
    }


    function rewardEra(uint256 _time) public view returns (uint256) {

        uint256 timeSinceContractCreation = _time.sub(contractCreationTime);

        if (timeSinceContractCreation < DURATION_OF_FIRST_ERA)
            return 0;
        else
            return uint256(1).add((timeSinceContractCreation.sub(DURATION_OF_FIRST_ERA)).div(DURATION_OF_ERA));
    }

    function getAdjustmentInterval() public view override returns (uint256) {
        return REWARD_INTERVAL.mul(maxNumberOfRewardsPerMint);
    }

    function getChallengeNumber() public view override returns (bytes32) {
        return challengeNumber;
    }

    function getMiningDifficulty() public view override returns (uint256) {
        // 64 f's:         1234567890123456789012345678901234567890123456789012345678901234
        uint256 maxInt = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        return maxInt.div(miningTarget);
    }

    function getMiningTarget() public view override returns (uint256) {
        return miningTarget;
    }

    function getMiningReward() public view override returns (uint256) {

        // use the timestamp of the ethereum block that gave the last reward
        // because ethereum miners can manipulate the value of block.timestamp
        return _getMiningReward(lastRewardBlockTime);
    }

    function _getMiningReward(uint256 _time) public view returns (uint256) {
        return INITIAL_REWARD.div(2 ** rewardEra(_time));
    }

    function getNumberOfRewardsAvailable(uint256 currentTime) external view returns (uint256) {
        return _numberOfRewardsAvailable(lastRewardBlockTime,
            maxNumberOfRewardsPerMint,
            currentTime);
    }

    function getRewardAmountForAchievingTarget(uint256 targetAchieved, uint256 currentTime) external view returns (uint256) {
        uint256 numberOfRewardsToGive = _numberOfRewardsToGive(miningTarget.div(targetAchieved),
            lastRewardBlockTime,
            maxNumberOfRewardsPerMint,
            currentTime);
        return _getMiningReward(currentTime).mul(numberOfRewardsToGive);
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function totalSupply() public view override returns (uint256) {

        return tokensMinted;
    }


    // ------------------------------------------------------------------------

    // Get the token balance for account `tokenOwner`

    // ------------------------------------------------------------------------

    function balanceOf(address tokenOwner) public view override returns (uint256 balance) {

        return balances[tokenOwner];

    }



    // ------------------------------------------------------------------------

    // Transfer the balance from token owner's account to `to` account

    // - Owner's account must have sufficient balance to transfer

    // - 0 value transfers are allowed

    // ------------------------------------------------------------------------

    function transfer(address to, uint256 tokens) public override returns (bool success) {

        require(to != address(0), "Invalid address");
        // was require(to != address(0) && to != address(this), "Invalid address");

        balances[msg.sender] = balances[msg.sender].sub(tokens);

        balances[to] = balances[to].add(tokens);

        emit Transfer(msg.sender, to, tokens);

        return true;

    }



    // ------------------------------------------------------------------------

    // Token owner can approve for `spender` to transferFrom(...) `tokens`

    // from the token owner's account

    //

    // Warning: This function is vulnerable to double-spend attacks and is

    // included for backwards compatibility. Use safeApprove instead.

    // ------------------------------------------------------------------------

    function approve(address spender, uint256 tokens) public override returns (bool success) {

        require(spender != address(0) && spender != address(this), "Invalid address");

        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);

        return true;

    }



    // ------------------------------------------------------------------------

    // Allow token owner to cancel the approval if the approved amount changes from its last

    // known value before this transaction is processed. This allows the owner to avoid

    // unintentionally re-approving funds that have already been spent.

    // ------------------------------------------------------------------------

    function safeApprove(address spender, uint256 previousAllowance, uint256 newAllowance) external returns (bool success) {

        require(allowed[msg.sender][spender] == previousAllowance,
            "Current spender allowance does not match specified value");

        return approve(spender, newAllowance);
    }



    // ------------------------------------------------------------------------

    // Transfer `tokens` from the `from` account to the `to` account

    //

    // The calling account must already have sufficient tokens approve(...)-d

    // for spending from the `from` account and

    // - From account must have sufficient balance to transfer

    // - Spender must have sufficient allowance to transfer

    // - 0 value transfers are allowed

    // ------------------------------------------------------------------------

    function transferFrom(address from, address to, uint256 tokens) public override returns (bool success) {

        require(to != address(0) && to != address(this), "Invalid address");

        balances[from] = balances[from].sub(tokens);

        allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);

        balances[to] = balances[to].add(tokens);

        emit Transfer(from, to, tokens);

        return true;

    }



    // ------------------------------------------------------------------------

    // Returns the amount of tokens approved by the owner that can be

    // transferred to the spender's account

    // ------------------------------------------------------------------------

    function allowance(address tokenOwner, address spender) public view override returns (uint256 remaining){

        return allowed[tokenOwner][spender];

    }


    // ------------------------------------------------------------------------

    // Token owner can approve for `spender` to transferFrom(...) `tokens`

    // from the token owner's account. The `spender` contract function

    // `receiveApproval(...)` is then executed. This is vulnerable to double-spend attacks

    // when called directly, so it is declared internal and called by safeApproveAndCall

    // ------------------------------------------------------------------------

    function approveAndCall(address spender, uint256 tokens, bytes memory data) public returns (bool success) {

        // was require(spender != address(0) && spender != address(this), "Invalid address");
        // approvals to the test contract are allowed for testing
        require(spender != address(0), "Invalid address");

        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);

        ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, address(this), data);

        return true;

    }


    // ------------------------------------------------------------------------

    // Allow safe approvals with calls to receiving contract

    // ------------------------------------------------------------------------

    function safeApproveAndCall(address spender, uint256 previousAllowance,
        uint256 newAllowance, bytes calldata data) external returns (bool success) {

        require(allowed[msg.sender][spender] == previousAllowance,
            "Current spender allowance does not match specified value");

        return approveAndCall(spender, newAllowance, data);
    }


    // ------------------------------------------------------------------------

    // Owner can transfer out any accidentally sent ERC20 tokens

    // ------------------------------------------------------------------------

    function transferAnyERC20Token(address tokenAddress, uint256 tokens) external onlyOwner returns (bool success) {

        return ERC20Interface(tokenAddress).transfer(owner, tokens);

    }


    // functions for unit testing

    function setMaxNumberOfRewards(uint256 _maxNumberOfRewards) public {
        maxNumberOfRewardsPerMint = _maxNumberOfRewards;
    }

    function setMiningTarget(uint256 _miningTarget) public {
        miningTarget = _miningTarget;
    }

    function setChallengeNumber(bytes32 _challengeNumber) public {
        challengeNumber = _challengeNumber;
    }

    function setBalance(address _address, uint256 balance) public {
        balances[_address] = balance;
    }

    function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public {
        notifiedAllowance = tokens;
        from;
        tokens;
        token;
        data;
        // suppress compiler warnings about unused variables
    }


}