// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "oz/contracts/token/ERC20/utils/SafeERC20.sol";

interface ILaunchFactory {
    enum LaunchStatus {
        NOT_LAUNCHED,
        LAUNCHED,
        SUCCESSFUL,
        NOT_SUCCESSFUL
    }

    function launches(address) external view returns (LaunchStatus);
    function updateLaunchStatus(address, LaunchStatus) external;
}

contract NewLaunch {
    using SafeERC20 for IERC20;

    ILaunchFactory public factory;

    uint256 public endTime;
    uint256 public startTime;
    uint256 public totalStaked;
    uint256 public tokensAssignedForStaking;

    address public curationToken;

    mapping(address => uint256) public stakedAmount;

    error NewLaunch_Zero_Amount();
    error NewLaunch_Still_Active();
    error NewLaunch_Too_Late_To_Stake();
    error NewLaunch_Too_Early_To_Stake();
    error NewLaunch_Launch_Was_Successful();
    error NewLaunch_Launch_Already_Triggered();

    constructor(uint256 _startTime, uint256 _endTime, uint256 _tokensAssignedForStaking, address _curationToken) {
        endTime = _endTime;
        factory = ILaunchFactory(msg.sender);
        startTime = _startTime;
        curationToken = _curationToken;
        tokensAssignedForStaking = _tokensAssignedForStaking;
    }

    function maxAmountAllowedForOneUser() public view returns (uint256) {
        return tokensAssignedForStaking / 10;
    }

    function stakeCurationToken(uint256 _amount) external {
        triggerLaunchState();

        if (_amount == 0) revert NewLaunch_Zero_Amount();
        if (block.timestamp < startTime) revert NewLaunch_Too_Early_To_Stake();
        if (block.timestamp > endTime) revert NewLaunch_Too_Late_To_Stake();

        uint256 _stakedAmount = stakedAmount[msg.sender];

        // prevents a single user from staking more than 10% of the total tokens assigned for staking
        if (_stakedAmount + _amount > maxAmountAllowedForOneUser()) {
            _amount = maxAmountAllowedForOneUser() - _stakedAmount;
        }

        if (_amount == 0) return;
        uint256 _amountAvailableForStaking = tokensAssignedForStaking - totalStaked;
        if (_amountAvailableForStaking == 0) return;

        // ensures that the total staked amount does not exceed the amount of tokens assigned for staking
        if (_amount > _amountAvailableForStaking) {
            _amount = _amountAvailableForStaking;
        }

        IERC20(curationToken).safeTransferFrom(msg.sender, address(this), _amount);
        stakedAmount[msg.sender] += _amount;
        totalStaked += _amount;

        //emit Staked(msg.sender, _amount);
    }

    function unstakeCurationToken() external {
        triggerLaunchState();
        uint256 _stakedAmount = stakedAmount[msg.sender];

        if (_stakedAmount == 0) revert NewLaunch_Zero_Amount();
        if (block.timestamp < endTime) revert NewLaunch_Still_Active();

        if (factory.launches(address(this)) != ILaunchFactory.LaunchStatus.NOT_SUCCESSFUL) {
            revert NewLaunch_Launch_Was_Successful();
        }

        stakedAmount[msg.sender] -= _stakedAmount;
        // totalStaked -= _stakedAmount; totalStaked is never decremented back for records

        IERC20(curationToken).safeTransfer(msg.sender, _stakedAmount);
        //emit Unstaked(msg.sender, _stakedAmount);
    }

    function triggerLaunchState() public {
        if (block.timestamp < endTime) return;
        if (factory.launches(address(this)) != ILaunchFactory.LaunchStatus.LAUNCHED) return;

        if (totalStaked < tokensAssignedForStaking) {
            factory.updateLaunchStatus(address(this), ILaunchFactory.LaunchStatus.NOT_SUCCESSFUL); // update by only factory
        } else {
            factory.updateLaunchStatus(address(this), ILaunchFactory.LaunchStatus.SUCCESSFUL);
        }
    }

    function claimLaunchToken() external {
        triggerLaunchState();
        if (factory.launches(address(this)) != ILaunchFactory.LaunchStatus.SUCCESSFUL) {
            revert NewLaunch_Launch_Already_Triggered();
        }

        // transfer the token to the user
    }
}
