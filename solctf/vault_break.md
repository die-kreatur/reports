# sol-ctf: Vault Break

This is a writeup for the Vault Break challenge from [solctf.com](https://solctf.com). The challenge is a Solana program binary and an `idl.json` file. The goal is to break the vault with two transactions.

Full description is available on [GitHub](https://github.com/sol-ctf/public-bank/tree/main).

## IDL analysis

Here is the IDL:

```json
{
    "address": "uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m",
    "metadata": {
        "name": "vault_break",
        "version": "0.1.0",
        "spec": "0.1.0",
        "description": "Created with Anchor"
    },
    "instructions": [
        {
            "name": "vault_create",
            "discriminator": [109, 191, 172, 125, 83, 225, 56, 122],
            "accounts": [
                {
                    "name": "admin",
                    "writable": true,
                    "signer": true
                },
                {
                    "name": "vault",
                    "writable": true,
                    "pda": {
                        "seeds": [
                            {
                                "kind": "const",
                                "value": [118, 97, 117, 108, 116]
                            }
                        ]
                    }
                },
                {
                    "name": "system_program",
                    "address": "11111111111111111111111111111111"
                }
            ],
            "args": []
        },
        {
            "name": "vault_open",
            "discriminator": [88, 119, 117, 99, 145, 1, 225, 154],
            "accounts": [
                {
                    "name": "authority",
                    "writable": true,
                    "signer": true
                },
                {
                    "name": "vault",
                    "writable": true,
                    "pda": {
                        "seeds": [
                            {
                                "kind": "const",
                                "value": [118, 97, 117, 108, 116]
                            }
                        ]
                    }
                }
            ],
            "args": []
        },
        {
            "name": "vault_reset",
            "discriminator": [162, 127, 159, 174, 179, 116, 127, 132],
            "accounts": [
                {
                    "name": "resetter",
                    "writable": true,
                    "signer": true
                },
                {
                    "name": "vault",
                    "writable": true,
                    "pda": {
                        "seeds": [
                            {
                                "kind": "const",
                                "value": [118, 97, 117, 108, 116]
                            }
                        ]
                    }
                }
            ],
            "args": [
                {
                    "name": "new_admin",
                    "type": "pubkey"
                }
            ]
        }
    ],
    "accounts": [
        {
            "name": "Vault",
            "discriminator": [211, 8, 232, 43, 2, 152, 117, 119]
        }
    ],
    "errors": [
        {
            "code": 6000,
            "name": "VaultLocked",
            "msg": "Vault is locked"
        },
        {
            "code": 6001,
            "name": "Unauthorized",
            "msg": "Unauthorized: Only the vault admin can open the vault"
        }
    ],
    "types": [
        {
            "name": "Vault",
            "type": {
                "kind": "struct",
                "fields": [
                    {
                        "name": "admin",
                        "type": "pubkey"
                    },
                    {
                        "name": "bump",
                        "type": "u8"
                    },
                    {
                        "name": "flag_captured",
                        "type": "bool"
                    },
                    {
                        "name": "locked",
                        "type": "bool"
                    }
                ]
            }
        }
    ]
}
```

Based on the file I figured out what instructions the program has:

1. `vault_create` - creates the vault account, requires:
    - `admin` (signer)
    - `vault` PDA with seed `"vault"`
    - system program
2. `vault_open` - opens the vault, requires:
    - `authority` (signer)
    - `vault` PDA with seed `"vault"`
3. `vault_reset` - changes the authority, requires:
    - `resetter` (signer)
    - `vault` PDA with seed `"vault"`
    - argument: `new_admin` (pubkey)

## The exploit

Since the challenge says I have to submit two transactions, the most obvious exploit is to reset the authority and then open the vault. I looked at `vault_reset` more closely. Normally only the current authority should be allowed to set a new authority. Otherwise anyone can pass their public key, sign the transaction and become a new authority. There's no such check visible in the IDL. It might be enforced in the instruction code rather than with Anchor constraints, but I decided to test my guess first.

I loaded the program binary into litesvm, set myself as the new admin via `vault_reset` and called `vault_open`. It worked:

```
Logs: [
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m invoke [1]",
    "Program log: Instruction: VaultReset",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m consumed 3083 of 200000 compute units",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m success",
]
Logs: [
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m invoke [1]",
    "Program log: Instruction: VaultOpen",
    "Program log: 🎉 FLAG CAPTURED! Well done!",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m consumed 3200 of 200000 compute units",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m success",
]
```
