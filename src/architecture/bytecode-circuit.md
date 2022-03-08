# Bytecode Circuit

Bytecode circuit iterates over contract bytecodes to verify each bytecode has valid hash.

It serves as a lookup table for EVM circuit to do random access of any index of bytecode.

# Implementation

- [spec](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/bytecode-proof.md)
    - [python](https://github.com/appliedzkp/zkevm-specs/blob/master/src/zkevm_specs/bytecode.py)
- [circuit](https://github.com/appliedzkp/zkevm-circuits/tree/main/zkevm-circuits/src/bytecode_circuit)
