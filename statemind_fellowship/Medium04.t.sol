// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {stdError} from "forge-std/Test.sol";

import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

contract VaultStateNegativeDeltaBugTest is MetaVaultTestHelpers {
    address admin = makeAddr("admin");

    EthVault vault;

    function setUp() public {
        _bootstrapStakeWise();

        vault = _createEthVault(admin, 1000 ether, 1000);
    
        vm.deal(address(this), 32 ether);
        vault.deposit{value: 32 ether}(address(this), address(0));
    }

    function test_revertsOnNegativeDelta() public {
        // Mock the oracle layer: harvest returns a negative totalAssetsDelta,
        // zero unlockedMevDelta (no shared-escrow withdrawal), harvested=true.
        // Signature: harvest(HarvestParams) -> (int256, uint256, bool)
        vm.mockCall(
            keeper,
            abi.encodeWithSelector(IKeeperRewards.harvest.selector),
            abi.encode(int256(-1 ether), uint256(0), true)
        );

        IKeeperRewards.HarvestParams memory params = IKeeperRewards.HarvestParams({
            rewardsRoot: bytes32(0),
            reward: 0,
            unlockedMevReward: 0,
            proof: new bytes32[](0)
        });

        vm.expectRevert(stdError.arithmeticError);
        vault.updateState(params);
    }

    receive() external payable {}
}
