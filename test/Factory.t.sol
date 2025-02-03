// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "../src/NewLaunch.sol";
import {Test, console} from "forge-std/Test.sol";
import {CurationToken} from "../src/CurationToken.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

//Todo: ensure only factory can deploy new launch contract
contract CounterTest is Test {
    NewLaunch newLaunch;
    CurationToken launchToken;
    CurationToken curationToken;
    LaunchFactory launchFactory;
    LaunchFactory launchFactoryProxy;

    function setUp() public {
        newLaunch = new NewLaunch();
        launchToken = new CurationToken();
        curationToken = new CurationToken();
        launchFactory = new LaunchFactory();

        bytes memory init =
            abi.encodeCall(launchFactory.initialize, (address(this), address(curationToken), address(newLaunch)));
        launchFactoryProxy = LaunchFactory(address(new ERC1967Proxy(address(launchFactory), init)));

        launchFactoryProxy.setMinimumLaunchAmount(5 ether);
        launchFactoryProxy.setMinimumCurationPeriod(48 hours);
        launchFactoryProxy.setMaximumStakingAmountPercentage(5_000);
        launchFactoryProxy.setMinimumStakingAmountPercentage(3_000);
    }

    function test_LaunchCuration() public {
        launchToken.mint(address(launchFactoryProxy), 10 ether);
        address newLaunchAddress =
            vm.computeCreateAddress(address(launchFactoryProxy), vm.getNonce(address(launchFactoryProxy)));
        assertEq(
            uint256(launchFactoryProxy.getLaunchStatus(newLaunchAddress)),
            uint256(LaunchFactory.LaunchStatus.NOT_ACTIVE)
        );

        newLaunch = NewLaunch(
            launchFactoryProxy.launchTokenForCuration(
                address(launchToken), block.timestamp, block.timestamp + 72 hours, 4_000
            )
        );

        uint256 stakingAmount = (10 ether * 4_000) / 10_000;
        assertEq(address(newLaunch), newLaunchAddress);

        assertEq(launchToken.balanceOf(address(newLaunch)), 10 ether);
        assertEq(launchFactoryProxy.getLaunchAddress(address(launchToken)), address(newLaunch));
        assertEq(launchFactoryProxy.getLaunchAmountForStaking(address(newLaunch)), newLaunch.tokensAssignedForStaking());

        assertEq(launchFactoryProxy.getLaunchStakedAmountAfterCurationPeriod(address(newLaunch)), 0);
        assertEq(launchFactoryProxy.getLaunchAmountForLiquidity(address(newLaunch)), 10 ether - stakingAmount);
        assertEq(
            uint256(launchFactoryProxy.getLaunchStatus(address(newLaunch))), uint256(LaunchFactory.LaunchStatus.ACTIVE)
        );
    }

    function test_ShouldFailToLaunchCuration() public {
        vm.warp(1 hours);

        vm.expectRevert(abi.encodeWithSelector(LaunchFactory.LaunchFactory_Start_Time_In_The_Past.selector));
        launchFactoryProxy.launchTokenForCuration(address(launchToken), 0, block.timestamp + 72 hours, 4_000);

        vm.expectRevert(abi.encodeWithSelector(LaunchFactory.LaunchFactory_Curation_Below_Minimum_Duration.selector));
        launchFactoryProxy.launchTokenForCuration(
            address(launchToken), block.timestamp, block.timestamp + 12 hours, 4_000
        );

        vm.expectRevert(
            abi.encodeWithSelector(LaunchFactory.LaunchFactory_Balance_Below_Minimum_Launch_Amount.selector)
        );

        launchFactoryProxy.launchTokenForCuration(
            address(launchToken), block.timestamp, block.timestamp + 72 hours, 4_000
        );

        launchToken.mint(address(launchFactoryProxy), 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchFactory.LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage.selector
            )
        );

        launchFactoryProxy.launchTokenForCuration(
            address(launchToken), block.timestamp, block.timestamp + 72 hours, 6_000
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchFactory.LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage.selector
            )
        );

        launchFactoryProxy.launchTokenForCuration(
            address(launchToken), block.timestamp, block.timestamp + 72 hours, 2_000
        );
    }
}
