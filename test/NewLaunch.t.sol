// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "../src/NewLaunch.sol";
import {Test, console} from "forge-std/Test.sol";
import {CurationToken} from "../src/CurationToken.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";
import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";

//Todo: ensure only factory can deploy new launch contract
contract NewLaunchTest is Test {
    NewLaunch newLaunch;
    CurationToken launchToken;
    CurationToken curationToken;
    LaunchFactory launchFactory;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");

    function setUp() public {
        launchToken = new CurationToken();
        curationToken = new CurationToken();
        launchFactory = new LaunchFactory(address(curationToken));

        launchFactory.setMinimumLaunchAmount(5 ether);
        launchFactory.setMinimumCurationPeriod(48 hours);
        launchFactory.setMaximumStakingAmountPercentage(5_000);
        launchFactory.setMinimumStakingAmountPercentage(3_000);

        launchToken.mint(address(launchFactory), 100 ether);

        vm.warp(1 days);

        newLaunch = NewLaunch(
            launchFactory.launchTokenForCuration(
                address(launchToken), block.timestamp, block.timestamp + 72 hours, 4_000
            )
        );
    }

    function test_Stake() public {
        uint256 amount = 1 ether;
        curationToken.mint(bob, amount);

        vm.startPrank(bob);
        IERC20(curationToken).approve(address(newLaunch), amount);
        newLaunch.stakeCurationToken(amount);

        assertEq(newLaunch.totalStaked(), amount);
        assertEq(newLaunch.stakedAmount(bob), amount);
        vm.stopPrank();
    }

    function test_Should_Let_Users_Stake_Only_Available_Amount_To_Stake() public {
        for (uint256 i = 0; i < 19; i++) {
            address newAddress = vm.addr(i + 1);

            uint256 amount = 2 ether;
            curationToken.mint(newAddress, amount);

            vm.startPrank(newAddress);
            IERC20(curationToken).approve(address(newLaunch), amount);
            newLaunch.stakeCurationToken(amount);

            assertEq(newLaunch.stakedAmount(newAddress), amount);
            vm.stopPrank();
        }

        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking() - 2 ether);

        // At this stage, only 2 ether is available for staking

        curationToken.mint(bob, 1 ether);
        curationToken.mint(alice, 2 ether);

        // Bob stakes 1 ether leaving 1 ether available for staking
        vm.startPrank(bob);
        IERC20(curationToken).approve(address(newLaunch), 1 ether);
        newLaunch.stakeCurationToken(1 ether);
        vm.stopPrank();

        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking() - 1 ether);

        // Alice tries to stake 2 ether but only 1 ether is available so the contract lets her stake only 1 ether
        assertEq(curationToken.balanceOf(alice), 2 ether);
        vm.startPrank(alice);
        IERC20(curationToken).approve(address(newLaunch), 2 ether);
        newLaunch.stakeCurationToken(2 ether);
        vm.stopPrank();

        // Alice should have 1 ether left
        assertEq(curationToken.balanceOf(alice), 1 ether);
        // Total staked amount should be equal to the assigned amount for staking
        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking());
    }

    function test_Users_Should_Not_Stake_Above_Assigned_Amount_For_Staking() public {
        for (uint256 i = 0; i < 20; i++) {
            address newAddress = vm.addr(i + 1);

            uint256 amount = 2 ether;
            curationToken.mint(newAddress, amount);

            vm.startPrank(newAddress);
            IERC20(curationToken).approve(address(newLaunch), amount);
            newLaunch.stakeCurationToken(amount);

            assertEq(newLaunch.stakedAmount(newAddress), amount);
            vm.stopPrank();
        }

        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking());

        // Bob tries to stake after assigned staking amount is reached

        uint256 amt = 1 ether;
        curationToken.mint(bob, amt);
        assertEq(curationToken.balanceOf(bob), amt);

        // Should revert because the total staked amount has reached the assigned amount and Launch status is not ACTIVE anymore.
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Too_Late_To_Stake.selector));
        newLaunch.stakeCurationToken(amt);
        vm.stopPrank();
    }

    function test_User_Should_Stake_Only_Up_To_Max_Allowed() public {
        uint256 amount = 10 ether;
        curationToken.mint(address(this), amount);
        assertEq(curationToken.balanceOf(address(this)), amount);

        IERC20(curationToken).approve(address(newLaunch), amount);
        newLaunch.stakeCurationToken(amount);
        uint256 maxAllowed = newLaunch.maxAmountAllowedForOneUser();

        assertEq(newLaunch.stakedAmount(address(this)), maxAllowed);
        assertEq(curationToken.balanceOf(address(this)), amount - maxAllowed);
        assertEq(newLaunch.totalStaked(), maxAllowed);

        // tries staking more than allowed
        newLaunch.stakeCurationToken(amount);

        // asserted values should remain the same
        assertEq(newLaunch.totalStaked(), maxAllowed);
        assertEq(newLaunch.stakedAmount(address(this)), maxAllowed);
        assertEq(curationToken.balanceOf(address(this)), amount - maxAllowed);
    }

    function test_Stake_Should_Fail() public {
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Zero_Amount.selector));
        newLaunch.stakeCurationToken(0);

        vm.warp(60 seconds);
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Too_Early_To_Stake.selector));
        newLaunch.stakeCurationToken(1 ether);
    }

    function test_ShouldFailToLaunchCuration() public {}
}
