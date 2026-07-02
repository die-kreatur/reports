// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

/**
 * End-to-end reproducer for Statemind MEDIUM-03
 * "MetaVault's redeem assets calculation does not account for sub-vault LTV"
 *
 * SubVaultsRegistry._processRedeemRequests (SubVaultsRegistry.sol:899)
 * computes osTokenShares = convertToShares(redeemAssets) without any LTV
 * haircut. VaultOsToken._mintOsToken (VaultOsToken.sol:152-154) reverts with
 * LowLtv whenever the resulting position exceeds collateral * ltvPercent.
 *
 * Real contracts in this test:
 *   - SubVaultsRegistry, EthMetaVault, EthVault (via the production factories)
 *   - VaultSubVaults, VaultOsToken, VaultEnterExit, VaultState (inheritance)
 *   - BalancedCurator (real production curator)
 *   - OsToken + OsTokenVaultController (real, wired up in test helpers)
 *
 * Stubs (external services, out of audit scope):
 *   - Keeper view methods (already mocked in MetaVaultTestHelpers)
 *   - VaultsRegistry / CuratorsRegistry whitelists
 *   - OsTokenConfig: redeemer() + getConfig() returning a realistic 90% LTV
 */
contract RedeemLtvBugTest is MetaVaultTestHelpers {
    address admin = makeAddr("admin");
    address redeemerAddr = makeAddr("redeemer");

    EthMetaVault metaVault;
    ISubVaultsRegistry registry;
    BalancedCurator curator;
    EthVault subVault;

    uint64 constant LTV_PERCENT = 9e17; // 90 %  — what OsTokenConfig validates as < 1e18

    function setUp() public {
        _bootstrapStakeWise();

        // OsTokenConfig stubs.
        vm.mockCall(
            osTokenConfig,
            abi.encodeWithSelector(IOsTokenConfig.redeemer.selector),
            abi.encode(redeemerAddr)
        );
        IOsTokenConfig.Config memory cfg = IOsTokenConfig.Config({
            liqBonusPercent: uint128(1e18),
            liqThresholdPercent: uint64(95e16),
            ltvPercent: LTV_PERCENT
        });
        vm.mockCall(
            osTokenConfig,
            abi.encodeWithSelector(IOsTokenConfig.getConfig.selector),
            abi.encode(cfg)
        );

        // Build the topology.
        curator = new BalancedCurator();
        metaVault = _deployMetaVault(admin, address(curator), 1000 ether, 1000);
        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());

        subVault = _createEthVault(admin, 1000 ether, 1000);
        _addSubVault(metaVault, admin, address(subVault));

        // Fund meta-vault, then push every wei into the single sub-vault.
        // After this:
        //   - meta-vault.withdrawableAssets() ≈ 0   (forces redeem path)
        //   - meta-vault's stake in sub-vault ≈ 100 ether (the LTV collateral)
        vm.deal(address(this), 100 ether);
        metaVault.deposit{value: 100 ether}(address(metaVault), address(0));
        registry.depositToSubVaults();
    }

    /// 95 ether > 100 ether * 90 % = 90 ether
    ///   - SubVaultsRegistry asks the sub-vault to mint shares for 95 ether
    ///   - _calcMaxOsTokenShares caps the position at ~90 ether
    ///   - _mintOsToken reverts with LowLtv (VaultOsToken.sol:152-154)
    function test_redeemAboveLtv_reverts() public {
        uint256 assetsToRedeem = 95 ether;

        vm.prank(redeemerAddr);
        vm.expectRevert(Errors.LowLtv.selector);
        registry.redeemSubVaultsAssets(assetsToRedeem);
    }
}
