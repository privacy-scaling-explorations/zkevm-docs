# Architecture

<!-- toc -->

# Concepts

## Architecture diagram

Each circuit is layouted to be capable to build their own custom constraints. When circuits encounter some expensive operations, they can outsource the effort to other circuits through the usage of lookup arguments. 
The relationship between circuits looks like:

![](./architecture_diagram2.png)

List of circuits and tables they generate/verify:

| Circuit                                                | Table                                                                                                  |
| ---                                                    | ---                                                                                                    |
| [EVM Circuit](./architecture/evm-circuit.md)           |                                                                                                        |
| [Bytecode Circuit](./architecture/bytecode-circuit.md) | [Bytecode Table](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/tables.md#bytecode_table) |
| [State Circuit](./architecture/state-circuit.md)       | [Rw Table](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/tables.md#rw_table)             |
| Block Circuit                                          | [Block Table](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/tables.md#block_table)       |
| [Tx Circuit](./architecture/tx-circuit.md)             | [Tx Table](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/tables.md#tx_table)             |
| [MPT Circuit](./architecture/mpt-circuit.md)           | MPT Table                                                                                              |
| [Keccak Circuit](./architecture/keccak-circuit.md)     | Keccak Table                                                                                           |
| [ECDSA Circuit](./architecture/ecdsa-circuit.md)       | ECDSA Table                                                                                            |

In the end, the circuits would be assembled depending on their dimension and the desired capacity. For example, we can just combine 2 different circuits by using different columns, or stack them using same columns with extra selectors.

In order to reduce the time required to build a proof of a full block and to
simplify the verification step, an aggregation circuit is being built to condenses the
verification of each sub-circuit proof shown in the diagram.  See [Design
Notes, Recursion](./design/recursion.md) for details on the recursion strategy
used in the aggregation circuit.

## Circuit as a lookup table

In halo2, lookup configuration is quite flexible, therefore anything that can be represented as an `Expression` could be used as an `item: Tuple[int, ...]` or `table: Set[Tuple[int, ...]]` in lookup. This enables assertion of items in the lookup table e.g. `assert item in table`. Examples of the `Expression` include `Constant`, `Fixed`, `Advice` or `Instance` column at arbitrary rotation.

The motivation to have multiple circuits as lookup tables is that the EVM contains many operations which are not suited to circuits, such as random read-write data access, "wrong" field operation (ECDSA on secp256k1) and traditional hash functions like `keccak256` to name a few. This is not suited to circuits because they all accept variable length inputs. Designing an EVM circuit that can verify computation traces become much more complex because each step could possibly contain some of the aforementioned operations. In order to solve this problem, we separated these expensive operations into single-purpose circuits which have a more friendly layout, and use them via lookups to communicate the requisite input and output. This is made possible by the fact that the lookup table is configured with constraints to ensure that the input and output have a relationship. For example, the Bytecode circuit contains a set of tuples `(code_hash, index, opcode)`, and each `code_hash` is the keccak256 digest of opcodes it contains, thus in the EVM circuit we can load `opcode` with `(code_hash, program_counter)` by performing a lookup the Bytecode table.

Whilst this method may work well for many cases, there are some properties that can't be verified exclusively with lookups (because the contents of all the lookups are only a subset of a table). Therefore, the number of all *looked-up items* should be equal to the size of `table`. This constraint is required by the EVM circuit and State circuit to prevent malicious writes in the `table`. In such case (the set of looked up items define the table exactly), we need some extra constraint to ensure the relationship is correct. A naive approach is to count all `item` in State circuit (which in the end is the size of the `table`) and ensure that it is equal to the value counted in the EVM circuit.


## EVM word encoding

See [Design Notes, Random Linear Combination](./design/random-linear-combinaion.md)

- [Word encoding spec](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/word-encoding.md)

# Custom types

# Constants

| Name                 | Value        | Description                     |
| -------------------- | ------------ | ------------------------------- |
| `MAX_MEMORY_ADDRESS` | `2**40 - 1`  | max memory address allowed [^1] |
| `MAX_GAS`            | `2**64 - 1`  | max gas allowed                 |
| `MAX_ETHER`          | `2**256 - 1` | max value of ether allowed [^2] |


[^1]: The explicit max memory address in EVM is actually `32 * (2**32 - 1)`,in order to prevent memory expansion gas cost from overflowing `u64`. In theory, a memory address is allowed to be 5 bytes, but will limit the memory expansion gas cost to fit `u64` in success case.

[^2]: There's no explicit upper bound on the value of ether (for `balance` or `gas_price`) in the yellow paper, but handling an unbounded big integer is impractical in  the circuit, so it is limited to `u256`.
