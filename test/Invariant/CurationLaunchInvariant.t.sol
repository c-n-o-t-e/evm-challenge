// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LaunchFactoryTestMock} from "../mocks/LaunchFactoryTestMock.sol";
import {CurationLaunchTestMock} from "../mocks/CurationLaunchTestMock.sol";
import {Test, console, ERC1967Proxy, CurationToken, CurationLaunchHandler} from "./CurationLaunchHandler.sol";

contract CurationLaunchInvariantTest is Test {
    CurationToken launchToken;
    CurationToken curationToken;
    LaunchFactoryTestMock launchFactory;
    CurationLaunchTestMock curationLaunch;
    CurationLaunchHandler handler;
    LaunchFactoryTestMock launchFactoryProxy;

    function setUp() public {
        launchToken = new CurationToken();
        curationToken = new CurationToken();
        launchFactory = new LaunchFactoryTestMock();
        curationLaunch = new CurationLaunchTestMock();

        bytes memory init =
            abi.encodeCall(launchFactory.initialize, (address(this), address(curationToken), address(curationLaunch)));
        launchFactoryProxy = LaunchFactoryTestMock(address(new ERC1967Proxy(address(launchFactory), init)));

        launchFactoryProxy.setMinimumLaunchAmount(5 ether);
        launchFactoryProxy.setMinimumCurationPeriod(48 hours);
        launchFactoryProxy.setMaximumStakingAmountPercentage(5_000);
        launchFactoryProxy.setMinimumStakingAmountPercentage(3_000);

        launchToken.mint(address(launchFactoryProxy), 100 ether);

        vm.warp(1 days);

        curationLaunch = CurationLaunchTestMock(
            launchFactoryProxy.launchTokenForCuration(
                address(launchToken), block.timestamp, block.timestamp + 72 hours, 4_000
            )
        );

        launchFactoryProxy.setMaxAllowedPerUserForNewLaunch(address(curationLaunch), 500);

        handler = new CurationLaunchHandler(launchToken, curationToken, launchFactoryProxy, curationLaunch);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = CurationLaunchHandler.stake.selector;
        selectors[1] = CurationLaunchHandler.unStake.selector;
        selectors[2] = CurationLaunchHandler.claim.selector;
        // selectors[3] = CurationLaunchHandler.executeOrder.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_TotalStakedIsSame() external {
        uint256 totalStakedFromLaunch;
        if (
            launchFactoryProxy.getLaunchStatus(address(curationLaunch)) == LaunchFactoryTestMock.LaunchStatus.SUCCESSFUL
                || launchFactoryProxy.getLaunchStatus(address(curationLaunch))
                    == LaunchFactoryTestMock.LaunchStatus.NOT_SUCCESSFUL
        ) {
            totalStakedFromLaunch = launchFactoryProxy.getLaunchStakedAmountAfterCurationPeriod(address(curationLaunch));
        } else {
            totalStakedFromLaunch = curationLaunch.totalStaked();
        }
        assertEq(totalStakedFromLaunch, handler.ghostTotalStaked());
    }

    function invariant_ContractCurationBalanceIsSame() external {
        assertEq(curationToken.balanceOf(address(curationLaunch)), handler.ghostContractCurationTokenBalance());
    }

    function invariant_ContractLaunchBalanceIsSame() external {
        assertEq(launchToken.balanceOf(address(curationLaunch)), handler.ghostContractLaunchTokenBalance());
    }

    function invariant_UserStakesAreSame() external {
        address[] memory actors = handler.actors();
        for (uint256 i; i < actors.length; ++i) {
            assertEq(handler.ghostUsersStakes(actors[i]), curationLaunch.stakedAmount(actors[i]));
        }
    }

    function invariant_UsersCurationTokenBalanceAreSame() external {
        address[] memory actors = handler.actors();
        for (uint256 i; i < actors.length; ++i) {
            assertEq(handler.ghostUsersCurationTokenBalance(actors[i]), curationToken.balanceOf(actors[i]));
        }
    }

    function invariant_UsersLaunchTokenBalanceAreSame() external {
        address[] memory actors = handler.actors();
        for (uint256 i; i < actors.length; ++i) {
            assertEq(handler.ghostUsersLaunchTokenBalance(actors[i]), launchToken.balanceOf(actors[i]));
        }

        console.log("state:", uint256(launchFactoryProxy.getLaunchStatus(address(curationLaunch))));
    }
}
