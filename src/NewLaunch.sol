// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13; // update version

import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";
import {ILaunchFactory} from "./interfaces/ILaunchFactory.sol";
import {ICurationToken} from "./interfaces/ICurationToken.sol";
import {SafeERC20} from "oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "ozUpgradeable/contracts/proxy/utils/Initializable.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

// Todo: add access control
contract NewLaunch is Initializable {
    using SafeERC20 for IERC20;

    ILaunchFactory public factory;

    uint256 public endTime;
    uint256 public startTime;
    uint256 public totalStaked;
    uint256 public maxAllowedPerUser;
    uint256 public tokensAssignedForStaking;

    bool public liquidityProvided;

    address public launchToken;
    address public curationToken;

    uint256 constant BIPS_DENOMINATOR = 10_000;
    uint256 constant MAX_ALLOWED_PER_USER = 500; // 5%

    mapping(address => uint256) public stakedAmount;

    error NewLaunch_Zero_Amount();
    error NewLaunch_Still_Active();
    error NewLaunch_Invalid_Token();
    error NewLaunch_Too_Late_To_Stake();
    error NewLaunch_Too_Early_To_Stake();
    error NewLaunch_Caller_Not_Factory();
    error NewLaunch_Above_MaxPercentage();
    error NewLaunch_Launch_Already_Triggered();
    error NewLaunch_Liquidity_Not_Added_To_Dex_Yet();
    error NewLaunch_Amount_Above_Amount_For_Liquidity();
    error NewLaunch_Launch_Was_Successful_Or_Still_Active();
    error NewLaunch_Launch_Not_Successful_Or_Still_Active();

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event LaunchTriggered(ILaunchFactory.LaunchStatus status, uint256 totalStakedAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tokenToLaunch,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokensAssignedForStaking,
        address _curationToken
    ) public initializer {
        endTime = _endTime;
        startTime = _startTime;
        launchToken = _tokenToLaunch;
        curationToken = _curationToken;
        factory = ILaunchFactory(msg.sender);
        tokensAssignedForStaking = _tokensAssignedForStaking;
    }

    modifier onlyFactory() {
        if (msg.sender != address(factory)) revert NewLaunch_Caller_Not_Factory();
        _;
    }

    // add access control only factory can call this function
    function setMaxAllowedPerUser(uint256 _maxAllowedPerUser) external onlyFactory {
        if (_maxAllowedPerUser > MAX_ALLOWED_PER_USER) revert NewLaunch_Above_MaxPercentage();
        maxAllowedPerUser = _maxAllowedPerUser;
        // emit
    }

    function maxAmountAllowedForOneUser() public view returns (uint256) {
        return tokensAssignedForStaking * maxAllowedPerUser / BIPS_DENOMINATOR;
    }

    //Todo: consider if there should be a minimum amount to stake
    function stakeCurationToken(uint256 _amount) external {
        triggerLaunchState();

        if (_amount == 0) revert NewLaunch_Zero_Amount();
        if (block.timestamp < startTime) revert NewLaunch_Too_Early_To_Stake();

        if (factory.getLaunchStatus(address(this)) != ILaunchFactory.LaunchStatus.ACTIVE) {
            revert NewLaunch_Too_Late_To_Stake();
        }

        uint256 _stakedAmount = stakedAmount[msg.sender];

        // prevents a single user from staking more than 5% of the total tokens assigned for staking
        if (_stakedAmount + _amount > maxAmountAllowedForOneUser()) {
            _amount = maxAmountAllowedForOneUser() - _stakedAmount;
        }

        if (_amount == 0) return;
        uint256 _amountAvailableForStaking = tokensAssignedForStaking - totalStaked;

        // ensures that the total staked amount does not exceed the amount of tokens assigned for staking
        if (_amount > _amountAvailableForStaking) {
            _amount = _amountAvailableForStaking;
        }

        IERC20(curationToken).safeTransferFrom(msg.sender, address(this), _amount);
        stakedAmount[msg.sender] += _amount;
        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    function unstakeCurationToken() external {
        triggerLaunchState();
        uint256 _stakedAmount = stakedAmount[msg.sender];

        if (_stakedAmount == 0) revert NewLaunch_Zero_Amount();
        if (factory.getLaunchStatus(address(this)) != ILaunchFactory.LaunchStatus.NOT_SUCCESSFUL) {
            revert NewLaunch_Launch_Was_Successful_Or_Still_Active();
        }

        stakedAmount[msg.sender] -= _stakedAmount;
        IERC20(curationToken).safeTransfer(msg.sender, _stakedAmount);

        emit Unstaked(msg.sender, _stakedAmount);
    }

    function triggerLaunchState() public {
        if (factory.getLaunchStatus(address(this)) != ILaunchFactory.LaunchStatus.ACTIVE) return;

        if (totalStaked == tokensAssignedForStaking) {
            totalStaked = 0;
            factory.updateLaunchStatus(address(this), launchToken, ILaunchFactory.LaunchStatus.SUCCESSFUL);
            factory.updateLaunchStakedAmountAfterCurationPeriod(address(this), launchToken, tokensAssignedForStaking);
        } else if (block.timestamp > endTime) {
            totalStaked = 0;
            factory.updateLaunchStakedAmountAfterCurationPeriod(address(this), launchToken, totalStaked);
            factory.updateLaunchStatus(address(this), launchToken, ILaunchFactory.LaunchStatus.NOT_SUCCESSFUL);

            // If curation isn't successful send back new tokens to launch back to the factory
            IERC20(launchToken).safeTransfer(address(factory), IERC20(launchToken).balanceOf(address(this)));
        }

        emit LaunchTriggered(factory.getLaunchStatus(address(this)), totalStaked);
    }

    function claimLaunchToken() external {
        triggerLaunchState();
        uint256 _stakedAmount = stakedAmount[msg.sender];
        if (_stakedAmount == 0) revert NewLaunch_Zero_Amount();

        if (factory.getLaunchStatus(address(this)) != ILaunchFactory.LaunchStatus.SUCCESSFUL) {
            revert NewLaunch_Launch_Not_Successful_Or_Still_Active();
        }
        if (!liquidityProvided) revert NewLaunch_Liquidity_Not_Added_To_Dex_Yet();

        stakedAmount[msg.sender] = 0;
        ICurationToken(curationToken).burn(_stakedAmount);

        // transfer the launch token to the user on a ratio of their staked amount ie 1:1
        IERC20(launchToken).safeTransfer(msg.sender, _stakedAmount);

        emit Claimed(msg.sender, _stakedAmount);
    }

    function addLiquidity(INonfungiblePositionManager.MintParams memory params, address _nftPositionManager)
        external
        payable
        onlyFactory
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (params.token0 != launchToken && params.token0 != curationToken) revert NewLaunch_Invalid_Token();
        if (params.token1 != launchToken && params.token1 != curationToken) revert NewLaunch_Invalid_Token();

        uint256 lunchTokenAmount = params.token0 == launchToken ? params.amount0Desired : params.amount1Desired;

        if (lunchTokenAmount > factory.getLaunchAmountForLiquidity(address(this))) {
            revert NewLaunch_Amount_Above_Amount_For_Liquidity();
        }

        IERC20(params.token0).approve(address(_nftPositionManager), params.amount0Desired);
        IERC20(params.token1).approve(address(_nftPositionManager), params.amount1Desired);

        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(_nftPositionManager).mint(params);

        if (amount0 < params.amount0Desired) {
            IERC20(params.token0).forceApprove(address(_nftPositionManager), 0);
            uint256 refund0 = params.amount0Desired - amount0;
            IERC20(params.token0).transfer(msg.sender, refund0);
        }
        if (amount1 < params.amount1Desired) {
            IERC20(params.token1).forceApprove(address(_nftPositionManager), 0);
            uint256 refund1 = params.amount1Desired - amount1;
            IERC20(params.token1).safeTransfer(msg.sender, refund1);
        }

        liquidityProvided = true;
        // emit
    }
}
