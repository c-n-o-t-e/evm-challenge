// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "../src/NewLaunch.sol";
import {Test, console} from "forge-std/Test.sol";
import {TickMath} from "../src/library/TickMath.sol";
import {CurationToken} from "../src/CurationToken.sol";
import {LaunchFactory} from "../src/LaunchFactory.sol";
import {MockNewLaunch} from "./mocks/MockNewLaunch.sol";
import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "oz/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LiquidityAmounts} from "../src/library/LiquidityAmounts.sol";
import {IERC721Receiver} from "../src/Interfaces/IERC721Receiver.sol";
import {UpgradeableBeacon} from "oz/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {INonfungiblePositionManager} from "../src/interfaces/INonfungiblePositionManager.sol";

/**
 * @title Uint Test For .......
 * @author c-n-o-t-e
 * @dev Contract is used to test out .......-
 *      by forking the Ethereum Mainnet chain to interact with....
 *
 * Functionalities Tested:
 */
/*
    Todo: ensure only factory can deploy new launch contract
    test for events
*/
contract NewLaunchTest is Test {
    NewLaunch newLaunch;
    CurationToken launchToken;
    CurationToken curationToken;
    LaunchFactory launchFactory;
    LaunchFactory launchFactoryProxy;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    string ETHEREUM_RPC_URL = vm.envString("ETHEREUM_RPC_URL");

    function setUp() public {
        vm.createSelectFork(ETHEREUM_RPC_URL);

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

        launchToken.mint(address(launchFactoryProxy), 100 ether);

        vm.warp(1 days);

        newLaunch = NewLaunch(
            launchFactoryProxy.launchTokenForCuration(
                address(launchToken), block.timestamp, block.timestamp + 72 hours, 4_000
            )
        );

        launchFactoryProxy.setMaxAllowedPerUserForNewLaunch(address(newLaunch), 500);

        //label
    }

    /////////////////// UPGRADE TESTS ///////////////////

    function test_upgradeNewLaunch() public {
        CurationToken launchToken1 = new CurationToken();
        CurationToken launchToken2 = new CurationToken();
        MockNewLaunch mockNewLaunch = new MockNewLaunch();

        launchToken1.mint(address(launchFactoryProxy), 100 ether);
        launchToken2.mint(address(launchFactoryProxy), 100 ether);

        // Deploy 2 more New Launch Contracts
        NewLaunch newLaunch1 = NewLaunch(
            launchFactoryProxy.launchTokenForCuration(
                address(launchToken1), block.timestamp, block.timestamp + 72 hours, 4_000
            )
        );

        NewLaunch newLaunch2 = NewLaunch(
            launchFactoryProxy.launchTokenForCuration(
                address(launchToken2), block.timestamp, block.timestamp + 72 hours, 4_000
            )
        );

        // All calls from Cpntracts will fail as newFunction() isn't part of their current implementation version.
        vm.expectRevert();
        MockNewLaunch(address(newLaunch)).newFunction();

        vm.expectRevert();
        MockNewLaunch(address(newLaunch1)).newFunction();

        vm.expectRevert();
        MockNewLaunch(address(newLaunch2)).newFunction();

        // Upgrade to MockNewLaunch Implementation
        launchFactoryProxy.getBeaconImplementation().upgradeTo(address(mockNewLaunch));

        // All calls pass as newFunction() is part of the current implementation version hence all contracts get updated saving gas.
        assertEq(MockNewLaunch(address(newLaunch)).newFunction(), "I am new Implementation");

        assertEq(MockNewLaunch(address(newLaunch1)).newFunction(), "I am new Implementation");

        assertEq(MockNewLaunch(address(newLaunch2)).newFunction(), "I am new Implementation");
    }

    error OwnableUnauthorizedAccount(address account);

    function test_upgradeNewLaunchShouldFail() public {
        MockNewLaunch mockNewLaunch = new MockNewLaunch();
        vm.startPrank(address(7));
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, (address(7))));
        launchFactoryProxy.getBeaconImplementation().upgradeTo(address(mockNewLaunch));
        vm.stopPrank();
    }

    /////////////////// STAKING TESTS ///////////////////
    function test_Stake() public {
        uint256 amount = 1 ether;
        curationToken.mint(bob, amount);

        vm.startPrank(bob);
        IERC20(curationToken).approve(address(newLaunch), amount);
        newLaunch.stakeCurationToken(amount);

        assertEq(newLaunch.totalStaked(), amount);
        assertEq(curationToken.balanceOf(address(newLaunch)), amount);
        vm.stopPrank();
    }

    function test_Should_Let_Users_Stake_Only_Available_Amount_To_Stake() public {
        _stakeUnStakeClaimForMultipleUsers(19, "stake");
        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking() - 2 ether);
        assertEq(curationToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking() - 2 ether);

        // At this stage, only 2 ether is available for staking

        curationToken.mint(bob, 1 ether);
        curationToken.mint(alice, 2 ether);

        // Bob stakes 1 ether leaving 1 ether available for staking
        vm.startPrank(bob);
        IERC20(curationToken).approve(address(newLaunch), 1 ether);
        newLaunch.stakeCurationToken(1 ether);
        vm.stopPrank();

        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking() - 1 ether);
        assertEq(curationToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking() - 1 ether);

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
        assertEq(curationToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking());
    }

    function test_Users_Should_Not_Stake_Above_Assigned_Amount_For_Staking() public {
        _stakeUnStakeClaimForMultipleUsers(20, "stake");

        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking());
        assertEq(curationToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking());

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

    function test_User_Should_Stake_Only_Up_To_Max_Allowed_Per_User() public {
        uint256 amount = 10 ether;
        curationToken.mint(address(this), amount);
        assertEq(curationToken.balanceOf(address(this)), amount);

        IERC20(curationToken).approve(address(newLaunch), amount);
        newLaunch.stakeCurationToken(amount);
        uint256 maxAllowed = newLaunch.maxAmountAllowedForOneUser();

        assertEq(newLaunch.stakedAmount(address(this)), maxAllowed);
        assertEq(newLaunch.totalStaked(), maxAllowed);

        assertEq(curationToken.balanceOf(address(newLaunch)), maxAllowed);
        assertEq(curationToken.balanceOf(address(this)), amount - maxAllowed);

        // tries staking more than allowed
        newLaunch.stakeCurationToken(amount);

        // asserted values should remain the same
        assertEq(newLaunch.totalStaked(), maxAllowed);
        assertEq(newLaunch.stakedAmount(address(this)), maxAllowed);

        assertEq(curationToken.balanceOf(address(newLaunch)), maxAllowed);
        assertEq(curationToken.balanceOf(address(this)), amount - maxAllowed);
    }

    function test_Stake_Should_Fail() public {
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Zero_Amount.selector));
        newLaunch.stakeCurationToken(0);

        vm.warp(60 seconds);
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Too_Early_To_Stake.selector));
        newLaunch.stakeCurationToken(1 ether);
    }

    /////////////////// UNSTAKING TESTS ///////////////////

    function test_Unstake() public {
        uint256 amount = 1 ether;

        curationToken.mint(bob, amount);
        assertEq(curationToken.balanceOf(bob), amount);

        vm.startPrank(bob);
        IERC20(curationToken).approve(address(newLaunch), amount);

        newLaunch.stakeCurationToken(amount);
        assertEq(newLaunch.totalStaked(), amount);

        assertEq(curationToken.balanceOf(bob), 0);
        assertEq(curationToken.balanceOf(address(newLaunch)), amount);

        vm.warp(block.timestamp + 4 days); // increase time to 4 days after end time.

        newLaunch.unstakeCurationToken();
        assertEq(newLaunch.totalStaked(), 0);

        assertEq(newLaunch.stakedAmount(bob), 0);
        assertEq(curationToken.balanceOf(bob), amount);

        assertEq(curationToken.balanceOf(address(newLaunch)), 0);
        vm.stopPrank();
    }

    function test_Should_Let_Users_UnStaking_Their_Staked_Token() public {
        _stakeUnStakeClaimForMultipleUsers(19, "stake");
        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking() - 2 ether);
        assertEq(curationToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking() - 2 ether);

        // Staking is still active here given assigned amount for a successful launch is 2 ether short
        assertEq(
            uint256(launchFactoryProxy.getLaunchStatus(address(newLaunch))), uint256(LaunchFactory.LaunchStatus.ACTIVE)
        );

        vm.warp(block.timestamp + 4 days); // increase time to 4 days after end time to end curating period.
        newLaunch.triggerLaunchState(); // This should set the launch status to NOT_SUCCESSFUL given the total staked amount is less than the assigned amount for a successful launch

        assertEq(
            uint256(launchFactoryProxy.getLaunchStatus(address(newLaunch))),
            uint256(LaunchFactory.LaunchStatus.NOT_SUCCESSFUL)
        );

        // Allows Users Unstaking their staked token.
        _stakeUnStakeClaimForMultipleUsers(19, "unstake");
        assertEq(newLaunch.totalStaked(), 0);
        assertEq(curationToken.balanceOf(address(newLaunch)), 0);
    }

    function test_Unstake_Should_Fail() public {
        uint256 amount = 1 ether;
        curationToken.mint(bob, amount);

        // Should revert if user doesn't have any staked amount to unstake
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Zero_Amount.selector));
        newLaunch.unstakeCurationToken();

        vm.startPrank(bob);
        IERC20(curationToken).approve(address(newLaunch), amount);
        newLaunch.stakeCurationToken(amount);
        assertEq(newLaunch.totalStaked(), amount);

        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Launch_Was_Successful_Or_Still_Active.selector));
        newLaunch.unstakeCurationToken();
        vm.stopPrank();
    }

    /////////////////// ADD LIQUIDITY TESTS ///////////////////

    function test_addLiquidity() public {
        _stakeUnStakeClaimForMultipleUsers(20, "stake");
        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking());

        newLaunch.triggerLaunchState();
        assertEq(newLaunch.totalStaked(), 0); // Once triggerLaunchState is called total stake is set to 0

        assertEq(curationToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking());
        assertEq(
            uint256(launchFactoryProxy.getLaunchStatus(address(newLaunch))),
            uint256(LaunchFactory.LaunchStatus.SUCCESSFUL)
        );

        curationToken.mint(address(launchFactoryProxy), 60 ether);
        LaunchFactory.AddLiquidity memory params = LaunchFactory.AddLiquidity({
            token: address(launchToken),
            factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            nftPositionManager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            fee: 3000,
            tickLower: -1200,
            tickUpper: 1200,
            sqrtPriceX96: 79228162514264337593543950336,
            amount0Desired: 60 ether,
            amount1Desired: 60 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this)
        });

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(-1200);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(1200);

        uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(
            79228162514264337593543950336, sqrtRatioAX96, sqrtRatioBX96, 60 ether, 60 ether
        );

        assertEq(IERC721(params.nftPositionManager).balanceOf(address(this)), 0);
        (, uint128 addedLiquidity, uint256 amount0, uint256 amount1) = launchFactoryProxy.addLiquidity(params);

        assertEq(amount0, 60 ether);
        assertEq(amount1, 60 ether);
        assertEq(liquidityToAdd, addedLiquidity);
        assertEq(IERC721(params.nftPositionManager).balanceOf(address(this)), 1);
    }

    function test_addLiquidity_Should_Fail() public {
        LaunchFactory.AddLiquidity memory params = LaunchFactory.AddLiquidity({
            token: address(launchToken),
            factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            nftPositionManager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            fee: 3000,
            tickLower: -1200,
            tickUpper: 1200,
            sqrtPriceX96: 79228162514264337593543950336,
            amount0Desired: 60 ether,
            amount1Desired: 60 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this)
        });

        vm.expectRevert(
            abi.encodeWithSelector(LaunchFactory.LaunchFactory_Launch_Not_Successful_Or_Still_Active.selector)
        );
        launchFactoryProxy.addLiquidity(params);
    }

    /////////////////// CLAIMING TESTS ///////////////////

    function test_Claim() public {
        _stakeUnStakeClaimForMultipleUsers(20, "stake");
        assertEq(newLaunch.totalStaked(), newLaunch.tokensAssignedForStaking());

        newLaunch.triggerLaunchState();
        assertEq(newLaunch.totalStaked(), 0); // Once triggerLaunchState is called total stake is set to 0

        assertEq(curationToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking());
        assertEq(
            uint256(launchFactoryProxy.getLaunchStatus(address(newLaunch))),
            uint256(LaunchFactory.LaunchStatus.SUCCESSFUL)
        );

        curationToken.mint(address(launchFactoryProxy), 60 ether);
        LaunchFactory.AddLiquidity memory params = LaunchFactory.AddLiquidity({
            token: address(launchToken),
            factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            nftPositionManager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            fee: 3000,
            tickLower: -1200,
            tickUpper: 1200,
            sqrtPriceX96: 79228162514264337593543950336,
            amount0Desired: 60 ether,
            amount1Desired: 60 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this)
        });

        launchFactoryProxy.addLiquidity(params);
        assertEq(launchToken.balanceOf(address(newLaunch)), newLaunch.tokensAssignedForStaking());

        _stakeUnStakeClaimForMultipleUsers(20, "claim");
        assertEq(curationToken.balanceOf(address(newLaunch)), 0);
        assertEq(launchToken.balanceOf(address(newLaunch)), 0);
    }

    function test_Claim_Should_Fail() public {
        uint256 amount = 2 ether;
        curationToken.mint(bob, amount);

        // Should revert if user doesn't have any staked amount to unstake
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Zero_Amount.selector));
        newLaunch.claimLaunchToken();

        vm.startPrank(bob);
        IERC20(curationToken).approve(address(newLaunch), amount);
        newLaunch.stakeCurationToken(amount);
        assertEq(newLaunch.totalStaked(), amount);

        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Launch_Not_Successful_Or_Still_Active.selector));
        newLaunch.claimLaunchToken();
        vm.stopPrank();

        _stakeUnStakeClaimForMultipleUsers(19, "stake");

        // After successful curation should fail to let users claim tokens if liquidity hasn't been added to Dex.
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NewLaunch.NewLaunch_Liquidity_Not_Added_To_Dex_Yet.selector));
        newLaunch.claimLaunchToken();
        vm.stopPrank();
    }

    function _stakeUnStakeClaimForMultipleUsers(uint256 _count, bytes32 _direction) internal {
        uint256 amount = 2 ether;

        if (_direction == "stake") {
            for (uint256 i = 0; i < _count; i++) {
                address newAddress = vm.addr(i + 1);
                curationToken.mint(newAddress, amount);
                assertEq(curationToken.balanceOf(newAddress), amount);

                vm.startPrank(newAddress);
                IERC20(curationToken).approve(address(newLaunch), amount);
                newLaunch.stakeCurationToken(amount);

                assertEq(curationToken.balanceOf(newAddress), 0);
                assertEq(newLaunch.stakedAmount(newAddress), amount);
                vm.stopPrank();
            }
        } else if (_direction == "unstake") {
            for (uint256 i = 0; i < _count; i++) {
                address newAddress = vm.addr(i + 1);

                vm.startPrank(newAddress);
                newLaunch.unstakeCurationToken();
                assertEq(newLaunch.stakedAmount(newAddress), 0);
                assertEq(curationToken.balanceOf(newAddress), amount);
                vm.stopPrank();
            }
        } else if (_direction == "claim") {
            for (uint256 i = 0; i < _count; i++) {
                address newAddress = vm.addr(i + 1);

                vm.startPrank(newAddress);
                newLaunch.claimLaunchToken();
                assertEq(newLaunch.stakedAmount(newAddress), 0);
                assertEq(launchToken.balanceOf(newAddress), amount);
                vm.stopPrank();
            }
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function test_ShouldFailToLaunchCuration() public {}
}
