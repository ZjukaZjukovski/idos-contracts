# idOS Smart Contract Security Audit — Findings

**Scope:** `src/IDOSToken.sol`, `src/IDOSVesting.sol`, `src/IDOSNodeStaking.sol`
**Commit:** `6ebbae56`
**Date:** 2026-06-11
**PoCs:** `test/AuditPoC.t.sol` (run with `forge test --match-path test/AuditPoC.t.sol -vv`)

STEP 0: `idos-network/contracts` has 0 open issues and 0 open PRs — no overlap.

---

## Finding 1 — Slashing can be fully evaded by unstaking before the slash lands

- **File:** `src/IDOSNodeStaking.sol` — `unstake()` (L138–172), `slash()` (L190–199)
- **Severity:** Medium
- **Confidence:** HIGH
- **PoC:** `test_Finding1_SlashEvasionByUnstaking`, `test_Finding1b_PartialSlashEvasion`

### Description
The contract enforces a 14-day `UNSTAKE_DELAY` between `unstake()` and `withdrawUnstaked()`.
This unbonding period exists so that funds remain slashable while a node's recent behaviour
can still be challenged. Here the delay only gates withdrawal — it does NOT keep funds slashable.

`unstake()` reduces `stakeByNode[node]` immediately (L152–157) and moves the amount into a
pending `unstakesByUser` entry. `slash()` only ever acts on the current `stakeByNode` balance
(L192, L198). Nothing in the unstake queue is ever reachable by slashing.

### Attack scenario
1. Attacker stakes a bond on `node1`.
2. The node misbehaves.
3. Before the owner's `slash(node1)` transaction is mined, attacker calls `unstake(node1, fullAmount)`.
4. `stakeByNode[node1]` is now zero. `slash(node1)` reverts with `NodeIsUnknown`.
5. After 14 days attacker calls `withdrawUnstaked()` and recovers 100% of the stake
   that should have been slashed.

### Missing check
In-flight unstakes from a node slashed within the unbonding window must remain slashable.
`slash()` must reach into pending `unstakesByUser` entries, or pending unstakes must be
frozen when their source node is slashed. No such code path exists.

---

## Finding 2 — `stake(user, …)` lets anyone force a victim's approved tokens into an attacker-chosen node

- **File:** `src/IDOSNodeStaking.sol` — `stake()` (L108–136)
- **Severity:** Low
- **Confidence:** HIGH
- **PoC:** `test_Finding2_ForcedStakeOnBehalf`

### Description
`stake(address user, address node, uint256 amount)` pulls tokens from `user` but lets the
caller pick both `user` and `node`. Any third party can spend a victim's standing allowance
and lock the victim's funds into a node the victim did not choose.

### Attack scenario
1. Victim approves the staking contract.
2. Attacker calls `stake(victim, attackerChosenNode, victimAllowance)`.
3. Victim's tokens are staked against attacker's chosen node without victim's consent.

### Missing check
Require `user == msg.sender` or an explicit delegation authorization.

---

## No findings in IDOSToken.sol and IDOSVesting.sol

- `IDOSToken` — fixed 1e9 supply minted in constructor, no mint function, ETH rejected. Clean.
- `IDOSVesting` — thin OZ VestingWallet wrapper, cliff/duration validated by base. Clean.