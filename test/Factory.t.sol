// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "../src/NewLaunch.sol";
import {Test, console} from "forge-std/Test.sol";
import {CurationToken} from "../src/CurationToken.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";

//Todo: ensure only factory can deploy new launch contract
contract CounterTest is Test {
    NewLaunch newLaunch;
    CurationToken launchToken;
    CurationToken curationToken;
    LaunchFactory launchFactory;

    function setUp() public {
        launchToken = new CurationToken();
        curationToken = new CurationToken();
        launchFactory = new LaunchFactory(address(curationToken));

        launchFactory.setMinimumLaunchAmount(5 ether);
        launchFactory.setMinimumCurationPeriod(48 hours);
        launchFactory.setMaximumStakingAmountPercentage(5_000);
        launchFactory.setMinimumStakingAmountPercentage(3_000);
    }

    function test_LaunchCuration() public {
        launchToken.mint(address(launchFactory), 10 ether);
        address newLaunchAddress = vm.computeCreateAddress(address(launchFactory), vm.getNonce(address(launchFactory)));
        assertEq(uint256(launchFactory.launchStatus(newLaunchAddress)), uint256(LaunchFactory.LaunchStatus.NOT_ACTIVE));

        newLaunch = NewLaunch(
            launchFactory.launchTokenForCuration(
                address(launchToken), block.timestamp, block.timestamp + 72 hours, 4_000
            )
        );

        uint256 stakingAmount = (10 ether * 4_000) / 10_000;
        assertEq(address(newLaunch), newLaunchAddress);

        assertEq(launchToken.balanceOf(address(newLaunch)), 10 ether);
        assertEq(launchFactory.launchToken(address(newLaunch)), address(launchToken));
        assertEq(launchFactory.launchAmountForStaking(address(newLaunch)), newLaunch.tokensAssignedForStaking());

        assertEq(launchFactory.launchStakedAmountAfterCurationPeriod(address(newLaunch)), 0);
        assertEq(launchFactory.launchAmountForLiquidity(address(newLaunch)), 10 ether - stakingAmount);
        assertEq(uint256(launchFactory.launchStatus(address(newLaunch))), uint256(LaunchFactory.LaunchStatus.ACTIVE));
    }

    function test_ShouldFailToLaunchCuration() public {
        vm.warp(1 hours);

        vm.expectRevert(abi.encodeWithSelector(LaunchFactory.LaunchFactory_Start_Time_In_The_Past.selector));
        launchFactory.launchTokenForCuration(address(launchToken), 0, block.timestamp + 72 hours, 4_000);

        vm.expectRevert(abi.encodeWithSelector(LaunchFactory.LaunchFactory_Curation_Below_Minimum_Duration.selector));
        launchFactory.launchTokenForCuration(address(launchToken), block.timestamp, block.timestamp + 12 hours, 4_000);

        vm.expectRevert(
            abi.encodeWithSelector(LaunchFactory.LaunchFactory_Balance_Below_Minimum_Launch_Amount.selector)
        );
        launchFactory.launchTokenForCuration(address(launchToken), block.timestamp, block.timestamp + 72 hours, 4_000);

        launchToken.mint(address(launchFactory), 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchFactory.LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage.selector
            )
        );
        launchFactory.launchTokenForCuration(address(launchToken), block.timestamp, block.timestamp + 72 hours, 6_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchFactory.LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage.selector
            )
        );
        launchFactory.launchTokenForCuration(address(launchToken), block.timestamp, block.timestamp + 72 hours, 2_000);
    }
}
