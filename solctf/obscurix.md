# sol-ctf: Obscurix

This is a writeup for the Obscurix challenge from [solctf.com](https://solctf.com). The challenge is a single file: `obscurix.hex`. The mission is to find a hidden key inside it and build a Solana transaction. No hints about where the key is, what it looks like, or how many layers deep the rabbit hole goes.

Full description is available on [GitHub](https://github.com/sol-ctf/public-bank/tree/main/obscurix).

## Hex to text

The first obvious step was to decode the hex to human-readable text and see what comes out. What I got wasn't readable, but it wasn't random noise either:

```rust
#[rsfwjs(Sffcf, Rspiu, Qzcbs)]
dip sbia DcvFsqcfrsfSffcf {
    #[sffcf("aol vswuvh fsoqvsr")]
    AolVswuvhFsoqvsr,

    #[sffcf("awb vswuvh bch fsoqvsr")]
    AwbVswuvhBchFsoqvsr,

    #[sffcf("gsbr KcfywbuPobySbhfm sffcf")]
    GsbrSffcf(#[tfca] GsbrSffcf<KcfywbuPobySbhfm>),

    #[sffcf("qvobbsz tizz")]
    QvobbszTizz,

    #[sffcf("qvobbsz rwgqcbbsqhsr")]
    QvobbszRwgqcbbsqhsr,
}

dip(qfohs) hmds Fsgizh<H> = ghr::fsgizh::Fsgizh<H, DcvFsqcfrsfSffcf>;
```

The structure is clearly Rust, but the words are scrambled. A couple of things jumped out: `dip sbia` is obviously `pub enum`, and `dip(qfohs) hmds` looks like `pub(crate) type`. I count the shift between `p` and `d`, `u` and `i`, and so on. It's consistent. Offset of 14, so the cipher is **ROT-14**.

After decrypting I had what looked like a modified version of `poh_recorder.rs`, an actual file from the Solana validator codebase. But something was still wrong.

## Digit cipher

With the letter cipher stripped away, weird things were still hiding in the types and values:

```rust
pub const ID: [u2; 2] = [23, 89, 67, 12, 34, 89, 76, 56];
```

```rust
struct PohRecorderMetrics {
    flush_cache_tick_us: u08,
    flush_cache_no_tick_us: u08,
    record_us: u08,
    record_lock_contention_us: u08,
    report_metrics_us: u08,
    send_entry_us: u08,
    tick_lock_contention_us: u08,
    ticks_from_record: u08,
    total_sleep_us: u08,
    last_metric: Instant,
}
```

```rust
if self.last_metric.elapsed().as_millis() > 5444
```

`u2` and `u08` aren't real Rust types. Rust has only `u8`, `u16`, `u32`, `u64`, `u128` for unsigned integers. 5444 ms looked like a weird threshold. I pulled up the original `poh_recorder.rs` and compared:

- `[u2; 2]` should be `[u8; 8]`
- `u08` should be `u64`
- `5444` should be `1000`

The pattern is clean: subtract 4 from every digit and take mod 10. It works every time:
- 2: (2 - 4) mod 10 = 8, also applies to `u2`
- `u08`: (0 - 4) mod 10 = 6 and (8 - 4) mod 10 = 4, so we get `u64`
- 5444 turns into 1000 after applying the same cipher

Thus, the full cipher is:

- **ROT-14** for letters
- **(digit - 4) mod 10** for digits

## Extracting the key

Now that I knew `[u2; 2]` was a deliberate marker, I scanned the whole file for every place it appeared. There were exactly four arrays, each with a comment sitting right above it, plus one suspicious variable that had no business being there:

```rust
/// 5
pub const ID: [u2; 2] = [23, 89, 67, 12, 34, 89, 76, 56];
// 2-0
let bank_hash: [u2; 2] = [5, 90, 12, 35, 89, 06, 56, 78];
/// 0/6
pub const ID: [u2; 2] = [5, 22, 78, 34, 56, 78, 12, 08];
// four
assert_eq!(bank.hash(), &[57, 23, 77, 54, 89, 56, 89, 77]);

let some_weird_url = "https://gist.github.com/Nagaprasadvr/3f639a47b8073e526f738745e436c97e";
```

Four arrays, 8 bytes each, that's 32 bytes. Exactly the size of a Solana public key. The comments encode the assembly order. The byte values also need decoding. The giveaway is `06` and `08`: you don't write raw byte literals with a leading zero unless the original first digit was 6, which encodes to 0. I applied the digit cipher to every byte value, assembled the segments in the right order, and got the 32-byte key.

## Deciphering the Gist URL

The GitHub Gist link returned a 404. Easy to dismiss, but one of the challenge hints says: 
> Understand the Cipher and apply it to literally everything.

Literally everything. What if the link is also ciphered? A gist ID is a hex string, so only digits 0-9 and letters a-f are allowed. **ROT-14** had already been applied to the entire file including the URL, so I assumed only the digit cipher should be applied here. I subtracted 4 from every digit in the gist ID, took mod 10, left the letters alone, and the URL resolved to a real Gist with an `idl.json` inside:

```json
{
  "address": "uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m",
  "metadata": {
    "name": "obscurix",
    "version": "0.1.0",
    "spec": "0.1.0",
    "description": "Created with Anchor"
  },
  "instructions": [
    {
      "name": "pawn",
      "discriminator": [218, 132, 24, 244, 48, 228, 134, 212],
      "accounts": [],
      "args": [
        {
          "name": "key",
          "type": { "array": ["u8", 32] }
        }
      ]
    }
  ],
  "errors": [
    {
      "code": 6000,
      "name": "FailedToPwn",
      "msg": "Invalid key, failed to pwn challenge"
    }
  ]
}
```

## Building the transaction

The IDL had everything I needed:

- **Program:** `uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m`
- **Instruction:** `pawn`
- **Discriminator:** `[218, 132, 24, 244, 48, 228, 134, 212]`
- **Argument:** the 32-byte key I assembled
- **Required accounts:** none

I built a transaction calling the `pawn` instruction with the key, serialized it, base64-encoded the result, and that was the flag.
