# sol-ctf: Solshark

This is a writeup for the Solshark challenge from [solctf.com](https://solctf.com). The challenge is a network dump with Solana transaction data, with a flag buried in the noise. The file is a transactions log with many very similar requests to the local RPC node and responses from it. The description says there's a transaction storing a treasure. The challenge was tagged as "network," but I didn't bother with Wireshark. It might be more convenient for sorting packets by length and seeking patterns, but `strings` and `grep` were enough. I stuck to command-line tools throughout.

Full description is available on [GitHub](https://github.com/sol-ctf/public-bank/tree/main/sol-shark).

## Decoys

My first instinct was to search for "Flag" directly in the file. The challenge authors anticipated that:

```
{"jsonrpc":"2.0","method":"logsNotification","params":{"result":{"context":{"slot":655},"value":{"signature":"4BzWg5r4UFQs2haMmUJib2rhtUoArEpXnid992JpTSojrWtT2XGNJU2f9qpPWMk62G5qN3JqBUqi5FNLkQMgaf6u","err":null,"logs":["Program MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr invoke [1]","Program log: Memo (len 16): \"Flag{OoPs_wRoNg}\"","Program MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr consumed 7200 of 200000 compute units","Program MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr success"]}},"subscription":3}}
```

This pattern repeats across many logs, all fake flags from the Memo program designed to throw you off.

## Finding the real flag

The real lead came from searching for `transaction` in the file. This turned up 14 RPC calls of "sendTransaction" method, each carrying a base64-encoded transaction payload. Here's an example:

```
{"id":8,"jsonrpc":"2.0","method":"sendTransaction","params":["AYie4yNGrVFCy9IK21APsP1GAQRx+cnPqbnek1sfZZiX0jX121v0RFCOEZR9BOAJHNoeJt1UWYFjFQMdG5lk0Q4BAAECb2j7jZWIJhlbTCF3GzEvXfrUF4SG5iM+dZcQsBwk55MFSlNamSkhBk0k6HFg2jh8fDW13bySu4HkH6hAQQVEjccKNFkIQjxAHni0Z8XXUaZgmW+ThKKUwm3CkZ0QNzbqAQEABzhxVHJ2OWY=",{"encoding":"base64","maxRetries":null,"minContextSlot":null,"preflightCommitment":"confirmed","skipPreflight":false}]}
```

Every one of these transactions was sent to the [Memo program](https://spl.solana.com/memo), a simple on-chain program for attaching arbitrary text to transactions. I decoded the base64 payload using [an online tool](https://naiba-archived.github.io/solana-transaction-decoder/) and got the raw instruction data:

```
43673957644b4e
```

This looked like hex-encoded bytes. Decoded it into readable text:

```
Cg9WdKN
```

This looked like base58. One more round of decoding:

```
g{Fla
```

A flag fragment! Instruction data are the last bytes of any Solana transaction with a single instruction. The entire log was noisy data, which usually means there's something unique hidden in the garbage. I looked for unique endings of transaction payloads and narrowed it down to six unique transactions in total. Decoded the remaining five the same way and reassembled the flag.
