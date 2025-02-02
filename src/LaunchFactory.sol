// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "./NewLaunch.sol";
import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";
// import {Initializable} from "ozUpgradeable/contracts/proxy/utils/Initializable.sol";

contract LaunchFactory {
    enum LaunchStatus {
        NOT_ACTIVE,
        ACTIVE,
        SUCCESSFUL,
        NOT_SUCCESSFUL
    }

    address curationToken;

    uint256 public minimumCurationPeriod;
    uint256 public minimumAmountToLaunch;
    uint256 public maximumStakingAmountPercentage;
    uint256 public minimumStakingAmountPercentage;

    uint256 constant MAX_PERCENTAGE = 5_000;
    uint256 constant BIPS_DENOMINATOR = 10_000;
    uint256 constant MINIMUM_PERCENTAGE = 2_000;
    uint256 constant MINIMUM_CURATION_PERIOD = 24 hours;

    mapping(address => TokenSubmission) public submissions;

    struct TokenSubmission {
        LaunchStatus status;
        address tokenAddress;
        uint256 amountForStaking;
        uint256 amountForLiquidity;
        uint256 stakedAmountAfterCurationPeriod;
    }

    error LaunchFactory_Above_MaxPercentage();
    error LaunchFactory_Start_Time_In_The_Past();
    error LaunchFactory_Below_Minimun_Duration();
    error LaunchFactory_Below_MinimumPercentage();
    error LaunchFactory_Curation_Below_Minimum_Duration();
    error LaunchFactory_Balance_Below_Minimum_Launch_Amount();
    error LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage();

    // /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _curationToken) {
        curationToken = _curationToken;
        // _disableInitializers();
    }

    function setMinimumLaunchAmount(uint256 _minimumAmountToLaunch) external {
        minimumAmountToLaunch = _minimumAmountToLaunch;
    }

    function setMinimumCurationPeriod(uint256 _minimumCurationPeriod) external {
        if (_minimumCurationPeriod < MINIMUM_CURATION_PERIOD) revert LaunchFactory_Below_Minimun_Duration();
        minimumCurationPeriod = _minimumCurationPeriod;
    }

    function setMaximumStakingAmountPercentage(uint256 _maximumStakingAmountPercentage) external {
        if (_maximumStakingAmountPercentage > MAX_PERCENTAGE) revert LaunchFactory_Above_MaxPercentage();
        maximumStakingAmountPercentage = _maximumStakingAmountPercentage;
    }

    function setMinimumStakingAmountPercentage(uint256 _minimumStakingAmountPercentage) external {
        if (_minimumStakingAmountPercentage < MINIMUM_PERCENTAGE) revert LaunchFactory_Below_MinimumPercentage();
        minimumStakingAmountPercentage = _minimumStakingAmountPercentage;
    }

    function launchStatus(address _launch) external view returns (LaunchStatus) {
        return submissions[_launch].status;
    }

    function launchToken(address _launch) external view returns (address) {
        return submissions[_launch].tokenAddress;
    }

    function launchAmountForStaking(address _launch) external view returns (uint256) {
        return submissions[_launch].amountForStaking;
    }

    function launchAmountForLiquidity(address _launch) external view returns (uint256) {
        return submissions[_launch].amountForLiquidity;
    }

    function launchStakedAmountAfterCurationPeriod(address _launch) external view returns (uint256) {
        return submissions[_launch].stakedAmountAfterCurationPeriod;
    }

    function launchTokenForCuration(
        address _tokenToLaunch,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _stakingPercentage
    ) external returns (address newLaunch) {
        if (_startTime < block.timestamp) revert LaunchFactory_Start_Time_In_The_Past();
        if (_endTime < _startTime + minimumCurationPeriod) revert LaunchFactory_Curation_Below_Minimum_Duration();

        uint256 contractLaunchTokenBalance = IERC20(_tokenToLaunch).balanceOf(address(this));

        if (contractLaunchTokenBalance < minimumAmountToLaunch) {
            revert LaunchFactory_Balance_Below_Minimum_Launch_Amount();
        }

        if (_stakingPercentage > maximumStakingAmountPercentage || _stakingPercentage < minimumStakingAmountPercentage)
        {
            revert LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage();
        }

        uint256 tokenAvailableForStaking = contractLaunchTokenBalance * _stakingPercentage / BIPS_DENOMINATOR;
        newLaunch =
            address(new NewLaunch(_tokenToLaunch, _startTime, _endTime, tokenAvailableForStaking, curationToken));

        TokenSubmission storage submission = submissions[newLaunch];
        submission.status = LaunchStatus.ACTIVE;
        submission.tokenAddress = _tokenToLaunch;
        submission.amountForStaking = tokenAvailableForStaking;
        submission.amountForLiquidity = contractLaunchTokenBalance - tokenAvailableForStaking;

        IERC20(_tokenToLaunch).transfer(newLaunch, contractLaunchTokenBalance);
        // emit LaunchToken(_tokenToLaunch, newLaunch);
    }

    // add access control only owner can call this function
    function setMaxAllowedPerUserForNewLaunch(address _launch, uint256 _maxAllowedPerUser) external {
        NewLaunch(_launch).setMaxAllowedPerUser(_maxAllowedPerUser);
    }

    function updateLaunchStatus(address _launch, LaunchStatus _status) external {
        submissions[_launch].status = _status;
    }

    function updateLaunchStakedAmountAfterCurationPeriod(address _launch, uint256 _amount) external {
        submissions[_launch].stakedAmountAfterCurationPeriod = _amount;
    }

    function withdrawToken(address _token, uint256 _amount) external {
        // <--- Check
        if (submissions[_token].status != LaunchStatus.ACTIVE) {
            IERC20(_token).transfer(msg.sender, _amount);
        }
    }
}
