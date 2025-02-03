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

    function getLaunchToken(address _launchAddress) external view returns (address);

    function getLaunchStatus(address _launchAddress) external view returns (LaunchStatus);

    function getLaunchAmountForLiquidity(address _launch) external view returns (uint256);

    function getLaunchAmountToDistribute(address _launchAddress) external view returns (uint256);

    function getLaunchTargetCurationAmount(address _launchAddress) external view returns (uint256);

    function updateLaunchStakedAmountAfterCurationPeriod(address _launch, uint256 _amount) external;

    function getLaunchStakedAmountAfterCurationPeriod(address _launchAddress) external view returns (uint256);
}
