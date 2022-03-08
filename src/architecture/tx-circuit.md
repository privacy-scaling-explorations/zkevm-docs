# Tx Circuit

Tx circuit iterates over transactions included in proof to verify each transaction has valid signature. It also verifies the built transaction merkle patricia trie has same root hash as public input.

Main part of Tx circuit will be instance columns whose evaluation values are built by verifier directly. See the [issue](https://github.com/appliedzkp/zkevm-circuits/issues/122) for more details.

To verify if transaction has valid signature, it hashes the RLP encoding of transaction and recover the address of signer with signature, then verifies the signer address is correct.

It serves as a lookup table for EVM circuit to do random access of any field of transaction.

To prevent any skip of transaction, we verify te amount of transactions in Tx circuit is equal to the amount that verified in EVM circuit.
