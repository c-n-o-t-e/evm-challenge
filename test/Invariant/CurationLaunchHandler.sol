// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AddressSet, LibAddressSet} from "./LibAddressSet.sol";
import {LaunchFactoryTestMock} from "../mocks/LaunchFactoryTestMock.sol";
import {CurationLaunchTestMock} from "../mocks/CurationLaunchTestMock.sol";

import "../CurationLaunch.t.sol";

contract CurationLaunchHandler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    AddressSet _actors;
    CurationToken launchToken;
    CurationToken curationToken;
    CurationLaunchTestMock curationLaunch;
    LaunchFactoryTestMock launchFactoryProxy;

    address currentActor;
    uint256 public ghostTotalStaked;
    uint256 public ghostContractLaunchTokenBalance;
    uint256 public ghostContractCurationTokenBalance;
    mapping(address => uint256) public ghostUsersStakes;
    mapping(address => uint256) public ghostUsersLaunchTokenBalance;
    mapping(address => uint256) public ghostUsersCurationTokenBalance;

    mapping(bytes32 => uint256) public calls;

    constructor(
        CurationToken _launchToken,
        CurationToken _curationToken,
        LaunchFactoryTestMock _launchFactoryProxy,
        CurationLaunchTestMock _curationLaunch
    ) {
        launchToken = _launchToken;
        curationToken = _curationToken;
        curationLaunch = _curationLaunch;
        launchFactoryProxy = _launchFactoryProxy;
        ghostContractLaunchTokenBalance = 100 ether;
    }

    modifier createActor() {
        if (actors().length == 30) return;
        if (msg.sender == address(curationLaunch)) return;
        if (msg.sender == address(launchFactoryProxy)) return;

        currentActor = msg.sender;
        _actors.add(currentActor);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function stake(uint256 _amount) external createActor countCall("stake") {
        if (msg.sender == address(curationLaunch)) return;
        if (msg.sender == address(launchFactoryProxy)) return;
        _amount = bound(_amount, 1 ether, 2 ether);

        curationLaunch.triggerLaunchState();

        if (
            launchFactoryProxy.getLaunchStatus(address(curationLaunch)) == LaunchFactoryTestMock.LaunchStatus.ACTIVE
                && _amount != 0
        ) {
            uint256 _ghostAmount = _amount;
            if (ghostUsersStakes[currentActor] + _ghostAmount > curationLaunch.maxAmountAllowedForOneUser()) {
                _ghostAmount = curationLaunch.maxAmountAllowedForOneUser() - ghostUsersStakes[currentActor];
            }

            if (ghostTotalStaked + _ghostAmount > curationLaunch.tokensAssignedForStaking()) {
                _ghostAmount = curationLaunch.tokensAssignedForStaking() - ghostTotalStaked;
            }

            curationToken.mint(currentActor, _amount);
            vm.startPrank(currentActor);
            curationToken.approve(address(curationLaunch), _amount);
            curationLaunch.stakeCurationToken(_amount);
            vm.stopPrank();

            ghostTotalStaked += _ghostAmount;
            ghostContractCurationTokenBalance += _ghostAmount;
            ghostUsersStakes[currentActor] = ghostUsersStakes[currentActor] + _ghostAmount;

            _ghostAmount = _amount > _ghostAmount ? _amount - _ghostAmount : 0;

            ghostUsersCurationTokenBalance[currentActor] = ghostUsersCurationTokenBalance[currentActor] + _ghostAmount;
        }
    }

    bool entered;

    function unStake(uint256 actorIndexSeed) external useActor(actorIndexSeed) countCall("unStake") {
        uint256 _amount = ghostUsersStakes[currentActor];
        // if (actors().length > 5) vm.warp(block.timestamp + 5 days);

        curationLaunch.triggerLaunchState();
        if (
            launchFactoryProxy.getLaunchStatus(address(curationLaunch))
                == LaunchFactoryTestMock.LaunchStatus.NOT_SUCCESSFUL && _amount != 0
        ) {
            if (!entered) {
                ghostContractLaunchTokenBalance -= 100 ether;
                entered = true;
            }

            vm.startPrank(currentActor);
            curationLaunch.unstakeCurationToken();
            vm.stopPrank();

            ghostUsersStakes[currentActor] = 0;
            ghostContractCurationTokenBalance -= _amount;
            ghostUsersCurationTokenBalance[currentActor] = ghostUsersCurationTokenBalance[currentActor] + _amount;
        }
    }

    function claim(uint256 actorIndexSeed) external useActor(actorIndexSeed) countCall("claim") {
        uint256 _amount = ghostUsersStakes[currentActor];
        curationLaunch.triggerLaunchState();

        if (
            launchFactoryProxy.getLaunchStatus(address(curationLaunch)) == LaunchFactoryTestMock.LaunchStatus.SUCCESSFUL
                && _amount != 0
        ) {
            if (!curationLaunch.liquidityProvided()) {
                vm.startPrank(address(launchFactoryProxy));
                curationLaunch.addLiquidity();
                ghostContractLaunchTokenBalance -= 60 ether;
                vm.stopPrank();
            }

            vm.startPrank(currentActor);
            curationLaunch.claimLaunchToken();
            vm.stopPrank();

            ghostUsersStakes[currentActor] = 0;
            ghostContractLaunchTokenBalance -= _amount;
            ghostContractCurationTokenBalance -= _amount;
            ghostUsersLaunchTokenBalance[currentActor] = ghostUsersLaunchTokenBalance[currentActor] + _amount;
        }
    }

    function spotPurchase(uint256 actorIndexSeed, uint256 actorIndexSeed1)
        external
        useActor(actorIndexSeed)
        countCall("spotPurchase")
    {}

    function actors() public view returns (address[] memory) {
        return _actors.addrs;
    }
}
