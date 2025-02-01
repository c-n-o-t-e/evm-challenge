// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILaunchFactory {
    enum LaunchStatus {
        NOT_ACTIVE,
        ACTIVE,
        SUCCESSFUL,
        NOT_SUCCESSFUL
    }

    function launchTokenForCuration(
        address _tokenToLaunch,
        uint256 startTime,
        uint256 _endTime,
        uint256 _tokenForStakingPercentage
    ) external returns (address newLaunch);

    function updateLaunchStatus(address, LaunchStatus) external;

    function launchToken(address _launchAddress) external view returns (address);

    function launchStatus(address _launchAddress) external view returns (LaunchStatus);

    function launchAmountToDistribute(address _launchAddress) external view returns (uint256);

    function launchTargetCurationAmount(address _launchAddress) external view returns (uint256);

    function updateLaunchStakedAmountAfterCurationPeriod(address _launch, uint256 _amount) external;

    function launchStakedAmountAfterCurationPeriod(address _launchAddress) external view returns (uint256);
}
