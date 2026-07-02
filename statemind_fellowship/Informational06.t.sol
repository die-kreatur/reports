// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {ISubVaultsCurator} from "../contracts/interfaces/ISubVaultsCurator.sol";

contract BalancedCuratorExitBugTest is Test {
    BalancedCurator curator;

    address vaultA = address(0xA1);
    address vaultB = address(0xA2);
    address vaultC = address(0xA3);
    address vaultD = address(0xA4);
    address vaultE = address(0xA5); // ejecting

    function setUp() public {
        curator = new BalancedCurator();
    }

    // Since there are 4 non-ejecting sub-vaults and 16 assets to exit,
    // all the assets should have been distributed evenly in one iteration,
    // but it takes 2 iterations and the first sub-vault gets looses more money.
    function test_unevenExitDistribution() public view {
        address[] memory vaults = new address[](5);
        vaults[0] = vaultA;
        vaults[1] = vaultB;
        vaults[2] = vaultC;
        vaults[3] = vaultD;
        vaults[4] = vaultE;

        uint256[] memory balances = new uint256[](5);
        balances[0] = 100 ether;
        balances[1] = 100 ether;
        balances[2] = 100 ether;
        balances[3] = 100 ether;
        balances[4] = 100 ether;

        ISubVaultsCurator.ExitRequest[] memory result =
            curator.getExitRequests(16, vaults, balances, vaultE);

        assertEq(result[0].assets, 7, "vaultA receives the entire amount (bug)");
        assertEq(result[1].assets, 3, "vaultB is starved despite being active");
        assertEq(result[2].assets, 3, "vaultC is starved despite being active");
        assertEq(result[3].assets, 3, "vaultD is starved despite being active");
        assertEq(result[4].assets, 0, "ejecting vault correctly receives nothing");
    }
}
