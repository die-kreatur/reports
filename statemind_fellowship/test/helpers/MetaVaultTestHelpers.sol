// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {EthMetaVault} from "../../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthMetaVaultFactory} from "../../contracts/vaults/ethereum/EthMetaVaultFactory.sol";
import {EthVault} from "../../contracts/vaults/ethereum/EthVault.sol";
import {EthVaultFactory} from "../../contracts/vaults/ethereum/EthVaultFactory.sol";
import {SubVaultsRegistry} from "../../contracts/vaults/SubVaultsRegistry.sol";
import {SubVaultsRegistryFactory} from "../../contracts/vaults/SubVaultsRegistryFactory.sol";
import {OsToken} from "../../contracts/tokens/OsToken.sol";
import {OsTokenVaultController} from "../../contracts/tokens/OsTokenVaultController.sol";
import {ICuratorsRegistry} from "../../contracts/interfaces/ICuratorsRegistry.sol";
import {IVaultsRegistry} from "../../contracts/interfaces/IVaultsRegistry.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {IEthMetaVault} from "../../contracts/interfaces/IEthMetaVault.sol";
import {IEthVault} from "../../contracts/interfaces/IEthVault.sol";
import {ISubVaultsRegistry} from "../../contracts/interfaces/ISubVaultsRegistry.sol";

