# Architecture

<!-- toc -->

# Concepts

## Circuit as a lookup table

In halo2, the lookup is flexible to be configured, anything able to be turned into `Expression` could used to be `item: Tuple[int, ...]` or `table: Set[Tuple[int, ...]]` in lookup, and then it `assert item in table`. The `Expression` includes constant, queried fixed, advice or instance column at arbitrary rotation, addition/multiplication of `Expression`.

The motivation to have multiple circuits as lookup tables is because EVM contains many circuit unfriendly operation like random read-write data access, wrong field operation (ECDSA on secp256k1), traditional hash function (keccak256), etc... And many of them accept variable lenght input.

These expensive operations makes it hard to design a EVM circuit to verify computation trace because each step could possibly contain some of them. So we try to separate these expensive operations to other single-purpose circuits which have more friendly layout, and use them by a lookup (or serveral lookups) to communicate input and output to outsource the effort.

The reason lookup with input and output could be used to outsource the effort is that we know the table lookup-ed is configured with constraints to verify the input and output are in some relationship. For example, we let Bytecode circuit to holds a set of tuple `(code_hash, index, opcode)`, and each `code_hash` is verified to be the keccak256 digest of opcodes it contains, then in EVM circuit we can load `opcode` with `(code_hash, program_counter)` by lookup to Bytecode circuit.

However, sometimes there are some properties we can't ensure by only lookups. For example, the amount of all `item` should equal to the size of `table`, which is required by between EVM circuit and State circuit to prevent extra malicious write. In such case (`assert set(items) == table`), we need some extra constraint to ensure the relationship is correct. A naive approach is to also count all `item` in State circuit, which in the end is the size of the `table`, and constraint it to be equal to the one counted in EVM circuit.

> The original approach is using lookup to move the meaningful items from State circuit to bus mapping, which is another private table, and verify the bus mapping has degree bound that eqaul to the one counted in EVM circuit.
> But it turns out that we also need to count in State circuit, otherwise the prover could insert something in bus mapping but skip it in State circuit. We can try to do lookup from bus mapping to State circuit to avoid the counting in State circuit, but it just makes bus mapping seem to be a redundant layer.
> In general, such case is more like reorder something to be friendly to perform other constraint instead of subset, which should be easy to add in halo2 since subset argument already uses such shuffle argument. But for flexibility, we might have multiple lookup to State circuit like `assert set(items1).intersection(set(items2)) == {0} and set(items1) + set(items2) == table`) , which is not a simple shuffle, so counting items in State circuit seems to be a more general solution.
> 
> **han**

## Architecture diagram

Each circuit is layouted to be friendly to build their own custom constraints. When circuits encounter some expensive operations, they can outsource the effort to other circuits by lookup. The relationship between circuits would be like:

![](./architecture_diagram.png)

In the end the circuits would be assembled depending on their dimension and the desired capacity. For example, we can just combine 2 different circuits by using different columns, or stack them using same columns with extra selectors.

## EVM word encoding

[TODO](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/word-encoding.md)

# Custom types

# Constants

| Name                 | Value        | Description                     |
| -------------------- | ------------ | ------------------------------- |
| `MAX_MEMORY_ADDRESS` | `2**40 - 1`  | max memory address allowed [^1] |
| `MAX_GAS`            | `2**64 - 1`  | max gas allowed                 |
| `MAX_ETHER`          | `2**256 - 1` | max value of ether allowed [^2] |


[^1]: The explicit max memory address in EVM is actually `32 * (2**32 - 1)`, which is the one that doesn't make memory expansion gas cost overflow `u64`. In our case, memory address is allowed to be 5 bytes, but will constrain the memory expansion gas cost to fit `u64` in success case.

[^2]: I didn't find a explicit upper bound on value of ether (for `balance` or `gas_price`) in yellow paper, but handling unbounded big integer seems unrealistic in circuit, so with `u256` as a hard bound seems reasonable.
