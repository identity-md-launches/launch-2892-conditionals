# Conditionals test properties

The original constructor, metadata, event, factory distribution, authorization,
and basic ERC-20 tests remain in `Conditionals.t.sol`. The additional edge cases
and algebraic properties are in `Conditionals.edges.t.sol`; the existing handler
and ledger in `Conditionals.invariant.t.sol` have been extended.

## Property selection

The five discovery perspectives from the supplied Pashov fizz reference were
applied locally. The Trail of Bits reference informed input bounds, fixed edge
examples, failure classification, and checks against vacuous assertions.

| Perspective | Required property and basis | Coverage |
| --- | --- | --- |
| Conservation | The constructor mints exactly `10^27` units once (`src/Conditionals.sol:11-15`); every transfer conserves that supply. | Original constructor/event tests; balance ledger and fixed-supply invariant after every handler action. |
| State transitions | Approval replaces the previous value; successful delegated spends consume finite allowances; failed calls preserve all balances and allowances (`ERC20.sol`, `approve`, `transferFrom`, `_spendAllowance`). | Approval reduction/revocation, empty-balance/refill tests, failure/retry fuzz tests, and allowance ledger invariant. |
| Round trips | With no fees or conversion logic, sending tokens back restores both balances exactly (`ERC20.sol`, `_update`). | Repeated round-trip fuzz test with intermediate delivery assertions; split-versus-single transfer property. |
| Adversarial use | Neither an unapproved caller nor an over-budget spender can move tokens; valid holders retain the ability to transfer their entire balance. | Original forbidden/admin calls, unauthorized handler calls, over-balance/over-allowance probes, and `afterInvariant` full-balance transfers. |
| Token semantics | Self-transfers preserve balances, zero operations have the documented address checks, and only `uint256.max` is unlimited approval. | Explicit zero/one/full-supply/maximum cases, largest-finite allowance test, direct-versus-delegated delivery with aliased roles. |

These are expected guarantees of the brief and the public ERC-20 behavior, not
speculative vault, AMM, or rounding assumptions. The ledger records requests that
succeeded rather than copying balances or allowances from the token as its oracle.

## Stateful campaign

Four actors can send, receive, approve, replace/revoke approvals, and act as
spenders, including self-transfers and self-approvals. An additional outsider is
never approved. All recipients belong to this closed actor set, so summing their
balances accounts for the entire supply. Zero, the token, the handler, the test
contract, and the outsider must hold no tokens during this campaign.

Ten explicitly targeted handler methods mix valid operations with expected
failures. Boundary approvals deliberately include zero, one base unit, the full
balance, `uint256.max - 1`, and `uint256.max`; delegated probes also reach balance
plus one and allowance plus one. Invalid operations assert their exact custom
errors and leave the model unchanged. Unexpected reverts fail the campaign.
Every owner/spender pair is checked, including untouched pairs.

Inline configuration runs 256 sequences of 128 calls. After each sequence,
`afterInvariant` moves every actor's complete balance and rechecks conservation
and allowances. A deterministic handler test exercises successful nonzero
spending, allowance exhaustion, failed delivery, balance failure, revocation, and
subsequent holder transfers. It makes these paths reproducible independently of
random selection. Stateless fuzz properties run 1,024 cases each and the new
tests constrain inputs with `bound`, without discarded assumptions.

## Reproduction

```sh
forge build
FOUNDRY_FUZZ_SEED=0xe95ae8c984230ad92d4b4007038ba34c6bd6509c589ccf408a78d06cdd29c410 forge test
```

Build artifacts can be confined to scratch by adding
`--out test/scratch/out --cache-path test/scratch/cache` to each command. No test
imports anything from scratch. The suite uses the existing vendored dependencies
and requires no network, RPC, environment changes, or additional installation.

The supplied protected launch checks were reviewed. Their factory, Uniswap pool,
and launch configuration are supplied by the separate verifier and are not in
this repository. Local factory tests establish exact token delivery, not an
execution of those protected integration checks.
