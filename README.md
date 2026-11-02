# Conditionals (COND)

An immutable, fixed-supply ERC-20 token. The only production contract is
[`src/Conditionals.sol`](src/Conditionals.sol), Solidity identifier `Conditionals`.

## Token parameters

| Parameter | Value |
| --- | --- |
| Name | `Conditionals` |
| Symbol | `COND` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` COND |
| Base-unit supply | `1000000000000000000000000000` (`10^27`) |
| Named constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Administrative roles | None |

Construction calls `_mint` exactly once for the full supply and emits the standard
`Transfer` event from the zero address. There is no external mint, burn, initialization,
ownership, pause, blacklist, seizure, fee, or upgrade function. Total supply stays fixed.

## Assumptions and behavior

The brief specifies no custom transfer conditions despite the token's name. Transfers
therefore use the unmodified OpenZeppelin Contracts v5.0.2 ERC-20 implementation;
there are no taxes, transfer restrictions beyond standard address/balance/allowance
checks, rebases, vesting, or special privileges for the deployer.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
OpenZeppelin's ERC-6093 custom errors on failure. Transfers deliver the exact requested
amount. Zero-value transfers to nonzero addresses succeed and emit `Transfer` events,
as required by [ERC-20](https://eips.ethereum.org/EIPS/eip-20). Transfers to the zero
address and approvals to the zero spender revert. Self-transfers are supported but
still require sufficient balance. ERC-20 transfers do not invoke recipient callbacks.

`approve` replaces the previous allowance. Finite allowances decrease on successful
`transferFrom`; `type(uint256).max` represents an unlimited allowance and does not
decrease. A failed transfer rolls back any attempted allowance change. `transferFrom`
requires allowance even when the caller is the holder. `approve` emits `Approval`;
this OpenZeppelin version does not emit it when spending an allowance, so indexers
must also account for delegated transfers or read `allowance` directly. See the
[pinned implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC20/ERC20.sol).

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xe95ae8c984230ad92d4b4007038ba34c6bd6509c589ccf408a78d06cdd29c410 forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, targets Cancun, enables the optimizer with
200 runs, and sets `bytecode_hash = "none"`. Fuzz tests use 1,024 cases each.
Stateful invariants use 128 sequences of up to 64 actions per invariant.
No seed overrides the supplied runner seed. All tests run locally without a fork,
RPC, environment reads, environment mutations, FFI, or filesystem cheatcodes.

All required library sources and licenses are ordinary files under `lib/`, with
versions, upstream URLs, and archive hashes recorded in
[`lib/DEPENDENCIES.md`](lib/DEPENDENCIES.md). No submodules or dependency installation
are required. An offline verifier only needs Foundry and the pinned compiler installed.

The tests cover constructor metadata, the single mint event, CREATE2 factory receipt,
exact distribution and bidirectional transfers, transfer and approval events, full
supply and zero-value transfers, self-transfers, contract recipients, finite and
unlimited approvals, replacement/revocation, isolation between owners/spenders,
failure rollback, invalid addresses, insufficient balances/allowances, and rejected
privileged calls. Fuzz tests vary amounts, recipients, and allowance boundaries.
Stateful tests compare balances and allowances against an independent ledger across
successful and rejected operations and assert conservation of the entire supply.

## Deployment

Deploy the creation bytecode for `src/Conditionals.sol:Conditionals`, with no appended
constructor arguments and no ETH. The Foundry artifact is
`out/Conditionals.sol/Conditionals.json`. There are no linked libraries or initialization
calls, and the constructor makes no external calls. Do not deploy through a proxy.

The recipient is the address executing CREATE/CREATE2, not `tx.origin`. A direct
deployment gives the supply to the deploying account; a factory deployment gives it
entirely to the factory. A factory must be capable of distributing its token balance.
The supplied launch process handles deployment and distribution on Ethereum
(chain ID 1); no signer, wallet, owner address, or external contract address is needed
by this token's constructor.

For this assignment's launch, the factory handles the stated 10% swarm distribution,
80% pool allocation, and 10% remainder. Those operations, pool setup, and the separate
launch manifest belong to the launch process. They are not hardcoded in the token.
The repository's factory test models exact token movements; it does not simulate
Uniswap pricing, liquidity accounting, or swaps. The pinned protected integration
suite performs those checks in the launch verification environment.

Only `Conditionals` under `src/` is a deployment artifact. The factory, recipient,
and invariant handler under `test/` are local test scaffolding.

## After launch

No owner settings, external service configuration, keepers, or maintenance transactions
are required. The launch operator is responsible for checking the deployed bytecode,
verifying the source on the explorer, confirming metadata and total supply, and
completing the factory's distribution. At construction the full supply belongs to the
factory; once its launch transaction distributes tokens, balances reflect that distribution.

Holders control transfers and spending approvals. Approvals grant the selected spender
access up to the allowance; limit approvals to intended amounts and revoke unused ones.
When replacing a nonzero allowance, clients should first revoke it and confirm that
transaction to mitigate the standard ERC-20 allowance replacement race. Existing
allowances may still be spent before a revocation confirms.

There is no recovery authority. Tokens sent to an incorrect address or an incompatible
contract, including this token contract itself, cannot be rescued by an administrator.
Ordinary ETH payments revert; forcibly credited ETH and accidentally sent assets have
no recovery method.

## Review scope

The security review for this implementation checks the public ABI, constructor-only
minting, exact units, authorization through allowances, address validation, atomic
rollback, fixed supply, and the absence of external calls or upgrade powers. There
are no oracle, randomness, signature, liquidity, or external custody mechanisms in
the token to configure or secure. Foundry unit, fuzz, and invariant tests are the
local automated checks; Slither and Mythril were not run. This implementation and
its tests are not an independent audit; the launch's separate review and integration
verification remain the launch operator's responsibility. No transactions were broadcast.
