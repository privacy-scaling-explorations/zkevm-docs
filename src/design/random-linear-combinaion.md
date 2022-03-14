# Random Linear Combination

<!-- toc -->

## Introduction

In the circuit, in order to reduce the number of constraints, we use the random linear combination as a cheap hash function on range-checked bytes for two scenarios:

1. Encode 32-bytes word (256-bits) in 254-bits field
2. Accumulate (or fit/encode) arbitrary-length bytes in 254-bits field

On the first scenario, it allows us to store an EVM word in a single witness value, without worrying about the fact that a word doesn't fit in the field. Most of the time we move these random linear combination word directly from here to there, and only when we need to perform arithmetic or bitwise operation we will decode the word into bytes (with range check on each byte) to do the actual operation.

Alternatively we could also store an EVM word in 2 witnes values, representing hi-part and lo-part; but it makes us need to move 2 witnes valuess around for each word. Note that the constraints optimizations obtained by using the random linear combination have not been properly analized yet. 

On the second scenario, it allows us to easily do RLP encoding for a transaction or a merkle (hexary) patricia trie node in a fixed amount of witnesses, without worrying about the fact that RLP encoded bytes could have arbitrary and unlimited length (for MPT node it has a max length, but for tx it doesn't). Each accumulated witness will be further decompress/decomposite/decode into serveral bytes and fed to `keccak256` as input.

> It would be really nice if we can further ask `keccak256` to accept a accumulated witness and the amount of bytes it contains as inputs.
>
> **han**

## Concern on randomness

The way randomness is derived for random linear combination is important: if done improperly, a malicious prover could find a collision to make a seemigly incorrect witness pass the verification (allowing minting Ether from thin air).

Here are 2 approaches trying to derive a reasonable randomness to mitigate the risk.

### 1. Randomness from committed polynomials with an extra round

Assuming we could separate all random linear combined witnesses to different polynomials in our constraint system, we can:
1. Commit polynomials except those for random linear combined witnesses
2. Derive the randomness from commitments as public input
3. Continue the proving process.

### 2. Randomness from all public inputs of circuit

> Update: We should just follow traditional Fiat-Shamir (approach 1), to always commit and generate challenge. Assuming EVM state transition is deterministic is not working for malicious prover.

The public inputs of circuit at least contains:

- Transactions raw data (input)
- Old state trie root (input)
- New state trie root (output)

Regardless of the fact that the new state trie root could be an incorrect one (in the case of an attack), since the state trie root implies all the bytes it contains (including transaction raw data), if we derive the randomness from all of them, the malicious prover needs to first decide what's the new (incorrect) state trie root and then find the collisions with input and output.  This somehow limits the possible collision pairs because the input and output are also fixed.

## A minimal deterministic system using random linear combination

The following example shows how the random linear combination is used to compare equality of words using a single witness value.

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

The randomness is derived from both input and output (fed to keccak256), which corresponds to [approach 2](#2-Randomness-from-all-public-inputs-of-circuit). Although it uses raw value in bytes instead of hashed value, but assuming the keacck256 and the merkle (hexary) patricia trie in Ethereum are collision resistant, it should be no big differece between the two cases.

The issue at least reduces to: **Whether a malicious prover can find collisions between stack push and pop, after it decides the input and output**.

