// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable2Step} from "@openzeppelin/contracts-v4/access/Ownable2Step.sol";
import {ZeroAddress, CallerNotTimerAdmin, DeadlineNotYetPassed, NewDeadlineNotGreaterThanCurrent, NewDeadlineExceedsMaxDeadline} from "../common/L1ContractErrors.sol";

/// @title Governance Upgrade Timer
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice This contract will be used by the governance to ensure that the chains have enough time
/// to upgrade their implementation before finalizing the upgrade on L1.
/// @notice The `startTimer` function should be called once the new version is published. It starts the 
/// timer and gives at least `INITIAL_DELAY` for the chains to upgrade. In case for any reason the timeline has to 
/// extended, the owner of this contract can increase the timeline, but only the maximum of `MAX_ADDITIONAL_DELAY` 
/// is allowed.
contract GovernanceUpgradeTimer is Ownable2Step {
    /// @notice The initial delay to be used.
    uint256 public immutable INITIAL_DELAY;
    /// @notice The maximal delay for the upgrade.
    uint256 public immutable MAX_ADDITIONAL_DELAY;
    /// @notice The address that can start the timer.
    address public immutable TIMER_ADMIN;

    /// @notice The deadline which we should wait.
    uint256 public deadline;
    /// @notice The maximal deadline to which the owner of this contract can
    /// increase the deadline.
    uint256 public maxDeadline;

    /**
     * @dev Emitted when the timer is started, logging the initial `deadline` and `maxDeadline`.
     * @param deadline The initial deadline set for the timer.
     * @param maxDeadline The maximum deadline the timer can be extended to.
     */
    event TimerStarted(uint256 deadline, uint256 maxDeadline);

    /**
     * @dev Emitted when the owner changes the deadline.
     * @param newDeadline The new deadline set by the owner.
     */
    event DeadlineChanged(uint256 newDeadline);

    /**
     * @dev Initializes the contract with immutable values for `INITIAL_DELAY`, `MAX_ADDITIONAL_DELAY`, and `TIMER_ADMIN`.
     * @param _initialDelay The initial delay in seconds to be added to the current block timestamp to set the deadline.
     * @param _maxAdditionalDelay The maximum number of seconds that can be added to the initial delay to set `maxDeadline`.
     * @param _timerAdmin The address of the timer administrator, who is allowed to start the timer.
     */
    constructor(
        uint256 _initialDelay,
        uint256 _maxAdditionalDelay,
        address _timerAdmin
    ) {
        if(_timerAdmin == address(0)) {
            revert ZeroAddress();
        }

        INITIAL_DELAY = _initialDelay;
        MAX_ADDITIONAL_DELAY = _maxAdditionalDelay;
        TIMER_ADMIN = _timerAdmin;
    }

    /**
     * @dev Modifier that restricts function access to the `TIMER_ADMIN` address.
     * Reverts with a custom error if the caller is not `TIMER_ADMIN`.
     */
    modifier onlyTimerAdmin() {
        if (msg.sender != TIMER_ADMIN) {
            revert CallerNotTimerAdmin();
        }
        _;
    }

    /**
     * @dev Starts the timer by setting the `deadline` and `maxDeadline`. Only callable by the `TIMER_ADMIN`.
     *
     * Emits a {TimerStarted} event.
     */
    function startTimer() external onlyTimerAdmin {
        deadline = block.timestamp + INITIAL_DELAY;
        maxDeadline = deadline + MAX_ADDITIONAL_DELAY;

        emit TimerStarted(deadline, maxDeadline);
    }

    /**
     * @dev Checks if the current `deadline` has passed. Reverts if the deadline has already passed.
     *
     * Reverts with {DeadlinePassed} error if the current block timestamp is greater than `deadline`.
     */
    function checkDeadline() external view {
        if (block.timestamp < deadline) {
            revert DeadlineNotYetPassed();
        }
    }

    /**
     * @dev Allows the owner to change the current `deadline` to a new value.
     *
     * The new deadline must be greater than the current deadline and must not exceed `maxDeadline`.
     *
     * Emits a {DeadlineChanged} event.
     *
     * @param newDeadline The new deadline to be set.
     *
     * Reverts with {NewDeadlineNotGreaterThanCurrent} if the new deadline is not greater than the current one.
     * Reverts with {NewDeadlineExceedsMaxDeadline} if the new deadline exceeds `maxDeadline`.
     */
    function changeDeadline(uint256 newDeadline) external onlyOwner {
        if (newDeadline <= deadline) {
            revert NewDeadlineNotGreaterThanCurrent();
        }
        if (newDeadline > maxDeadline) {
            revert NewDeadlineExceedsMaxDeadline();
        }

        deadline = newDeadline;

        emit DeadlineChanged(newDeadline);
    }
}
