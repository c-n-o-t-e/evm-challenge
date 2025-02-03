// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "./NewLaunch.sol";
import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {BeaconProxy} from "oz/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "oz/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {UUPSUpgradeable} from "ozUpgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "ozUpgradeable/contracts/access/OwnableUpgradeable.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ReentrancyGuardUpgradeable} from "ozUpgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

contract LaunchFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    enum LaunchStatus {
        NOT_ACTIVE,
        ACTIVE,
        SUCCESSFUL,
        NOT_SUCCESSFUL
    }

    struct AddLiquidity {
        address token;
        address factory;
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
        address newLaunchImplementation;
        uint256 minimumCurationPeriod;
        uint256 minimumAmountToLaunch;
        uint256 maximumStakingAmountPercentage;
        uint256 minimumStakingAmountPercentage;
        UpgradeableBeacon newLaunchBeacon;
        mapping(address => LaunchStatus) status;
        mapping(address => address) curationAddress;
        mapping(address => uint256) amountForStaking;
        mapping(address => uint256) amountForLiquidity;
        mapping(address => uint256) stakedAmountAfterCurationPeriod;
    }

    error LaunchFactory_Zero_Address();
    error LaunchFactory_Above_MaxPercentage();
    error LaunchFactory_Start_Time_In_The_Past();
    error LaunchFactory_Below_Minimun_Duration();
    error LaunchFactory_Below_MinimumPercentage();
    error LaunchFactory_Caller_Not_CurationContract();
    error LaunchFactory_Amount_Above_Contract_Balance();
    error LaunchFactory_Curation_Below_Minimum_Duration();
    error LaunchFactory_Balance_Below_Minimum_Launch_Amount();
    error LaunchFactory_Launch_Not_Successful_Or_Still_Active();
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

    modifier onlyCurationContract(address _launch, address _token) {
        if (getLaunchAddress(_token) != _launch) revert LaunchFactory_Caller_Not_CurationContract();
        _;
    }

    function initialize(address _owner, address _curationToken, address _implementation) external initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_curationToken == address(0)) revert LaunchFactory_Zero_Address();
        if (_implementation == address(0)) revert LaunchFactory_Zero_Address();

        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.curationToken = _curationToken;
        $.newLaunchImplementation = _implementation;
        $.newLaunchBeacon = new UpgradeableBeacon(_implementation, msg.sender);
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

    function getLaunchStatus(address _launch) public view returns (LaunchStatus) {
        return _getLaunchFactoryStorage().status[_launch];
    }

    function getLaunchAddress(address _token) public view returns (address) {
        return _getLaunchFactoryStorage().curationAddress[_token];
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
        uint256 _stakingPercentage
    ) external onlyOwner returns (address newLaunch) {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();

        if (_tokenToLaunch == address(0)) revert LaunchFactory_Zero_Address();
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

        uint256 tokenAssignedForStaking = contractLaunchTokenBalance * _stakingPercentage / BIPS_DENOMINATOR;

        BeaconProxy beaconProxy = new BeaconProxy(
            address($.newLaunchBeacon),
            abi.encodeWithSignature(
                "initialize(address,uint256,uint256,uint256,address)",
                _tokenToLaunch,
                _startTime,
                _endTime,
                tokenAssignedForStaking,
                $.curationToken
            )
        );

        newLaunch = address(beaconProxy);
        $.status[address(newLaunch)] = LaunchStatus.ACTIVE;
        $.curationAddress[_tokenToLaunch] = address(newLaunch);
        $.amountForStaking[address(newLaunch)] = tokenAssignedForStaking;
        $.amountForLiquidity[address(newLaunch)] = contractLaunchTokenBalance - tokenAssignedForStaking;

        IERC20(_tokenToLaunch).transfer(newLaunch, contractLaunchTokenBalance);
        // emit LaunchToken(_tokenToLaunch, newLaunch);
    }

    function setMaxAllowedPerUserForNewLaunch(address _launch, uint256 _maxAllowedPerUser) external onlyOwner {
        NewLaunch(_launch).setMaxAllowedPerUser(_maxAllowedPerUser);
    }

    function addLiquidity(AddLiquidity memory _p)
        external
        onlyOwner
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        address curationContract = getLaunchAddress(_p.token);

        if (getLaunchStatus(curationContract) != LaunchStatus.SUCCESSFUL) {
            revert LaunchFactory_Launch_Not_Successful_Or_Still_Active();
        }

        address pool = IUniswapV3Factory(_p.factory).createPool($.curationToken, _p.token, _p.fee);
        IUniswapV3Factory(pool).initialize(_p.sqrtPriceX96);

        address token0 = INonfungiblePositionManager(pool).token0();
        address token1 = INonfungiblePositionManager(pool).token1();

        uint256 curationTokenAmount = token0 == $.curationToken ? _p.amount0Desired : _p.amount1Desired;

        if (curationTokenAmount > IERC20($.curationToken).balanceOf(address(this))) {
            revert LaunchFactory_Amount_Above_Contract_Balance();
        }

        IERC20($.curationToken).transfer(curationContract, curationTokenAmount);

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
        (tokenId, liquidity, amount0, amount1) = NewLaunch(curationContract).addLiquidity(params, _p.nftPositionManager);
    }

    function updateLaunchStatus(address _launch, address _token, LaunchStatus _status)
        external
        onlyCurationContract(_launch, _token)
    {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.status[_launch] = _status;
    }

    function updateLaunchStakedAmountAfterCurationPeriod(address _launch, address _token, uint256 _amount)
        external
        onlyCurationContract(_launch, _token)
    {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        $.stakedAmountAfterCurationPeriod[_launch] = _amount;
    }

    // function withdrawToken(address _token, uint256 _amount) external {
    //     // <--- Check
    //     LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
    //     if ($.status[_launch] != LaunchStatus.ACTIVE) {
    //         IERC20(_token).transfer(msg.sender, _amount);
    //     }
    // }
}
