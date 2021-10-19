// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Staking is AccessControl, ReentrancyGuard {
	using SafeERC20 for IERC20;
	
	bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
	
	struct Staker {
		uint256 amount;
		uint256 rewardAllowed;
		uint256 rewardDebt;
		uint256 distributed;
		uint256 unstakeRequestApplyTimestamp;
		uint256 unstakeRequestAmount;
	}
	
	mapping(address => Staker) public stakers;
	
	// ERC20 DLD token staking to the contract
	// and DLS token earned by stakers as reward.
	ERC20 public depositToken;
	ERC20 public rewardToken;
	
	// Common contract configuration variables.
	uint256 public rewardsPerEpoch;
	uint256 public startTime;
	uint256 public epochDuration;
	
	uint256 public rewardsPerDeposit;
	uint256 public rewardProduced;
	uint256 public produceTime;
	uint256 public halvingDuration;
	
	uint256 public totalStaked;
	uint256 public totalDistributed;
	
	uint256 public fineDuration;
	uint256 public finePercent;
	uint256 public accumulatedFine;
	uint256 public constant precision = 10 ** 20;
	
	bool public isStakeAvailable = true;
	bool public isUnstakeAvailable = true;
	bool public isClaimAvailable = true;
	
	event tokensStaked(uint256 amount, uint256 time, address indexed sender);
	event tokensClaimed(uint256 amount, uint256 time, address indexed sender);
	event tokensUnstaked(
		uint256 amount,
		uint256 fineAmount,
		uint256 time,
		address indexed sender
	);
	event tokensUnstakeRequest(
		uint256 amount,
		uint256 requestApplyTimestamp,
		uint256 time,
		address indexed sender
	);
	
	constructor(
		uint256 _rewardsPerEpoch,
		uint256 _startTime,
		uint256 _epochDuration,
		uint256 _halvingDuration,
		uint256 _fineDuration,
		uint256 _finePercent,
		address _depositToken,
		address _rewardToken
	) public {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(ADMIN_ROLE, msg.sender);
		_setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
		
		require(_rewardsPerEpoch > 0, "Staking: amount of reward must be positive");
		
		rewardsPerEpoch = _rewardsPerEpoch;
		startTime = _startTime;
		
		epochDuration = _epochDuration;
		
		produceTime = _startTime;
		halvingDuration = _halvingDuration;
		
		fineDuration = _fineDuration;
		finePercent = _finePercent;
		
		rewardToken = ERC20(_rewardToken);
		depositToken = ERC20(_depositToken);
	}
	
	/**
	 * @dev Calculates the necessary parameters for staking
	 *
	 */
	function produced() private view returns (uint256) {
		uint256 epochCount = (block.timestamp - produceTime) / epochDuration * precision; // epochCount need to floor
		uint256 epochCountByHalving = halvingDuration * precision / epochDuration;
		uint256 halvingCount = (block.timestamp - produceTime) / halvingDuration;
		uint256 produced;
		for (uint256 i = 0; i <= halvingCount; i++) {
			if (i == halvingCount) {
				produced += (rewardsPerEpoch / (2 ** i)) * (epochCount % epochCountByHalving);
			} else {
				produced += (rewardsPerEpoch / (2 ** i)) * epochCountByHalving;
			}
		}
		return (produced / precision);
	}
	
	function update() public {
		uint256 rewardProducedAtNow = produced();
		if (rewardProducedAtNow > rewardProduced) {
			uint256 producedNew = rewardProducedAtNow - rewardProduced;
			if (totalStaked > 0) {
				rewardsPerDeposit = rewardsPerDeposit + producedNew * 1e20 / totalStaked;
			}
			rewardProduced += producedNew;
		}
	}
	
	/**
	 * @dev stake
	 *
	 * Parameters:
	 *
	 * - `_amount` - stake amount
	 */
	function stake(uint256 _amount) public {
		require(isStakeAvailable, "Staking: stake is not available now");
		require(
			block.timestamp > startTime,
			"Staking: stake time has not come yet"
		);
		Staker storage staker = stakers[msg.sender];
		
		// Transfer specified amount of staking tokens to the contract
		IERC20(depositToken).safeTransferFrom(
			msg.sender,
			address(this),
			_amount
		);
		
		if (totalStaked > 0) {
			update();
		}
		staker.rewardDebt += (_amount * rewardsPerDeposit) / 1e20;
		
		
		totalStaked += _amount;
		staker.amount += _amount;
		
		update();
		emit tokensStaked(_amount, block.timestamp, msg.sender);
	}
	
	function unstakeWithoutFineRequest(uint256 amount) public payable {
		require(isUnstakeAvailable, "Staking: unstake is not available now");
		Staker storage staker = stakers[msg.sender];
		require(
			staker.amount >= amount,
			"Staking: not enough tokens to unstake"
		);
		
		require(
			staker.unstakeRequestAmount <= amount,
			"Staking: you already have request with greater or equal amount"
		);
		
		staker.unstakeRequestApplyTimestamp = block.timestamp + fineDuration;
		staker.unstakeRequestAmount = amount;
		emit tokensUnstakeRequest(amount, staker.unstakeRequestApplyTimestamp, block.timestamp, msg.sender);
	}
	
	/**
	 * @dev unstake - return staked amount
	 *
	 * Parameters:
	 *
	 * - `_amount` - stake amount
	 */
	
	function unstake(uint256 _amount) public nonReentrant payable {
		require(isUnstakeAvailable, "Staking: unstake is not available now");
		Staker storage staker = stakers[msg.sender];
		
		require(
			staker.amount >= _amount,
			"Staking: not enough tokens to unstake"
		);
		
		update();
		
		staker.rewardAllowed += (_amount * rewardsPerDeposit / 1e20);
		staker.amount -= _amount;
		
		uint256 unstakeAmount;
		uint256 fineAmount;

		if (
			block.timestamp > staker.unstakeRequestApplyTimestamp
			|| _amount > staker.unstakeRequestAmount
			|| staker.unstakeRequestApplyTimestamp == 0
			|| staker.unstakeRequestAmount == 0
		) {
			fineAmount = finePercent * _amount / precision;
			unstakeAmount = _amount - fineAmount;
			accumulatedFine += fineAmount;
			if (
				staker.unstakeRequestApplyTimestamp == 0
				|| staker.unstakeRequestAmount == 0
			) {
				staker.unstakeRequestApplyTimestamp = 0;
				staker.unstakeRequestAmount = 0;
			}
		} else {
			unstakeAmount = _amount;
		}
		
		IERC20(depositToken).safeTransfer(msg.sender, unstakeAmount);
		totalStaked -= _amount;
	
		emit tokensUnstaked(unstakeAmount, fineAmount, block.timestamp, msg.sender);
	}
	
	/**
	 * @dev calcReward - calculates available reward
	 */
	function calcReward(address stakerAddress, uint256 _tps)
	private
	view
	returns (uint256)
	{
		Staker memory staker = stakers[stakerAddress];
		return ((staker.amount * _tps) / 1e20) + staker.rewardAllowed - staker.distributed - staker.rewardDebt;
	}
	
	/**
	 * @dev claim available rewards
	 */
	function claim() public nonReentrant {
		require(isClaimAvailable, "Staking: claim is not available now");
		if (totalStaked > 0) {
			update();
		}
		
		uint256 reward = calcReward(msg.sender, rewardsPerDeposit);
		require(reward > 0, "Staking: nothing to claim");
		
		Staker storage staker = stakers[msg.sender];
		
		staker.distributed += reward;
		totalDistributed += reward;
		
		IERC20(rewardToken).safeTransfer(msg.sender, reward);
		emit tokensClaimed(reward, block.timestamp, msg.sender);
	}
	
	/**
	 * @dev getClaim - returns available reward of `_staker`
	 */
	function getClaim(address _staker) public view returns (uint256 reward) {
		uint256 _rewardsPerDeposit = rewardsPerDeposit;
		if (totalStaked > 0) {
			uint256 rewardProducedAtNow = produced();
			if (rewardProducedAtNow > rewardProduced) {
				uint256 producedNew = rewardProducedAtNow - rewardProduced;
				_rewardsPerDeposit += ((producedNew * 1e20) / totalStaked);
			}
		}
		reward = calcReward(_staker, _rewardsPerDeposit);
		
		return reward;
	}
	
	/**
	 * @dev getUserInfoByAddress - return staker info by user address
	 */
	function getUserInfoByAddress(address user)
	external
	view
	returns (
		uint256 staked,
		uint256 available,
		uint256 claimed
	)
	{
		Staker memory staker = stakers[user];
		staked = staker.amount;
		available = getClaim(user);
		claimed = staker.distributed;
		
		return (staked, available, claimed);
	}
	
	/**
	 * @dev withdrawToken - withdraw token to sender by token address, if sender is admin
	 */
	function withdrawToken(address token, uint256 amount) public payable nonReentrant onlyRole(ADMIN_ROLE) {
		IERC20(token).safeTransfer(
			msg.sender,
			amount
		);
	}
	
	function withdrawFine() public payable nonReentrant onlyRole(ADMIN_ROLE) {
		require(accumulatedFine > 0, "Staking: accumulated fine is zero");
		IERC20(depositToken).safeTransfer(
			msg.sender,
			accumulatedFine
		);
		accumulatedFine = 0;
	}
	
	function setAvailability(bool[] calldata booleans) public onlyRole(ADMIN_ROLE) {
		if (isStakeAvailable != booleans[0]) {
			isStakeAvailable = booleans[0];
		}
		if (isUnstakeAvailable != booleans[1]) {
			isUnstakeAvailable = booleans[1];
		}
		if (isClaimAvailable != booleans[2]) {
			isClaimAvailable = booleans[2];
		}
	}
	
	struct CommonStakingInfo {
		uint256 rewardsPerEpoch;
		uint256 startTime;
		uint256 epochDuration;
		uint256 rewardsPerDeposit;
		uint256 rewardProduced;
		uint256 produceTime;
		uint256 halvingDuration;
		uint256 totalStaked;
		uint256 totalDistributed;
		address depositToken;
		address rewardToken;
		uint256 fineDuration;
		uint256 finePercent;
		uint256 accumulatedFine;
	}

	function getCommonStakingInfo() view public returns(CommonStakingInfo memory) {
		return CommonStakingInfo({
			rewardsPerEpoch: rewardsPerEpoch,
			startTime: startTime,
			epochDuration: epochDuration,
			rewardsPerDeposit: rewardsPerDeposit,
			rewardProduced: rewardProduced,
			produceTime: produceTime,
			halvingDuration: halvingDuration,
			totalStaked: totalStaked,
			totalDistributed: totalDistributed,
			depositToken: address(depositToken),
			rewardToken: address(rewardToken),
			fineDuration: fineDuration,
			finePercent: finePercent,
			accumulatedFine: accumulatedFine
		});
	}
}
