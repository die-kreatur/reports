// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";

import {MetaVaultTestHelpers} from "./helpers/MetaVaultTestHelpers.sol";

contract SwapAssetsZeroSharesBugTest is MetaVaultTestHelpers {
    address admin = makeAddr("admin");
    address swapper = makeAddr("swapper");
    address receiver = makeAddr("receiver");

    EthVault subVault;
    EthOsTokenRedeemer redeemer;

    function setUp() public {
        _bootstrapStakeWise();

        // Real redeemer.
        redeemer = new EthOsTokenRedeemer(vaultsRegistry, address(osToken), osTokenController, admin, 0);

        // OsTokenConfig stub: minting osToken reads the LTV config.
        IOsTokenConfig.Config memory cfg = IOsTokenConfig.Config({
            liqBonusPercent: uint128(1e18),
            liqThresholdPercent: uint64(95e16),
            ltvPercent: uint64(9e17) // 90%
        });
        vm.mockCall(osTokenConfig, abi.encodeWithSelector(IOsTokenConfig.getConfig.selector), abi.encode(cfg));

        // Real sub-vault used only to mint osToken and seed the controller's
        // totalShares / totalAssets through real code.
        subVault = _createEthVault(admin, 1000 ether, 1000);
    }

    function test_swap1WeiAbsorbsEth() public {
        vm.deal(address(this), 1 ether);
        subVault.depositAndMintOsToken{value: 1 ether}(address(this), type(uint256).max, address(0));

        // Accrue real protocol rewards so totalAssets grows strictly above
        // totalShares. This is what makes convertToShares(1 wei) floor to zero.
        vm.prank(keeper);
        osTokenControllerImpl.setAvgRewardPerSecond(1e18);
        vm.warp(block.timestamp + 1 days);
        osTokenControllerImpl.updateState();

        // Swapper sends 1 wei expecting osToken shares back.
        vm.deal(swapper, 1 wei);
        uint256 redeemerEthBefore = address(redeemer).balance;
        uint256 receiverOsBefore = osToken.balanceOf(receiver);

        vm.prank(swapper);
        uint256 sharesOut = redeemer.swapAssetsToOsTokenShares{value: 1 wei}(receiver);

        // The 1 wei left the swapper and is now stuck in the redeemer,
        // while no shares were transferred and the swap was never accounted for.
        assertEq(sharesOut, 0, "swap returned zero shares");
        assertEq(swapper.balance, 0, "swapper's 1 wei is gone");
        assertEq(address(redeemer).balance, redeemerEthBefore + 1, "redeemer absorbed the 1 wei");
        assertEq(osToken.balanceOf(receiver), receiverOsBefore, "receiver got no osToken");
        assertEq(redeemer.swappedAssets(), 0, "1 wei never credited to swappedAssets: no refund, no accounting");
    }
}
