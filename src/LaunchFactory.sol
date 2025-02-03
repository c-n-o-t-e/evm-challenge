// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "./NewLaunch.sol";
import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

import {UUPSUpgradeable} from "ozUpgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "ozUpgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "ozUpgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

contract LaunchFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    enum LaunchStatus {
        NOT_ACTIVE,
        ACTIVE,
        SUCCESSFUL,
        NOT_SUCCESSFUL
    }

    struct AddLiquidity {
        address factory;
        address curationContract;
        address nftPositionManager;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
    }

    uint256 constant MAX_PERCENTAGE = 5_000;
    uint256 constant BIPS_DENOMINATOR = 10_000;
    uint256 constant MINIMUM_PERCENTAGE = 2_000;
    uint256 constant MINIMUM_CURATION_PERIOD = 24 hours;

    struct LaunchFactoryStorage {
        address curationToken;
        uint256 minimumCurationPeriod;
        uint256 minimumAmountToLaunch;
        uint256 maximumStakingAmountPercentage;
        uint256 minimumStakingAmountPercentage;
        mapping(address => LaunchStatus) status;
        mapping(address => address) tokenAddress;
        mapping(address => uint256) amountForStaking;
        mapping(address => uint256) amountForLiquidity;
        mapping(address => uint256) stakedAmountAfterCurationPeriod;
    }

    error LaunchFactory_Above_MaxPercentage();
    error LaunchFactory_Start_Time_In_The_Past();
    error LaunchFactory_Below_Minimun_Duration();
    error LaunchFactory_Below_MinimumPercentage();
    error LaunchFactory_Curation_Below_Minimum_Duration();
    error NewLaunch_Launch_Not_Successful_Or_Still_Active();
    error LaunchFactory_Balance_Below_Minimum_Launch_Amount();
    error LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage();

    // keccak256(abi.encode(uint256(keccak256("bio.storage.LaunchFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LaunchFactoryStorageLocation =
        0x40f6a347e5b73cd2e1f4103810af363b4099ae3a1e65d0bfb823ba7ce33e9900;

    function _getLaunchFactoryStorage() private pure returns (LaunchFactoryStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := LaunchFactoryStorageLocation
        }
    }

    // /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _curationToken) external initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.curationToken = _curationToken;
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation.
     * @dev Internal function to authorize upgrading the contract to a new implementation.
     *      Overrides the UUPSUpgradeable `_authorizeUpgrade` function.
     *      Restricted to the contract owner.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setMinimumLaunchAmount(uint256 _minimumAmountToLaunch) external onlyOwner {
        // emit
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.minimumAmountToLaunch = _minimumAmountToLaunch;
    }

    function setMinimumCurationPeriod(uint256 _minimumCurationPeriod) external onlyOwner {
        if (_minimumCurationPeriod < MINIMUM_CURATION_PERIOD) revert LaunchFactory_Below_Minimun_Duration();
        // emit
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.minimumCurationPeriod = _minimumCurationPeriod;
    }

    function setMaximumStakingAmountPercentage(uint256 _maximumStakingAmountPercentage) external onlyOwner {
        if (_maximumStakingAmountPercentage > MAX_PERCENTAGE) revert LaunchFactory_Above_MaxPercentage();
        // emit
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.maximumStakingAmountPercentage = _maximumStakingAmountPercentage;
    }

    function setMinimumStakingAmountPercentage(uint256 _minimumStakingAmountPercentage) external onlyOwner {
        if (_minimumStakingAmountPercentage < MINIMUM_PERCENTAGE) revert LaunchFactory_Below_MinimumPercentage();
        // emit
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.minimumStakingAmountPercentage = _minimumStakingAmountPercentage;
    }

    // should all start with get
    function getLaunchStatus(address _launch) public view returns (LaunchStatus) {
        return _getLaunchFactoryStorage().status[_launch];
    }

    function getLaunchToken(address _launch) public view returns (address) {
        return _getLaunchFactoryStorage().tokenAddress[_launch];
    }

    function getLaunchAmountForStaking(address _launch) external view returns (uint256) {
        return _getLaunchFactoryStorage().amountForStaking[_launch];
    }

    function getLaunchAmountForLiquidity(address _launch) external view returns (uint256) {
        return _getLaunchFactoryStorage().amountForLiquidity[_launch];
    }

    function getLaunchStakedAmountAfterCurationPeriod(address _launch) external view returns (uint256) {
        return _getLaunchFactoryStorage().stakedAmountAfterCurationPeriod[_launch];
    }

    function launchTokenForCuration(
        address _tokenToLaunch,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _stakingPercentage,
        address _nonfungiblePositionManager
    ) external onlyOwner returns (address newLaunch) {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();

        if (_startTime < block.timestamp) revert LaunchFactory_Start_Time_In_The_Past();
        if (_endTime < _startTime + $.minimumCurationPeriod) revert LaunchFactory_Curation_Below_Minimum_Duration();

        uint256 contractLaunchTokenBalance = IERC20(_tokenToLaunch).balanceOf(address(this));

        if (contractLaunchTokenBalance < $.minimumAmountToLaunch) {
            revert LaunchFactory_Balance_Below_Minimum_Launch_Amount();
        }

        if (
            _stakingPercentage > $.maximumStakingAmountPercentage
                || _stakingPercentage < $.minimumStakingAmountPercentage
        ) {
            revert LaunchFactory_Balance_Below_Or_Above_Minimum_Staking_Percentage();
        }

        uint256 tokenAvailableForStaking = contractLaunchTokenBalance * _stakingPercentage / BIPS_DENOMINATOR;
        newLaunch = address(
            new NewLaunch(
                _tokenToLaunch,
                _startTime,
                _endTime,
                tokenAvailableForStaking,
                $.curationToken,
                _nonfungiblePositionManager
            )
        );

        $.status[address(newLaunch)] = LaunchStatus.ACTIVE;
        $.tokenAddress[address(newLaunch)] = _tokenToLaunch;
        $.amountForStaking[address(newLaunch)] = tokenAvailableForStaking;
        $.amountForLiquidity[address(newLaunch)] = contractLaunchTokenBalance - tokenAvailableForStaking;

        IERC20(_tokenToLaunch).transfer(newLaunch, contractLaunchTokenBalance);
        // emit LaunchToken(_tokenToLaunch, newLaunch);
    }

    // add access control only owner can call this function
    function setMaxAllowedPerUserForNewLaunch(address _launch, uint256 _maxAllowedPerUser) external onlyOwner {
        NewLaunch(_launch).setMaxAllowedPerUser(_maxAllowedPerUser);
    }

    function addLiquidity(AddLiquidity memory _p)
        external
        onlyOwner
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (getLaunchStatus(_p.curationContract) != LaunchStatus.SUCCESSFUL) {
            revert NewLaunch_Launch_Not_Successful_Or_Still_Active();
        }

        address pool = IUniswapV3Factory(_p.factory).createPool(
            _getLaunchFactoryStorage().curationToken, getLaunchToken(_p.curationContract), _p.fee
        );
        IUniswapV3Factory(pool).initialize(_p.sqrtPriceX96);

        address token0 = INonfungiblePositionManager(pool).token0();
        address token1 = INonfungiblePositionManager(pool).token1();

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: _p.fee,
            tickLower: _p.tickLower,
            tickUpper: _p.tickUpper,
            amount0Desired: _p.amount0Desired,
            amount1Desired: _p.amount1Desired,
            amount0Min: _p.amount0Min,
            amount1Min: _p.amount1Min,
            recipient: _p.recipient,
            deadline: block.timestamp
        });
        (tokenId, liquidity, amount0, amount1) = NewLaunch(_p.curationContract).addLiquidity(params);
    }

    function updateLaunchStatus(address _launch, LaunchStatus _status) external {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.status[_launch] = _status;
    }

    function updateLaunchStakedAmountAfterCurationPeriod(address _launch, uint256 _amount) external {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.stakedAmountAfterCurationPeriod[_launch] = _amount;
    }

    // function withdrawToken(address _token, uint256 _amount) external {
    //     // <--- Check
    //     if (submissions[_token].status != LaunchStatus.ACTIVE) {
    //         IERC20(_token).transfer(msg.sender, _amount);
    //     }
    // }
}
