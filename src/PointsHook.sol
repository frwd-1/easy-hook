// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC1155 {
    // Points multiplier system
    struct UserStreak {
        uint256 consecutiveSwaps;
        uint256 lastSwapTime;
        uint256 totalPointsEarned;
    }

    mapping(address => UserStreak) public userStreaks;
    mapping(uint256 => address) public topUsers;
    uint256 public topUsersCount;

    uint256 public constant STREAK_TIMEOUT = 1 hours; // 1 hour to maintain streak
    uint256 public constant MAX_MULTIPLIER = 3; // Maximum 3x multiplier

    event StreakUpdated(
        address indexed user,
        uint256 newStreak,
        uint256 multiplier
    );
    event PointsMultiplied(
        address indexed user,
        uint256 basePoints,
        uint256 multiplier,
        uint256 finalPoints
    );

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    // Helper function to get current multiplier for a user
    function getMultiplier(address user) public view returns (uint256) {
        UserStreak memory streak = userStreaks[user];

        // If no streak or streak expired, return 1x
        if (
            streak.consecutiveSwaps == 0 ||
            block.timestamp - streak.lastSwapTime > STREAK_TIMEOUT
        ) {
            return 1;
        }

        // Calculate multiplier based on streak (capped at MAX_MULTIPLIER)
        uint256 multiplier = 1 + (streak.consecutiveSwaps / 5); // +1x every 5 swaps
        return multiplier > MAX_MULTIPLIER ? MAX_MULTIPLIER : multiplier;
    }

    // Get user's current streak info
    function getUserStreak(
        address user
    ) public view returns (UserStreak memory) {
        return userStreaks[user];
    }

    // Get top users by total points earned
    function getTopUsers(uint256 count) public view returns (address[] memory) {
        uint256 actualCount = count > topUsersCount ? topUsersCount : count;
        address[] memory result = new address[](actualCount);

        for (uint256 i = 0; i < actualCount; i++) {
            result[i] = topUsers[i];
        }

        return result;
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // If this is not an ETH-TOKEN pool with this hook attached, ignore
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        // We only mint points if user is buying TOKEN with ETH
        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        // Mint points equal to 20% of the amount of ETH they spent
        // Since its a zeroForOne swap:
        // if amountSpecified < 0:
        //      this is an "exact input for output" swap
        //      amount of ETH they spent is equal to |amountSpecified|
        // if amountSpecified > 0:
        //      this is an "exact output for input" swap
        //      amount of ETH they spent is equal to BalanceDelta.amount0()

        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsForSwap = ethSpendAmount / 5;

        // Mint the points
        _assignPoints(key.toId(), hookData, pointsForSwap);

        return (this.afterSwap.selector, 0);
    }

    function _assignPoints(
        PoolId poolId,
        bytes calldata hookData,
        uint256 points
    ) internal {
        // If no hookData is passed in, no points will be assigned to anyone
        if (hookData.length == 0) return;

        // Extract user address from hookData
        address user = abi.decode(hookData, (address));

        // If there is hookData but not in the format we're expecting and user address is zero
        // nobody gets any points
        if (user == address(0)) return;

        // Update user streak and calculate multiplier
        uint256 multiplier = _updateUserStreak(user);
        uint256 finalPoints = points * multiplier;

        // Update total points earned
        userStreaks[user].totalPointsEarned += finalPoints;

        // Update top users leaderboard
        _updateTopUsers(user);

        // Emit events
        emit PointsMultiplied(user, points, multiplier, finalPoints);

        // Mint points to the user
        uint256 poolIdUint = uint256(PoolId.unwrap(poolId));
        _mint(user, poolIdUint, finalPoints, "");
    }

    // Internal function to update user streak and return multiplier
    function _updateUserStreak(address user) internal returns (uint256) {
        UserStreak storage streak = userStreaks[user];
        uint256 currentTime = block.timestamp;

        // Check if streak has expired
        if (
            streak.consecutiveSwaps > 0 &&
            currentTime - streak.lastSwapTime > STREAK_TIMEOUT
        ) {
            // Reset streak
            streak.consecutiveSwaps = 0;
        }

        // Increment streak
        streak.consecutiveSwaps++;
        streak.lastSwapTime = currentTime;

        // Calculate multiplier
        uint256 multiplier = getMultiplier(user);

        emit StreakUpdated(user, streak.consecutiveSwaps, multiplier);

        return multiplier;
    }

    // Internal function to update top users leaderboard
    function _updateTopUsers(address user) internal {
        // Simple implementation: just add to top users if not already there
        // In a more sophisticated version, you'd sort by totalPointsEarned
        bool alreadyInTop = false;
        for (uint256 i = 0; i < topUsersCount; i++) {
            if (topUsers[i] == user) {
                alreadyInTop = true;
                break;
            }
        }

        if (!alreadyInTop && topUsersCount < 10) {
            // Keep top 10
            topUsers[topUsersCount] = user;
            topUsersCount++;
        }
    }
}
