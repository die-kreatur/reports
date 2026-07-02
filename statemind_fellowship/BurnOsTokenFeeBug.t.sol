// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

contract BurnOsTokenFeeBugTest is MetaVaultTestHelpers {
    address user = makeAddr("user");
    address redeemerAddr = makeAddr("redeemer");

    EthVault vault;

    uint64  constant LTV_PERCENT = 9e17;
    uint16  constant TREASURY_FEE_BPS = 1000;
    uint256 constant AVG_REWARD_PER_SEC = 1e11;
    uint256 constant USER_COLLATERAL = 100 ether;
    uint128 constant MINT_AMOUNT = 50e18;

    function setUp() public {
        _bootstrapStakeWise();

        // --- OsTokenConfig stubs (LTV / liquidation params, redeemer addr) ---
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

        // Bootstrap deployed OsTokenVaultController with feePercent=0; turn it on.
        // The test contract is the owner (see MetaVaultTestHelpers._bootstrapStakeWise).
        osTokenControllerImpl.setFeePercent(TREASURY_FEE_BPS);

        // Deploy a real EthVault, fund and deposit as `user`.
        vault = _createEthVault(makeAddr("vaultAdmin"), 1000 ether, 1000);
        vm.deal(user, USER_COLLATERAL);
        vm.prank(user);
        vault.deposit{value: USER_COLLATERAL}(user, address(0));
    }

    function test_burnOsToken_skipsFeeSync_erasesAccruedDebt() public {
        // Mint osToken
        vm.prank(user);
        vault.mintOsToken(user, MINT_AMOUNT, address(0));
        assertEq(vault.osTokenPositions(user), MINT_AMOUNT, "initial debt must equal mint");

        // Turn on staking rewards so the global index starts growing
        vm.prank(keeper);
        osTokenControllerImpl.setAvgRewardPerSecond(AVG_REWARD_PER_SEC);

        // Let fee accrue
        vm.warp(block.timestamp + 365 days);

        // Guard: fee actually accrued
        assertGt(vault.osTokenPositions(user), MINT_AMOUNT, "fee did not accrue - setup broken");

        // Burn all the osToken shares
        vm.prank(user);
        vault.burnOsToken(MINT_AMOUNT);

        // Check if the position is closed and there is no debt
        uint256 debtAfterBurn = vault.osTokenPositions(user);
        assertEq(debtAfterBurn, 0, "position should be reported closed (bug)");
    }
}
