// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

contract RedeemLtvBugTest is MetaVaultTestHelpers {
    address admin = makeAddr("admin");
    address redeemerAddr = makeAddr("redeemer");

    EthMetaVault metaVault;
    ISubVaultsRegistry registry;
    BalancedCurator curator;
    EthVault subVault1;
    EthVault subVault2;

    uint64 constant LTV_PERCENT = 9e17; // 90%

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

        curator = new BalancedCurator();
        metaVault = _deployMetaVault(admin, address(curator), 1000 ether, 1000);
        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());

        subVault1 = _createEthVault(admin, 1000 ether, 1000);
        subVault2 = _createEthVault(admin, 1000 ether, 1000);
        _addSubVault(metaVault, admin, address(subVault1));
        _addSubVault(metaVault, admin, address(subVault2));

        // Fund meta-vault, then push every wei into the sub-vaults. BalancedCurator
        // splits evenly, so each sub-vault receives 50 ether.
        // After this:
        //   - meta-vault's stake in each sub-vault ≈ 50 ether (the LTV collateral)
        //   - per-sub-vault LTV cap = 50 * 90% = 45 ether
        vm.deal(address(this), 100 ether);
        metaVault.deposit{value: 100 ether}(address(metaVault), address(0));
        registry.depositToSubVaults();
    }

    function test_redeemAboveLtv_reverts() public {
        uint256 assetsToRedeem = 95 ether;

        vm.prank(redeemerAddr);
        vm.expectRevert(Errors.LowLtv.selector);
        registry.redeemSubVaultsAssets(assetsToRedeem);
    }
}
