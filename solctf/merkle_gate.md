# sol-ctf: Merkle Gate

This is a writeup for the Merkle Gate challenge from [solctf.com](https://solctf.com). The challenge provides a program binary, an IDL, and a Merkle root. The goal is to bypass Merkle root checks by calling a given instruction with correct parameters.

Full description is available on [GitHub](https://github.com/sol-ctf/public-bank/tree/main/merkle-gate).

## IDL analysis
Here is the IDL file:
```json
{
    "address": "uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m",
    "metadata": {
        "name": "merkle_gate",
        "version": "0.1.0",
        "spec": "0.1.0",
        "description": "Created with Anchor"
    },
    "instructions": [
        {
            "name": "merkle_gate",
            "discriminator": [
                143,
                149,
                6,
                175,
                8,
                80,
                200,
                62
            ],
            "accounts": [
                {
                    "name": "payer",
                    "writable": true,
                    "signer": true
                },
                {
                    "name": "state",
                    "writable": true,
                    "pda": {
                        "seeds": [
                            {
                                "kind": "const",
                                "value": [
                                    109,
                                    101,
                                    114,
                                    107,
                                    108,
                                    101
                                ]
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
                    "name": "leaf",
                    "type": {
                        "array": [
                            "u8",
                            32
                        ]
                    }
                },
                {
                    "name": "proof",
                    "type": {
                        "vec": {
                            "array": [
                                "u8",
                                32
                            ]
                        }
                    }
                },
                {
                    "name": "challenge_id",
                    "type": {
                        "array": [
                            "u8",
                            32
                        ]
                    }
                }
            ]
        }
    ],
    "accounts": [
        {
            "name": "MerkleState",
            "discriminator": [
                206,
                169,
                210,
                196,
                54,
                110,
                7,
                217
            ]
        }
    ],
    "types": [
        {
            "name": "MerkleState",
            "type": {
                "kind": "struct",
                "fields": [
                    {
                        "name": "pwned",
                        "type": "bool"
                    },
                    {
                        "name": "challenge_id",
                        "type": {
                            "array": [
                                "u8",
                                32
                            ]
                        }
                    }
                ]
            }
        }
    ]
}
```

Only one instruction available:

1. `merkle_gate` - verifies a Merkle proof and sets `pwned` to `true`, requires:
    - `payer` (signer, writable)
    - `state` PDA with seed `"merkle"` (writable)
    - system program
    - arguments: 
        - `leaf` ([u8; 32]),
        - `proof` (Vec<[u8; 32]>),
        - `challenge_id` ([u8; 32])

## The exploit
When I started solving the challenge I was not familiar with the Merkle proof algorithm. As I understood from what I read, in the real world we have to provide a leaf to verify if it's a part of the tree. To do that we need a proof, which is a sequence of sibling hashes along the path from the leaf to the root. The proof is provided by an external resource, which stores the full tree. The verifier then takes the leaf, hashes it together with each proof element step by step, and checks whether the resulting root matches the known one.

I needed to know the proof to call the instruction, but there are no other instructions in the IDL file. Hints say:
> If order doesn’t matter, very short “proofs” might get… persuasive.
> The IDL shows you everything you need to build the instruction bytes.

I assumed that if I passed an empty proof, the program would just check that my leaf equals the given root and all the checks would be skipped, so I could just pass the known root as the leaf. I didn't understand what `challenge_id` parameter is, so I decided to try to pass a default value. It worked out:

```
Logs: [
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m invoke [1]",
    "Program log: Instruction: MerkleGate",
    "Program 11111111111111111111111111111111 invoke [2]",
    "Program 11111111111111111111111111111111 success",
    "Program log: 🎉 Merkle gate bypassed! Challenge pwned!",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m consumed 8990 of 200000 compute units",
    "Program uWGrWGNk4enkjkboj6ErEW8FKDQBaFCUGqtpcw7Ea5m success",
]
```