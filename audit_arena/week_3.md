# Security Audit: Zenon Protocol
07.04.26 - 12.04.26

## Acknowledgements
This report was written by [die-kreatur](https://github.com/die-kreatur). It was published before Frank Castle's official judging and represents an independent analysis.

This report may be reproduced or referenced with attribution to the original author.

## Overview
_Framework: Anchor 0.30.1_

The audited protocol is Zenon, which is a token launchpad.

This audit was performed as part of [Solana Audit Arena - Week 3](https://github.com/Frankcastleauditor/Solana-Audit-Arena), a weekly security competition organized by Frank Castle.

## Scope
All code in `programs/zenon`

## Architecture Summary

Zenon is a pump.fun-style token launchpad. Anyone can create a token, which is immediately tradeable on a constant-product bonding curve. Once cumulative token sales reach the market's `escape_amount` threshold, the curve is marked completed and the admin migrates the accumulated SOL and remaining tokens to an external DEX.

Global parameters (fee rates, graduation threshold, treasury addresses) are stored in a versioned `Market` PDA. Each token has its own `BondingCurve` PDA that tracks virtual and real reserves and holds SOL directly as lamports. Tokens are held in an ATA owned by the `BondingCurve` PDA. The protocol collects a SOL trading fee on every swap and an escape fee on graduation; a flat token amount (`tokens_fee_amount`) is also reserved at graduation for the protocol.

## Design concerns

`Market` is passed as an account into every instruction and read at execution time, meaning any change via `update_market` takes effect immediately across all existing bonding curves. Parameters like `trading_fee_bps` and `escape_amount` are global. A single update affects every token ever launched against that market, regardless of when it was created or what its current state is.

This creates two problems. First, it is a centralisation risk: a single admin action can silently alter the economics of an unbounded number of active curves. Second, it is operationally unsound: since `init_token` can be called for any number of mints, the admin cannot reasonably predict how a parameter change will interact with each individual curve at the time the change is made.

A better design would be to snapshot the relevant market parameters into the `BondingCurve` account at `init_token` time, at minimum `trading_fee_bps` and `escape_amount`. Changes to `Market` would then only affect curves created after the update, leaving existing curves with the parameters they were launched under. This significantly reduces both centralisation risk and the blast radius of a misconfiguration.

## Findings Summary
| ID | Severity | Title |
|----|---------|-------|
| F-01 | High | `initialize_market` has no access control |
| F-02 | Medium | `escape_amount` validation in `save_market` always passes |
| F-03 | Medium | Stack overflow in `InitializeAndMint` prevents all token creation |
| F-04 | Medium | Slippage check in `sell_tokens` is applied to gross SOL amount before fee deduction |
| F-05 | Low | Unvalidated `sol_offset` in `init_token` permanently breaks the bonding curve |
| F-06 | Low | `tokens_fee_cooldown_timestamp` set by token creator can permanently freeze fee withdrawal |

## Detailed Findings

### [F-01] `initialize_market` has no access control

A `Market` is the global configuration account that controls fee rates, treasury destinations, and the graduation threshold for all bonding curves launched against it. Whoever holds `market.authority` can update all of these parameters at any time via `update_market`.

`initialize_market` requires only a `payer` signer with no restriction on who can call it. Any account can create a `Market` PDA for any unused `version`, set themselves as `authority`, and point all treasury fields to addresses they control.

This make possible different malicious actions. For instance, an attacker creates a market with their own authority, waits for users to launch tokens against it, then calls `update_market` to set `trading_fee_bps = 10000`. Every subsequent buy and sell on those tokens transfers 100% of the SOL input as a trading fee to the attacker's treasury. Users receive tokens but lose all the SOL they spent. There is no on-chain signal distinguishing a legitimate market from a malicious one.

#### Recommended Fix

Restrict `initialize_market` to a known protocol admin, either via a hardcoded key or a separate admin PDA:

```rust
#[account(mut, constraint = payer.key() == PROTOCOL_ADMIN)]
pub payer: Signer<'info>,
```

### [F-02] `escape_amount` validation in `save_market` always passes on `initialize_market`

`escape_amount` is the number of tokens that must be sold before a bonding curve completes. It must not exceed `initial_mint` (the total token supply) otherwise the graduation threshold can never be reached.

`save_market` is a shared helper called by both `initialize_market` and `update_market`. It writes the new `initial_mint` first, then checks whether the stored `escape_amount` exceeds it, and only then writes the new `escape_amount`. The check therefore reads the old on-chain value, not the incoming one. On a freshly created market all fields are zero-initialised, so the check compares `0 > initial_mint`, which is always false. Hence, the incoming `escape_amount` is never validated and any value is accepted.

With `escape_amount > initial_mint`, the completion condition in `buy_tokens` can never be satisfied since the total sellable supply is bounded by `initial_mint`. The bonding curve never completes, `process_completed_curve` can never be called, and all accumulated SOL is permanently locked in the `BondingCurve` PDA.

#### Recommended Fix

Validate the incoming value, not the stale stored one:

```rust
if market_data.escape_amount > market_data.initial_mint {
    return Err(TokenError::EscapeAmountTooHigh.into());
}

market.initial_mint = market_data.initial_mint;
market.escape_amount = market_data.escape_amount;
```

### [F-03] Stack overflow in `InitializeAndMint` prevents all token creation

Solana's BPF VM enforces a hard 4096-byte limit per stack frame. When an Anchor accounts struct is too large, the generated `try_accounts` deserialisation exceeds this limit and the transaction fails at runtime.

`InitializeAndMint` in `init_token.rs` holds all account types directly on the stack without boxing, including `Mint`, `BondingCurve`, `Market`, `TokenAccount`, and the Metaplex `Metadata` account. Together they exceed the limit by 16 bytes. The compiler confirms this with a stack overflow warning at build time. Thus, every call to `init_token` fails, meaning no token can ever be created and the entire protocol is non-functional.

#### Recommended Fix

Wrap the large account types in `Box` to allocate them on the heap instead of the stack:

```rust
pub bonding_curve: Box<Account<'info, BondingCurve>>,
pub market: Box<Account<'info, Market>>,
pub bonding_curve_ata: Box<Account<'info, TokenAccount>>,
```

### [F-04] Slippage check in `sell_tokens` is applied to gross SOL amount before fee deduction

Slippage protection lets a seller specify a minimum acceptable SOL output (`min_sol_amount`) to guard against unfavourable price movement between transaction submission and execution. For this guarantee to hold, the check must be applied to what the seller actually receives.

In `sell_tokens`, the swap output is validated against `min_sol_amount` before the trading fee is calculated. The fee is then charged as a separate transfer from the seller's wallet on top of the swap. This means the slippage check passes on the gross amount, while the seller's net receipt is `gross - trading_fee`. A seller who sets `min_sol_amount = X` to guarantee receiving at least `X` lamports will in fact receive `X - trading_fee`. At the maximum allowed fee of 10000 bps the seller receives nothing regardless of their stated minimum.

#### Recommended Fix

Compute the fee before the slippage check and validate the net amount:

```rust
let trading_fee = calculate_fee(sol_amount.into(), trading_fee_bps.into(), 10000).unwrap() as u64;
let net_sol_amount = sol_amount.checked_sub(trading_fee).unwrap();
if net_sol_amount < min_sol_amount {
    return Err(TokenError::MinSolAmountNotMet.into());
}
```

### [F-05] Unvalidated `sol_offset` in `init_token` permanently breaks the bonding curve

When a token is launched, the caller supplies `sol_offset` and `token_offset` to seed the bonding curve's virtual reserves. These offsets define the initial price and depth of the AMM. Neither value is validated before being written to the `BondingCurve` account.

If `sol_offset` is set to zero, `virtual_sol_reserves` is initialised to zero. The constant-product swap formula used in `buy_tokens` and `sell_tokens` computes with these reserves in the denominator, so a zero value causes a panic and the transaction fails. Since the `BondingCurve` account is immutable after creation, there is no way to correct the reserves. The bonding curve is permanently non-functional, and the rent paid for the `BondingCurve` PDA and its ATA is irrecoverable.

#### Recommended Fix

Reject zero values for `sol_offset` and `token_offset` in `init_token`:

```rust
require!(params.sol_offset > 0, TokenError::InvalidOffset);
require!(params.token_offset > 0, TokenError::InvalidOffset);
```

### [F-06] `tokens_fee_cooldown_timestamp` set by token creator can permanently freeze fee withdrawal

When launching a token, the caller supplies a `tokens_fee_cooldown_timestamp` that is written directly to the `BondingCurve` account without validation. This timestamp gates `withdraw_tokens_fee`: the instruction checks that the current clock is past the timestamp before allowing the admin to withdraw the reserved token fee allocation.

Since any caller can set this value to an arbitrarily large timestamp such as `i64::MAX`, `withdraw_tokens_fee` will never pass the cooldown check for that curve. The token fee allocation reserved at graduation is permanently frozen and can never be withdrawn by the admin.

#### Recommended Fix

Require the caller to pass a cooldown duration in seconds (`u64`) instead of an absolute timestamp. The absolute timestamp is then computed inside `init_token`, preventing the token creator from setting an arbitrary value and additional validations are not required in this case. In `init_token`:

```rust
ctx.accounts.bonding_curve.tokens_fee_cooldown_timestamp = Clock::get()?.unix_timestamp + params.cooldown_period;
```

Additionally, `cooldown_period` itself should be bounded by a protocol-defined maximum to prevent unreasonably long cooldowns.
