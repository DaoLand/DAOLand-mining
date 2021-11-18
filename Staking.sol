// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Staking is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct CommonStakingInfo {
        uint256 startingRewardsPerEpoch;
        uint256 startTime;
        uint256 epochDuration;
        uint256 rewardsPerDeposit;
        uint256 rewardProduced;
        uint256 produceTime;
        uint256 halvingDuration;
        uint256 totalStaked;
        uint256 totalDistributed;
        uint256 fineCooldownTime;
        uint256 finePercent;
        uint256 accumulatedFine;
        address depositToken;
        address rewardToken;
    }

    struct Staker {
        uint256 amount;
        uint256 rewardAllowed;
        uint256 rewardDebt;
        uint256 distributed;
        uint256 noFineUnstakeOpenSince;
        uint256 requestedUnstakeAmount;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bool public isStakeAvailable;
    bool public isUnstakeAvailable;
    bool public isClaimAvailable;

    // BEP20 DLD token staking to the contract
    IERC20 public depositToken;
    // BEP20 DLS token earned by stakers as reward_.
    IERC20 public rewardToken;

    uint256 public startingRewardsPerEpoch;
    uint256 public startTime;
    uint256 public epochDuration;

    uint256 public rewardsPerDeposit; // tps
    uint256 public rewardProduced;
    uint256 public produceTime;
    uint256 public halvingDuration;

    uint256 public totalStaked;
    uint256 public totalDistributed;

    uint256 public constant precision = 10**20;
    uint256 public finePercent; // calcs with precision
    uint256 public fineCooldownTime;
    uint256 public accumulatedFine;

    mapping(address => Staker) public stakers;

    event TokensStaked(uint256 amount, uint256 time, address indexed sender);
    event TokensClaimed(uint256 amount, uint256 time, address indexed sender);
    event TokensUnstaked(
        uint256 amount,
        uint256 fineAmount,
        uint256 time,
        address indexed sender
    );
    event RequestTokensUnstake(
        uint256 amount,
        uint256 requestApplyTimestamp,
        uint256 time,
        address indexed sender
    );

    /**
     *@param _rewardsPerEpoch number of rewards per epoch
     *@param _startTime staking start time
     *@param _epochDuration epoch duration in seconds
     *@param _halvingDuration the time after which the number of rewards is halved
     *@param _fineCoolDownTime time after which you can unstake without commission
     *@param _finePercent commission for withdrawing funds without request
     *@param _depositToken address deposit token
     *@param _rewardToken address reward token
     */
    constructor(
        uint256 _rewardsPerEpoch,
        uint256 _startTime,
        uint256 _epochDuration,
        uint256 _halvingDuration,
        uint256 _fineCoolDownTime,
        uint256 _finePercent,
        address _depositToken,
        address _rewardToken
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

        startingRewardsPerEpoch = _rewardsPerEpoch;
        startTime = _startTime;

        epochDuration = _epochDuration;

        produceTime = _startTime;
        halvingDuration = _halvingDuration;

        fineCooldownTime = _fineCoolDownTime;
        finePercent = _finePercent;

        rewardToken = IERC20(_rewardToken);
        depositToken = IERC20(_depositToken);
    }

    /**
     *@dev change FineCoolDownTime
     *@param _fineCoolDownTime time after which you can unstake without commission
     */
    function changeParamFineCoolDownTime(uint256 _fineCoolDownTime)
        external
        onlyRole(ADMIN_ROLE)
    {
        fineCooldownTime = _fineCoolDownTime;
    }

    /**
     *@dev change FinePercent
     *@param _finePercent fine percent
     */
    function changeParamFinePercent(uint256 _finePercent)
        external
        onlyRole(ADMIN_ROLE)
    {
        finePercent = _finePercent;
    }

    /**
     *@dev take the commission, can only be used by the admin
     */
    function withdrawFine() external onlyRole(ADMIN_ROLE) {
        require(accumulatedFine > 0, "S:afz"); // "Staking: accumulated fine is zero"
        IERC20(depositToken).safeTransfer(msg.sender, accumulatedFine);
        accumulatedFine = 0;
    }

    /**
     *@dev withdraw token to sender by token address, if sender is admin
     *@param token address token
     *@param amount amount
     */
    function withdrawToken(address token, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
    {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     *@dev set staking state (in terms of STM)
     *@param _isStakeAvailable block stake
     *@param _isUnstakeAvailable block unstake
     *@param _isClaimAvailable block claim
     */
    function setAvailability(
        bool _isStakeAvailable,
        bool _isUnstakeAvailable,
        bool _isClaimAvailable
    ) external onlyRole(ADMIN_ROLE) {
        if (isStakeAvailable != _isStakeAvailable)
            isStakeAvailable = _isStakeAvailable;
        if (isUnstakeAvailable != _isUnstakeAvailable)
            isUnstakeAvailable = _isUnstakeAvailable;
        if (isClaimAvailable != _isClaimAvailable)
            isClaimAvailable = _isClaimAvailable;
    }

    /**
     *@dev make stake
     *@param amount how many tokens to send
     */
    function stake(uint256 amount) external {
        require(!isStakeAvailable, "S:sna"); //  "Staking: stake is not available now"
        require(block.timestamp > startTime, "S:stn"); // "Staking: stake time has not come yet"

        IERC20(depositToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        if (totalStaked > 0) update();

        Staker storage staker = stakers[msg.sender];

        staker.rewardDebt += (amount * rewardsPerDeposit) / 1e20;
        totalStaked += amount;
        staker.amount += amount;

        update();
        emit TokensStaked(amount, block.timestamp, msg.sender);
    }

    /**
     *@dev pick up a stake
     *@param amount how many tokens to pick up
     */
    function unstake(uint256 amount) external nonReentrant {
        require(!isUnstakeAvailable, "S:una"); // "Staking: unstake is not available now"

        Staker storage staker = stakers[msg.sender];
        require(staker.amount >= amount, "S:netu"); // "Staking: not enough tokens to unstake"

        update();

        staker.rewardAllowed += ((amount * rewardsPerDeposit) / 1e20);
        staker.amount -= amount;

        uint256 unstakeAmount;
        uint256 fineAmount;

        if (
            staker.noFineUnstakeOpenSince > block.timestamp ||
            amount > staker.requestedUnstakeAmount
        ) {
            fineAmount = (finePercent * amount) / precision;
            unstakeAmount = amount - fineAmount;
            accumulatedFine += fineAmount;
        } else {
            unstakeAmount = amount;
            staker.requestedUnstakeAmount -= amount;
        }

        IERC20(depositToken).safeTransfer(msg.sender, unstakeAmount);
        totalStaked -= amount;

        emit TokensUnstaked(
            unstakeAmount,
            fineAmount,
            block.timestamp,
            msg.sender
        );
    }

    /**
     *@dev make a request for withdrawal of funds without commission
     *@param amount amount
     */
    function requestUnstakeWithoutFine(uint256 amount) external {
        require(!isUnstakeAvailable, "S:una"); // "Staking: unstake is not available now"

        Staker storage staker = stakers[msg.sender];
        require(staker.amount >= amount, "S:netu"); // "Staking: not enough tokens to unstake"
        require(staker.requestedUnstakeAmount <= amount, "S:ahr"); // "Staking: you already have request with greater or equal amount"

        staker.noFineUnstakeOpenSince = block.timestamp + fineCooldownTime;
        staker.requestedUnstakeAmount = amount;

        emit RequestTokensUnstake(
            amount,
            staker.noFineUnstakeOpenSince,
            block.timestamp,
            msg.sender
        );
    }

    /**
     *  @dev claim available rewards
     */
    function claim() external nonReentrant {
        require(!isClaimAvailable, "S:cna"); // "Staking: claim is not available now"
        if (totalStaked > 0) update();

        uint256 reward = _calcReward(msg.sender, rewardsPerDeposit);
        require(reward > 0, "S:nc"); // "Staking: nothing to claim"

        Staker storage staker = stakers[msg.sender];

        staker.distributed += reward;
        totalDistributed += reward;

        IERC20(rewardToken).safeTransfer(msg.sender, reward);

        emit TokensClaimed(reward, block.timestamp, msg.sender);
    }

    /**
     *@dev updates the value "rewardProduced" must be called before getting
     * the actual information about the number of rewards received
     */
    function update() public {
        uint256 rewardProducedAtNow_ = _produced();
        if (rewardProducedAtNow_ > rewardProduced) {
            uint256 producedNew_ = rewardProducedAtNow_ - rewardProduced;
            if (totalStaked > 0)
                rewardsPerDeposit =
                    rewardsPerDeposit +
                    ((producedNew_ * 1e20) / totalStaked);
            rewardProduced += producedNew_;
        }
    }

    /**
     *@dev get information about staking
     *@return returning structure CommonStakingInfo
     */
    function getCommonStakingInfo()
        external
        view
        returns (CommonStakingInfo memory)
    {
        return
            CommonStakingInfo({
                startingRewardsPerEpoch: startingRewardsPerEpoch,
                startTime: startTime,
                epochDuration: epochDuration,
                rewardsPerDeposit: rewardsPerDeposit,
                rewardProduced: rewardProduced,
                produceTime: produceTime,
                halvingDuration: halvingDuration,
                totalStaked: totalStaked,
                totalDistributed: totalDistributed,
                fineCooldownTime: fineCooldownTime,
                finePercent: finePercent,
                accumulatedFine: accumulatedFine,
                depositToken: address(depositToken),
                rewardToken: address(rewardToken)
            });
    }

    /**
     *@dev get information about user
     *@param _user address user
     *@return returning structure Staker
     */
    function getUserInfo(address _user) external view returns (Staker memory) {
        Staker memory staker = stakers[_user];
        staker.rewardAllowed = getRewardInfo(_user);
        return staker;
    }

    /**
     *@dev returns available reward of staker
     *@param _user address user
     *@return returns available reward
     */
    function getRewardInfo(address _user) public view returns (uint256) {
        uint256 tempRewardPerDeposit = rewardsPerDeposit;
        if (totalStaked > 0) {
            uint256 rewardProducedAtNow = _produced();
            if (rewardProducedAtNow > rewardProduced) {
                uint256 producedNew = rewardProducedAtNow - rewardProduced;
                tempRewardPerDeposit += ((producedNew * 1e20) / totalStaked);
            }
        }
        uint256 reward = _calcReward(_user, tempRewardPerDeposit);

        return reward;
    }

    /// @dev calculates the necessary parameters for staking
    function _produced() internal view returns (uint256) {
        uint256 halvingPeriodsQuantity = (block.timestamp - produceTime) /
            halvingDuration;

        require(
            2**halvingPeriodsQuantity <= startingRewardsPerEpoch,
            "Staking: game over"
        );
        uint256 epochQuantity = ((block.timestamp - produceTime) /
            epochDuration) * precision;
        uint256 epochesInHalvingPeriod = (halvingDuration * precision) /
            epochDuration;

        uint256 produced;
        for (uint256 i = 0; i <= halvingPeriodsQuantity; i++) {
            if (i != halvingPeriodsQuantity) {
                // calc reward for every epoches in halving period
                produced +=
                    (startingRewardsPerEpoch / (2**i)) *
                    epochesInHalvingPeriod;
            } else {
                // calc how much epoches is in last halving period
                produced +=
                    (startingRewardsPerEpoch / (2**i)) *
                    (epochQuantity % epochesInHalvingPeriod);
            }
        }
        return (produced / precision);
    }

    /**
     * @dev calculates available reward_
     */
    function _calcReward(address _user, uint256 _tps)
        internal
        view
        returns (uint256)
    {
        Staker memory staker = stakers[_user];
        return
            ((staker.amount * _tps) / 1e20) +
            staker.rewardAllowed -
            staker.distributed -
            staker.rewardDebt;
    }
}
