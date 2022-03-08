# Random Linear Combination

> Update: We should just follow traditional Fiat-Shamir, to always commit and generate challenge. Assuming EVM state transition is deterministic is not working for malicious prover.

<!-- toc -->

## Introduction

In circuit, in order to reduce constraints, we try to use random linear combination as a cheap hash function on range-checked bytes for:

1. Fit 32-bytes word (256-bits) in 254-bits field
2. Accumulate arbitrary-length bytes (or say fit arbitrary-length bytes in 254-bits field)

For the first point, it allows us to store an EVM word in a single witness, without worrying about the fact that it doesn't fit in the field. Most time we move these random linear combination word directly from here to there, only when we need to perform arithmetic or bitwise operation we will decompress/decomposite/decode the word into bytes (with range check on each byte) and then do the actual operation.

> We can also store an EVM word in 2 witnesses representing hi-part and lo-part, but it makes us need to move 2 witnesses around for each word. It's not very clear how the random linear combination saves the overall constraints, we might need to explore more opcodes and know the actual benefit.
>
> **han**

For the second point, it allows us to easily do RLP encoding for transaction or merkle (hexary) patricia trie node in fixed amount of witnesses, without worrying about the fact that RLP encoded bytes could have arbitrary and unlimited length (for MPT node it has a max length, but for tx it doesn't). Each accumulated witness will be further decompress/decomposite/decode into serveral bytes and fed to `keccak256` as input.

> It would be really nice if we can further ask `keccak256` to accept a accumulated witness and the amount of bytes it contains as inputs.
>
> **han**

## Concern on randomness

The randomness for random linear combination is important, otherwise the malicious prover could try to find a collision to mint its ether from the thin air.

Here are 2 approaches trying to derive a reasonable randomness to mitigate the risk.

### 1. Randomness from committed polynomials with an extra round

Assuming we could separate all random linear combined witnesses to different polynomials in our constraint system, we can first commit polynomials except those for random linear combined witnesses, and derive the randomness from commitments as public input, and continue the proving process.

### 2. Randomness from all public inputs of circuit

The public inputs of circuit at least contains:

- Transactions raw data (input)
- Old state trie root (input)
- New state trie root (output)

Regardless of the fact that the new state trie root could be a bad one (it should be a bad one, otherwise the attack affect nothing), since the state trie root implies all the bytes it contains, with transaction raw data, if we derive the randomness from all of them, the malicious prover needs to decide what's the new bad state trie root, then find the collisions with input and output. It somehow limits the possible collision pairs because the input and output are also fixed.

## A minimal deterministic system using random linear combination

Suppose a deterministic virtual machine consists of 2 opcodes `PUSH32` and `ADD`, and the VM runs as a pure function `run` as described:

### Pseudo code

```python
def randomness_approach_2(bytecode: list, claimed_output: list) -> int:
    return int.from_bytes(keccak256(bytecode + claimed_output), 'little') % FP

def run(bytecode: list, claimed_output: list):
    """
    run takes bytecode to execute and treat the top of stack as output in the end.
    """

    # Derive randomness
    r = randomness_approach_2(bytecode, claimed_output)

    # Despite an EVM word is 256-bit which is larger then field size, we store it
    # as random linear combination in stack. Top value is in the end of the list.
    stack = []

    program_counter = 0
    while program_counter < len(bytecode):
        opcode = bytecode[program_counter]

        # PUSH32
        if opcode == 0x00:
            # Read next 32 bytes as an EVM word from bytecode
            bytes = bytecode[program_counter+1:program_counter+33]
            # Push random linear combination of the EVM word to stack
            stack.append(random_linear_combine(bytes, r))
            program_counter += 33
        # ADD
        elif opcode == 0x01:
            # Pop 2 random linear combination EVM word from stack
            a, b = stack.pop(), stack.pop()
            # Decompress them into little-endian bytes
            bytes_a, bytes_b = rlc_to_bytes[a], rlc_to_bytes[b]
            # Add them together
            bytes_c = add_bytes(bytes_a, bytes_b)
            # Push result as random linear combination to stack
            stack.append(random_linear_combine(bytes_c, r))
            program_counter += 1
        else:
            raise ValueError("invalid opcode")

    assert rlc_to_bytes[stack.pop()] == claimed_output, "unsatisfied"
```

### [Full runnable code](./random-linear-combinaion/full-runnable-code.md)

All the random linear combination or decompression will be constraint in PLONK constraint system, where the randomness is fed as public input.

It derives the randomness from both input and output (feed them into keccak256), which is the [approach 2](#2-Randomness-from-all-public-inputs-of-circuit). Although it uses raw value in bytes instead of hashed value, but assuming the keacck256 and the merkle (hexary) patricia trie in Ethereum is collision resistent, it should be no big differece between the two cases.

The issue at least reduces to: **Whether a malicious prover can find collisions between stack push and pop, after it decides the input and output**.

