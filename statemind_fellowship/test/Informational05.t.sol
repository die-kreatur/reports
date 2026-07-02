// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

contract DepositToSubVaultsCapacityTest is MetaVaultTestHelpers {
    address admin = makeAddr("admin");

    EthMetaVault metaVault;
    ISubVaultsRegistry registry;
    BalancedCurator curator;

    // Two sub-vaults with plenty of room, one whose total capacity is below the
    // even share the curator will hand it.
    EthVault roomyVaultA;
    EthVault roomyVaultB;
    EthVault smallVault;

    function setUp() public {
        _bootstrapStakeWise();

        curator = new BalancedCurator();
        metaVault = _deployMetaVault(admin, address(curator), 10_000 ether, 1000);
        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());

        roomyVaultA = _createEthVault(admin, 1000 ether, 1000);
        roomyVaultB = _createEthVault(admin, 1000 ether, 1000);
        smallVault = _createEthVault(admin, 5 ether, 1000);

        _addSubVault(metaVault, admin, address(roomyVaultA));
        _addSubVault(metaVault, admin, address(roomyVaultB));
        _addSubVault(metaVault, admin, address(smallVault));

        // Give the meta-vault the 30 ether to distribute.
        vm.deal(address(metaVault), 30 ether);
    }

    /// BalancedCurator splits 30 ether -> [10, 10, 10] regardless of capacity.
    /// roomyVaultA and roomyVaultB accept their 10 ether shares, but smallVault's
    /// _deposit reverts: totalAssetsAfter (~10 ether) > capacity() (5 ether).
    /// The whole depositToSubVaults transaction rolls back.
    function test_depositToSubVaults() public {
        vm.expectRevert(Errors.CapacityExceeded.selector);
        registry.depositToSubVaults();

        // Nothing moved: the meta-vault still holds the full amount and the
        // accounted sub-vault total is untouched.
        assertEq(address(metaVault).balance, 30 ether);
        assertEq(registry.subVaultsTotalAssets(), 0);
    }

    receive() external payable {}
}
