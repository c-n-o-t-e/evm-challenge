// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "oz/contracts/token/ERC20/IERC20.sol";
import {CurationLaunchTestMock} from "./CurationLaunchTestMock.sol";
import {IUniswapV3Factory} from "../../src/interfaces/IUniswapV3Factory.sol";
import {BeaconProxy} from "oz/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "oz/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {UUPSUpgradeable} from "ozUpgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "ozUpgradeable/contracts/access/OwnableUpgradeable.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {ReentrancyGuardUpgradeable} from "ozUpgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

contract LaunchFactoryTestMock is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
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
    error LaunchFactory_Curation_Already_Launched();
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

    /// @custom:oz-upgrades-unsafe-allow constructor
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

    function launchTokenForCuration(
        address _tokenToLaunch,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _stakingPercentage
    ) external onlyOwner returns (address newLaunch) {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();

        if (_tokenToLaunch == address(0)) revert LaunchFactory_Zero_Address();
        if (_startTime < block.timestamp) revert LaunchFactory_Start_Time_In_The_Past();
        if (getLaunchAddress(_tokenToLaunch) != address(0)) revert LaunchFactory_Curation_Already_Launched();
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
    }

    function setMaxAllowedPerUserForNewLaunch(address _launch, uint256 _maxAllowedPerUser) external onlyOwner {
        CurationLaunchTestMock(_launch).setMaxAllowedPerUser(_maxAllowedPerUser);
    }

    function addLiquidity(address _token)
        external
        onlyOwner
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        LaunchFactoryStorage storage $ = _getLaunchFactoryStorage();
        address curationContract = getLaunchAddress(_token);

        if (getLaunchStatus(curationContract) != LaunchStatus.SUCCESSFUL) {
            revert LaunchFactory_Launch_Not_Successful_Or_Still_Active();
        }

        (tokenId, liquidity, amount0, amount1) = CurationLaunchTestMock(curationContract).addLiquidity();
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

    /////////////////// VIEW FUNCTION ///////////////////

    function getMinimumStakingAmountPercentage() external view returns (uint256) {
        return _getLaunchFactoryStorage().minimumStakingAmountPercentage;
    }

    function getMaximumStakingAmountPercentage() external view returns (uint256) {
        return _getLaunchFactoryStorage().maximumStakingAmountPercentage;
    }

    function getMinimumCurationPeriod() external view returns (uint256) {
        return _getLaunchFactoryStorage().minimumCurationPeriod;
    }

    function getMinimumLaunchAmount() external view returns (uint256) {
        return _getLaunchFactoryStorage().minimumAmountToLaunch;
    }

    function getBeaconImplementation() external view returns (UpgradeableBeacon) {
        return _getLaunchFactoryStorage().newLaunchBeacon;
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
}
