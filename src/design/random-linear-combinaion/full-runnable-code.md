# Random Linear Combination full runnable code

```python
from Crypto.Hash import keccak
from Crypto.Random.random import randrange


def keccak256(data: list) -> list:
    return list(keccak.new(digest_bits=256).update(bytes(data)).digest())


# BN254 scalar field size.
FP = 21888242871839275222246405745257275088548364400416034343698204186575808495617


def fp_add(a: int, b: int) -> int: return (a + b) % FP
def fp_mul(a: int, b: int) -> int: return (a * b) % FP


# rlc_to_bytes records the original bytes of a random linear combination.
# In circuit we ask prover the provide bytes and verify all bytes are in range
# and the random linear combination matches.
rlc_to_bytes = dict()


def random_linear_combine(bytes: list, r: int) -> int:
    """
    random_linear_combine returns bytes[0] + r*bytes[1] + ... + (r**31)*bytes[31].
    """

    rlc = 0
    for byte in reversed(bytes):
        assert 0 <= byte < 256
        rlc = fp_add(fp_mul(rlc, r), byte)

    rlc_to_bytes[rlc] = bytes

    return rlc


def add_bytes(lhs: list, rhs: list) -> list:
    """
    add_bytes adds 2 little-endian bytes value modulus 2**256 and returns result
    as bytes also in little-endian.
    """

    result = (
        int.from_bytes(lhs, 'little') +
        int.from_bytes(rhs, 'little')
    ) % 2**256

    return list(result.to_bytes(32, 'little'))


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


def test_run():
    a, b = randrange(0, 2**256), randrange(0, 2**256)
    c = (a + b) % 2**256
    run(
        bytecode=[
            0x00, *a.to_bytes(32, 'little'),  # PUSH32 a
            0x00, *b.to_bytes(32, 'little'),  # PUSH32 b
            0x01                              # ADD
        ],
        claimed_output=list(c.to_bytes(32, 'little')),
    )


test_run()
```