abstract contract MetaVaultTestHelpers is Test {
    // External service stubs (out of audit scope).
    address internal keeper;
    address internal vaultsRegistry;
    address internal curatorsRegistry;
    address internal osTokenController;
    address internal osTokenConfig;
    address internal sharedMevEscrow;
    address internal validatorsRegistry_;
    address internal validatorsWithdrawals;
    address internal validatorsConsolidations;
    address internal consolidationsChecker;
    address internal depositDataRegistry;

    // Real deployments shared by tests.
    EthMetaVault internal metaVaultImpl;
    EthVault internal ethVaultImpl;
    SubVaultsRegistryFactory internal subVaultsRegistryFactory;
    EthMetaVaultFactory internal metaVaultFactory;
    EthVaultFactory internal ethVaultFactory;
    OsToken internal osToken;
    OsTokenVaultController internal osTokenControllerImpl;

    /// @dev Stand up the whole environment. Call once in setUp().
    function _bootstrapStakeWise() internal {
        keeper = makeAddr("keeper");
        vaultsRegistry = makeAddr("vaultsRegistry");
        curatorsRegistry = makeAddr("curatorsRegistry");
        osTokenConfig = makeAddr("osTokenConfig");
        sharedMevEscrow = makeAddr("sharedMevEscrow");
        validatorsRegistry_ = makeAddr("validatorsRegistry_");
        validatorsWithdrawals = makeAddr("validatorsWithdrawals");
        validatorsConsolidations = makeAddr("validatorsConsolidations");
        consolidationsChecker = makeAddr("consolidationsChecker");
        depositDataRegistry = makeAddr("depositDataRegistry");

        // Keeper / registry view-call stubs. Selector-only encoding matches
        // any argument, so newly-deployed vaults pass validation automatically.
        vm.mockCall(
            keeper, abi.encodeWithSelector(IKeeperRewards.rewardsNonce.selector), abi.encode(uint64(1))
        );
        vm.mockCall(
            keeper, abi.encodeWithSelector(IKeeperRewards.isCollateralized.selector), abi.encode(true)
        );
        vm.mockCall(
            keeper,
            abi.encodeWithSelector(IKeeperRewards.rewards.selector),
            abi.encode(int192(0), uint64(1))
        );
        vm.mockCall(
            keeper, abi.encodeWithSelector(IKeeperRewards.isHarvestRequired.selector), abi.encode(false)
        );
        vm.mockCall(
            vaultsRegistry, abi.encodeWithSelector(IVaultsRegistry.vaults.selector), abi.encode(true)
        );
        // OsTokenVaultController.mintShares checks vaultImpls(...) in addition
        // to vaults(...). Selector-only mock matches any impl.
        vm.mockCall(
            vaultsRegistry, abi.encodeWithSelector(IVaultsRegistry.vaultImpls.selector), abi.encode(true)
        );
        // Real factories call vaultsRegistry.addVault(vault) during createVault.
        // Function returns nothing; intercept it so the call to the EOA-stub
        // address doesn't revert on the EXTCODESIZE check.
        vm.mockCall(vaultsRegistry, abi.encodeWithSelector(IVaultsRegistry.addVault.selector), "");

        // Real OsToken + OsTokenVaultController. OsToken's `_vaultController`
        // immutable would create a circular constructor dependency, so we deploy
        // OsToken with a placeholder controller and grant mint/burn rights to
        // the real controller via setController().
        osToken = new OsToken(address(this), address(0xdead), "Staked ETH", "osETH");
        osTokenControllerImpl = new OsTokenVaultController(
            keeper,
            vaultsRegistry,
            address(osToken),
            makeAddr("treasury"),
            address(this),
            0,                  // feePercent: 0 — no treasury accrual during tests
            type(uint256).max   // capacity: unlimited
        );
        osToken.setController(address(osTokenControllerImpl), true);
        osTokenController = address(osTokenControllerImpl);

        // Real SubVaultsRegistry impl + factory (meta-vault will create its
        // own registry instance through this factory during initialize).
        address subVaultsRegistryImpl = address(
            new SubVaultsRegistry(curatorsRegistry, vaultsRegistry, keeper, osTokenController, osTokenConfig)
        );
        subVaultsRegistryFactory =
            new SubVaultsRegistryFactory(subVaultsRegistryImpl, IVaultsRegistry(vaultsRegistry));

        // Real EthMetaVault implementation.
        metaVaultImpl = new EthMetaVault(
            IEthMetaVault.EthMetaVaultConstructorArgs({
                keeper: keeper,
                vaultsRegistry: vaultsRegistry,
                osTokenVaultController: osTokenController,
                osTokenConfig: osTokenConfig,
                subVaultsRegistryFactory: address(subVaultsRegistryFactory),
                exitingAssetsClaimDelay: 0
            })
        );

        // Real EthVault implementation (used for sub-vaults).
        ethVaultImpl = new EthVault(
            IEthVault.EthVaultConstructorArgs({
                keeper: keeper,
                vaultsRegistry: vaultsRegistry,
                validatorsRegistry: validatorsRegistry_,
                validatorsWithdrawals: validatorsWithdrawals,
                validatorsConsolidations: validatorsConsolidations,
                consolidationsChecker: consolidationsChecker,
                osTokenVaultController: osTokenController,
                osTokenConfig: osTokenConfig,
                sharedMevEscrow: sharedMevEscrow,
                depositDataRegistry: depositDataRegistry,
                exitingAssetsClaimDelay: 0
            })
        );

        // Real production factories. createVault() will deploy the proxy,
        // register the vault, set `vaultAdmin = msg.sender`, then call
        // initialize() on the proxy.
        metaVaultFactory = new EthMetaVaultFactory(address(metaVaultImpl), IVaultsRegistry(vaultsRegistry));
        ethVaultFactory = new EthVaultFactory(address(ethVaultImpl), IVaultsRegistry(vaultsRegistry));
    }

    /// Approve `curator` in the mocked CuratorsRegistry.
    function _approveCurator(address curator) internal {
        vm.mockCall(
            curatorsRegistry,
            abi.encodeWithSelector(ICuratorsRegistry.isCurator.selector, curator),
            abi.encode(true)
        );
    }

    /// Deploy and initialize a real EthMetaVault via the real EthMetaVaultFactory.
    /// admin is pranked as msg.sender so the factory records it as vaultAdmin.
    function _deployMetaVault(address admin, address curator, uint256 capacity, uint16 feePercent)
        internal
        returns (EthMetaVault metaVault)
    {
        _approveCurator(curator);

        bytes memory params = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: capacity,
                feePercent: feePercent,
                metadataIpfsHash: "test"
            })
        );

        vm.prank(admin);
        address proxy = metaVaultFactory.createVault(params);
        metaVault = EthMetaVault(payable(proxy));
    }

    /// Deploy and initialize a real EthVault via the real EthVaultFactory.
    /// EthVault's init requires msg.value >= 1e9 (security deposit). admin is
    /// funded and pranked so the factory records it as vaultAdmin.
    /// isOwnMevEscrow=false → vault uses the shared MEV escrow (mainnet default).
    function _createEthVault(address admin, uint256 capacity, uint16 feePercent)
        internal
        returns (EthVault vault)
    {
        bytes memory params = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: capacity,
                feePercent: feePercent,
                metadataIpfsHash: "test"
            })
        );

        vm.deal(admin, 1e9);
        vm.prank(admin);
        address proxy = ethVaultFactory.createVault{value: 1e9}(params, false);
        vault = EthVault(payable(proxy));
    }

    /// Add a sub-vault to a meta-vault's registry. Must be called by admin.
    function _addSubVault(EthMetaVault metaVault, address admin, address subVault) internal {
        ISubVaultsRegistry registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());
        vm.prank(admin);
        registry.addSubVault(subVault);
    }
}
