# sol-ctf: American Bank

This is a writeup for the American Bank challenge from [solctf.com](https://solctf.com). Very similar to Vault Break: a program binary and an `idl.json`. The goal is to steal money from the bank in one transaction, but the records must stay unchanged and the institution must stay standing. The challenge says the manager's identity is public knowledge, so the public key is known.

Full description is available on [GitHub](https://github.com/sol-ctf/public-bank/tree/main/american-bank).

## IDL analysis

Here is the IDL file:
```json
{
  "address": "uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m",
  "metadata": {
    "name": "american_bank",
    "version": "0.1.0",
    "spec": "0.1.0",
    "description": "Created with Anchor"
  },
  "instructions": [
    {
      "name": "drain_liquid_capital",
      "discriminator": [157, 155, 217, 32, 86, 116, 224, 73],
      "accounts": [
        {
          "name": "bank",
          "writable": true,
          "pda": {
            "seeds": [
              {
                "kind": "const",
                "value": [98, 97, 110, 107]
              }
            ]
          }
        },
        {
          "name": "manager",
          "relations": [
            "bank"
          ]
        },
        {
          "name": "to",
          "writable": true
        }
      ],
      "args": []
    },
    {
      "name": "setup_bank",
      "discriminator": [164, 194, 172, 169, 29, 14, 14, 22],
      "accounts": [
        {
          "name": "manager",
          "writable": true,
          "signer": true
        },
        {
          "name": "bank",
          "writable": true,
          "pda": {
            "seeds": [
              {
                "kind": "const",
                "value": [98, 97, 110, 107]
              }
            ]
          }
        },
        {
          "name": "system_program",
          "address": "11111111111111111111111111111111"
        }
      ],
      "args": [
        {
          "name": "amount",
          "type": "u64"
        }
      ]
    }
  ],
  "accounts": [
    {
      "name": "Bank",
      "discriminator": [142, 49, 166, 242, 50, 66, 97, 188]
    }
  ],
  "errors": [
    {
      "code": 6000,
      "name": "YouAreNotTheManager",
      "msg": "You are dead, the bells rang!"
    }
  ],
  "types": [
    {
      "name": "Bank",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "manager",
            "type": "pubkey"
          },
          {
            "name": "book_balance",
            "type": "u64"
          },
          {
            "name": "bump",
            "type": "u8"
          }
        ]
      }
    }
  ]
}
```

Based on the file I figured out what instructions the program has:

1. `drain_liquid_capital` - drains the bank, requires:
    - `bank` PDA with seed `"bank"` (writable)
    - `manager` (must match the bank account's manager)
    - `to` - destination account (writable)
2. `setup_bank` - initializes the bank, requires:
    - `manager` (signer)
    - `bank` PDA with seed `"bank"`
    - system program
    - argument: `amount` (u64)

## The exploit

The bank account is a PDA, so only the program can modify it. The only way to steal money is through `drain_liquid_capital`. I looked at who can call it. The manager account has a `relations` constraint tying it to the bank, but there's no signer requirement. Anyone can pass the manager's public key as an argument and drain the account.

## A design issue

I ran the exploit locally and my account received all the lamports from the bank. But I noticed something off. The bank's `book_balance` is not dependent on the actual lamport balance. The bank account holds a fixed storage deposit plus the passed amount. When `drain_liquid_capital` is invoked, all lamports are transferred, bringing the account to zero. Accounts that reach zero lamports are removed from the ledger, so the institution can't stay standing after the drain. I think the challenge authors should have designed the instruction to transfer only the `book_balance` amount, leaving a few lamports to keep the account alive.

Program log as proof that the instruction was called successfully:

```
logs: [
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m invoke [1]",
    "Program log: Instruction: DrainLiquidCapital",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m consumed 3458 of 200000 compute units",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m success",
]
```
