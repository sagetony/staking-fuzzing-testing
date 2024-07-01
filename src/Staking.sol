// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Staking Contract
 */

contract Staking is ERC20 {
    error Staking_FailedTransaction();

    uint256 public price = 0.001 ether;
    uint256 public totalSales;
    uint256 public totalPurchase;
    uint32 constant SECONDS_IN_A_DAY = 86400;
    uint16 constant DAYS_IN_A_YEAR = 365;

    uint128 public annualYieldRate;
    uint256 public totalStakedToken;

    struct Stake {
        uint256 amount;
        uint32 startTimestamp;
        uint256 period;
        uint256 annualYieldRate;
        bool withdrawn;
        uint256 lastClaimTimestamp;
        uint256 lastRewardTimestamp;
        uint256 accumulatedRewards;
        uint256 currentRewards;
    }

    mapping(address => Stake[]) public stakes;

    event TokensStaked(
        address indexed user,
        uint256 amount,
        uint256 period,
        uint256 annualYieldRate
    );
    event RewardsClaimed(address indexed user, uint256 amount);
    event StakeWithdrawn(address indexed user, uint256 amount);
    event EarlyWithdrawal(
        address indexed user,
        uint256 amount,
        uint256 penalty
    );
    event TokensBurned(address indexed user, uint256 amount);

    constructor(uint128 _annualYieldRate) ERC20("Staking Token", "ST") {
        annualYieldRate = _annualYieldRate;
        _mint(address(this), 100_000 * 10 ** 18);
    }

    //  1 = 3
    //  6 =
    function buyToken() external payable {
        require(msg.value >= price);

        uint256 tokensToMint = msg.value / price;

        totalPurchase += tokensToMint;
        totalSales += msg.value;

        bool success = transfer(msg.sender, tokensToMint);
        if (!success) revert("Failed Transaction");
    }

    function stakeTokens(uint256 _amount, uint256 _period) external {
        require(_amount > 0, "Amount must be greater than 0");

        bool success = transferFrom(msg.sender, address(this), _amount);
        require(success, "Staking failed");

        totalStakedToken += _amount;

        stakes[msg.sender].push(
            Stake({
                amount: _amount,
                startTimestamp: uint32(block.timestamp),
                period: _period,
                annualYieldRate: annualYieldRate,
                withdrawn: false,
                lastClaimTimestamp: block.timestamp,
                lastRewardTimestamp: block.timestamp,
                accumulatedRewards: 0,
                currentRewards: 0
            })
        );

        emit TokensStaked(msg.sender, _amount, _period, annualYieldRate);
    }

    function claimRewards(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage stake = stakes[msg.sender][stakeIndex];
        require(!stake.withdrawn, "Stake already withdrawn");

        // Make sure the expected Reward is less or equal to the accumlatedRewards
        uint256 expectedTotalRewards = calculateEarnings(
            stake.amount,
            stake.period
        );
        require(
            stake.accumulatedRewards <= expectedTotalRewards,
            "Exceed expected reward"
        );

        // Calculate time intervals
        uint256 currentTime = block.timestamp;
        uint256 claimInterval = 30 days; // 30 days interval
        uint256 eligibleClaimTime = stake.lastClaimTimestamp + claimInterval;
        require(currentTime >= eligibleClaimTime, "Rewards not yet claimable");

        // Calculate earnings since last claim
        uint256 timeSinceLastClaim = (currentTime - stake.lastClaimTimestamp) /
            1 days;
        uint256 earnings = calculateEarnings(stake.amount, timeSinceLastClaim);

        // Update accumulated rewards and last claim timestamp
        stake.accumulatedRewards += earnings;
        stake.currentRewards += earnings;
        stake.lastClaimTimestamp = currentTime;

        emit RewardsClaimed(msg.sender, earnings);
    }

    function withdrawStake(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage stake = stakes[msg.sender][stakeIndex];
        require(!stake.withdrawn, "Stake already withdrawn");

        // Make sure the expected Reward is less or equal to the accumlatedRewards
        uint256 expectedTotalRewards = calculateEarnings(
            stake.amount,
            stake.period
        );
        uint256 rewardAmount = stake.currentRewards;

        require(
            stake.accumulatedRewards <= expectedTotalRewards,
            "Exceed expected reward"
        );

        require(rewardAmount != 0, "Rewards not available");

        // Calculate time intervals
        uint256 currentTime = block.timestamp;
        uint256 claimInterval = 30 days; // 30 days interval
        uint256 eligibleRewardTime = stake.lastRewardTimestamp + claimInterval;
        require(currentTime > eligibleRewardTime, "Rewards not yet claimable");

        // Update accumulated rewards and last claim timestamp
        stake.lastRewardTimestamp = currentTime;

        // Transfer reward amount (accumulated rewards)
        stake.currentRewards = 0;

        if (stake.accumulatedRewards >= expectedTotalRewards) {
            stake.withdrawn = true;
        }
        bool success = transfer(msg.sender, rewardAmount);
        if (!success) revert Staking_FailedTransaction();

        emit RewardsClaimed(msg.sender, rewardAmount);
    }

    function withdrawLockedToken(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage stake = stakes[msg.sender][stakeIndex];
        require(!stake.withdrawn, "Stake already withdrawn");
        require(stake.amount > 0, "Invalid amount");

        require(
            block.timestamp >
                stake.startTimestamp + (stake.period * SECONDS_IN_A_DAY),
            "Staking period not completed"
        );

        uint256 lockedAmount = stake.amount;
        stake.amount = 0;

        // Transfer total amount (initial stakes)
        bool success = transfer(msg.sender, lockedAmount);
        if (!success) revert Staking_FailedTransaction();

        emit StakeWithdrawn(msg.sender, lockedAmount);
    }

    function calculateEarnings(
        uint256 _amount,
        uint256 _timeElapsed
    ) internal view returns (uint256) {
        return
            (_amount * annualYieldRate * _timeElapsed) / (DAYS_IN_A_YEAR * 100);
    }

    receive() external payable {}
}
