// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "./NewLaunch.sol";
import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";

contract LaunchFactory {
    enum LaunchStatus {
        NOT_LAUNCHED,
        LAUNCHED,
        SUCCESSFUL,
        NOT_SUCCESSFUL
    }

    address curationToken;

    uint256 public constant BIPS_DENOMINATOR = 10_000;
    uint256 public minimumAmountToLaunch = 1_000;
    uint256 public maximumStakingAmount;
    uint256 public minimumStakingAmount;

    mapping(address => LaunchStatus) public launches;

    error LaunchFactory_Balance_Below_Minimum_Launch_Amount();

    function launchToken(
        address _tokenToLaunch,
        uint256 startTime,
        uint256 _endTime,
        uint256 _tokenForStakingPercentage
    ) external returns (address newLaunch) {
        if (IERC20(_tokenToLaunch).balanceOf(address(this)) < minimumAmountToLaunch) {
            revert LaunchFactory_Balance_Below_Minimum_Launch_Amount();
        }

        if (_tokenForStakingPercentage > maximumStakingAmount || _tokenForStakingPercentage < minimumStakingAmount) {
            revert LaunchFactory_Balance_Below_Minimum_Launch_Amount();
        }

        uint256 tokenUsedForStaking =
            IERC20(_tokenToLaunch).balanceOf(address(this)) * _tokenForStakingPercentage / BIPS_DENOMINATOR;

        newLaunch = address(new NewLaunch(startTime, _endTime, tokenUsedForStaking, curationToken));
        launches[newLaunch] = LaunchStatus.LAUNCHED;
    }

    function updateLaunchStatus(address _launch, LaunchStatus _status) external {
        launches[_launch] = _status;
    }

    function withdrawToken(address _token, uint256 _amount) external {
        // <--- Check
        if (launches[_token] != LaunchStatus.LAUNCHED) {
            IERC20(_token).transfer(msg.sender, _amount);
        }
    }
}
