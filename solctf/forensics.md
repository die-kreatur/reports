# sol-ctf: Forensics Challenges

Writeups for all forensics challenges from [solctf.com](https://solctf.com). The platform is down, but challenge descriptions are available on [GitHub](https://github.com/sol-ctf/public-bank/tree/main). No flags are shared.

### Heirloom Archive

The challenge gives you a single text file with a hidden flag. The file turned out to not be a text file at all, but an archive. No flag on the surface, so I unpacked it. Inside was another text file, seemingly full of invalid Unicode characters.

Looking closer, I found readable text among the garbage. It resembled stderr output from a Rust program, mixed with a lot of junk and repeating many times. No flag in sight, but I noticed that many lines were identical, so I filtered for unique ones. That's where this showed up:

```
.equ WEIRD_BYTES_0, 0x466c61677b536869
```

The `0x` prefix gave it away as hex-encoded data. Decoded the bytes and got the flag.

### Toly Praises ETH

The challenge gives you an audio recording of Anatoly Yakovenko apparently praising Ethereum, with a flag hidden inside. Everything you need is already in the challenge description, and it can be solved in just a few minutes.

The description suggests generating a spectrogram, so that's what I did:

```shell
ffmpeg -i toly_praises_eth_praise.wav -lavfi \
  showspectrumpic=s=1920x1080:legend=disabled:scale=log \
  spectrogram.png
```

In the resulting image I noticed a base58-encoded string embedded in the frequency bands. Some characters were hard to make out visually, but keeping the base58 alphabet in mind helped resolve the ambiguity. Decoded it and got the flag.

I won't spoil it, but the flag is a punchline, something along the lines of "I lied, ETH sucks."

### Shadow SBPF

You're given a Solana binary file and asked to find a flag inside. The challenge description sounds intimidating:

```
The program won't run for you on-chain. It will, however, reveal hints to anyone
who examines it closely: disassemble the code, inspect the data sections, and decode
the scrambled fragments. The secret is there, patiently waiting for the right approach.
```

Despite the hints about disassembly, I prefer to try the simplest approach first. The `strings` command-line tool turned out to be enough to find the flag pieces right away. The challenge also drops this hint in the description:

```
PS

Know this CHAD?

https://x.com/deanmlittle
```

This pointed me toward what keywords to look for when combing through the strings output.
