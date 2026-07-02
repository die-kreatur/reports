// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

/**
 * @title End-to-end reproducer for Statemind INFORMATIONAL-03
 *
 * "Missing checks for sub-vault capacity" — SubVaultsRegistry.depositToSubVaults
 * distributes assets across sub-vaults in a single transaction loop. A
 * CapacityExceeded revert on ANY one sub-vault causes the ENTIRE batch to revert.
 *
 * EVERY contract under audit is real production code:
 *   - SubVaultsRegistry (real, created by EthMetaVault during init via factory)
 *   - BalancedCurator (real)
 *   - EthMetaVault (real, deployed via ERC1967 proxy + initialize)
 *   - EthVault (real, used for both sub-vaults; deployed via ERC1967 proxy
 *               with the 1e9 wei security deposit, just like on mainnet)
 *   - VaultEnterExit, VaultEthStaking, VaultState, VaultMev, VaultOsToken,
 *     VaultValidators, VaultFee, VaultAdmin, VaultVersion — all REAL via the
 *     EthVault/EthMetaVault inheritance chain.
 *
 * External services (out of audit scope) are stubbed with vm.mockCall:
 *   - Keeper view methods (rewardsNonce, isCollateralized, rewards,
 *     isHarvestRequired) — the oracle layer
 *   - VaultsRegistry.vaults — the deployment-registration whitelist
 *   - CuratorsRegistry.isCurator — the curator approval whitelist
 */
contract DepositToSubVaultsBugTest is MetaVaultTestHelpers {
    address admin = makeAddr("admin");

    EthMetaVault metaVault;
    ISubVaultsRegistry registry;
    BalancedCurator curator;
    EthVault highCap;
    EthVault lowCap;

    function setUp() public {
        _bootstrapStakeWise();

        curator = new BalancedCurator();
        metaVault = _deployMetaVault(admin, address(curator), 10_000 ether, 1000);
        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());

        highCap = _createEthVault(admin, 1000 ether, 1000);
        lowCap = _createEthVault(admin, 10 ether, 1000);

        _addSubVault(metaVault, admin, address(highCap));
        _addSubVault(metaVault, admin, address(lowCap));

        // Pre-fill lowCap close to its capacity. In production this would come
        // from reward accrual or a direct deposit by anyone (sub-vault deposits
        // are open, not gated by the meta-vault).
        //
        // lowCap starts with 1e9 wei from the security deposit; we top it up
        // to (capacity - 1 ether) so only 1 ether of headroom remains.
        vm.deal(address(this), 100 ether);
        uint256 toFill = 10 ether - 1 ether - 1e9;
        lowCap.deposit{value: toFill}(address(this), address(0));

        // Give MetaVault 20 ether of withdrawableAssets to distribute.
        vm.deal(address(metaVault), 20 ether);
    }

    /// THE BUG.
    /// BalancedCurator (real) splits 20 ETH -> [10, 10].
    /// Iteration 1: highCap accepts 10 ETH (real VaultEnterExit._deposit).
    /// Iteration 2: lowCap's real _deposit reverts because
    ///   _totalAssets (~9 ether) + 10 ether > capacity (10 ether)
    /// at the real `if (totalAssetsAfter > capacity()) revert Errors.CapacityExceeded;`
    /// in VaultEnterExit.sol:129. Whole tx rolls back.
    function test_depositToSubVaults() public {
        vm.expectRevert(Errors.CapacityExceeded.selector);
        registry.depositToSubVaults();

        // Sanity: meta-vault still holds its 20 ether (no partial state changes).
        assertEq(address(metaVault).balance, 20 ether);
    }

    receive() external payable {}
}
