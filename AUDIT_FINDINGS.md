# idOS Smart Contract Security Audit — Findings

**Scope:** `src/IDOSToken.sol`, `src/IDOSVesting.sol`, `src/IDOSNodeStaking.sol`
**Commit:** `6ebbae56`
**Date:** 2026-06-11
**PoCs:** `test/AuditPoC.t.sol` and `test/AuditPoCBreak.t.sol`
Run with: `forge test --match-path "test/AuditPoC*" -vv`

STEP 0: `idos-network/contracts` has 0 open issues and 0 open PRs — no overlap.

---

## Finding 1 — Slashing can be fully evaded by unstaking before the slash lands

- **File:** `src/IDOSNodeStaking.sol` — `unstake()` (L138–172), `slash()` (L190–199)
- **Severity:** Medium (arguing High)
- **Confidence:** HIGH
- **PoC tests:** `test_Finding1_SlashEvasionByUnstaking`, `test_Finding1b_PartialSlashEvasion`, `test_Break_OwnerCannotSlashAfterUnstake`, `test_Break_SlashDoesNotFreezePendingUnstake`

### Description
The contract enforces a 14-day `UNSTAKE_DELAY` between `unstake()` and `withdrawUnstaked()`.
This unbonding period exists so that funds remain slashable while a node's recent behaviour
can still be challenged. Here the delay only gates withdrawal — it does NOT keep funds slashable.

`unstake()` reduces `stakeByNode[node]` immediately (L152–157) and pushes the amount into a
pending `unstakesByUser[msg.sender]` entry that records only `{amount, timestamp}` — no node
reference (L167, struct at L43–46). `slash()` only ever marks the node and is valued against
the current `stakeByNode` balance (L192, L198). Because the queued unstake is detached from
the node entirely, nothing in the unstake queue is ever reachable by slashing.

### Attack scenario (does NOT require mempool front-running)
The contract is deployed on Arbitrum One — no public mempool. The exploit does not need one:

1. Attacker stakes a bond on `node1`.
2. Attacker calls `unstake(node1, fullAmount)` — a normal action. `stakeByNode[node1]` drops to zero.
3. Misbehaviour is discovered by the owner while funds are still in the 14-day unbonding window.
4. `slash(node1)` reverts with `NodeIsUnknown` — node has no live stake.
   Even if a co-staker keeps the node known, the slash only captures remaining live stake,
   never the attacker's queued unstake.
5. After 14 days attacker calls `withdrawUnstaked()` and recovers 100% of the bond
   that should have been slashed.

### Missing check
`unstakesByUser` must record the source node and remain slashable until matured, or pending
unstakes must be frozen when their node is slashed. No such code path exists.

### Severity rationale
- **Not Critical** — attacker recovers only their own bond; no third-party funds stolen.
- **Medium** — "Attacks on logic (behaviour different from business description)": the
  slashing/unbonding security guarantee is completely defeated.
- **Arguing High** — the slashing deterrent is trivially and unconditionally bypassable
  with a single ordinary call, providing zero protection to the protocol.

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

### Impact
Attacker gains nothing — rewards accrue to victim, attacker cannot slash (owner-only).
Pure griefing: victim's funds locked for 14-day unbond, then fully recoverable. Low is correct.

### Missing check
Require `user == msg.sender` or explicit delegation authorization.

---

## No findings in IDOSToken.sol and IDOSVesting.sol

- `IDOSToken` — fixed 1e9 supply minted in constructor, no mint function, ETH rejected. Clean.
- `IDOSVesting` — thin OZ VestingWallet wrapper, cliff/duration validated by base. Clean.