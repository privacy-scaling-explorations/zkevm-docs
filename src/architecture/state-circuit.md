# State Circuit

<!-- toc -->

# Introduction

The State circuit iterates over random read-write access records of EVM circuit to verify that each piece of data is consistent between different writes. It also verifies the state merkle patricia trie root hash corresponds to a valid transition from old to new one incrementally, where both are from public input.

To verify if data is consistent, it first verifies that all access records are grouped by their unique identifier and sorted by order of access. Then verifies that the records between writes are consistent. It also verifies that data is in the correct format.

It serves as a lookup table for EVM circuit to do consistent random read-write access.

To prevent any malicious insertion of access record, we also verify the amount of random read-write access records in State circuit is equal to the amount in EVM circuit (the final value of `rw_counter`).

# Concepts

## Read-write unit grouping

The first thing to ensure data is consistent between different writes is to give each data an unique identifier, then group data chunks by the unique identifier. And finally, then sort them by order of access `rw_counter`. 

Here are all kinds of data with their unique identifier:


| Tag                       | Unique Index                             | Values                                |
| ------------------------- | ---------------------------------------- | ------------------------------------- |
| `TxAccessListAccount`     | `(tx_id, account_address)`               | `(is_warm, is_warm_prev)`             |
| `TxAccessListAccountStorage` | `(tx_id, account_address, storage_slot)` | `(is_warm, is_warm_prev)`             |
| `TxRefund`                | `(tx_id)`                                | `(value, value_prev)`                 |
| `Account`                 | `(account_address, field_tag)`           | `(value, value_prev)`                 |
| `AccountStorage`          | `(account_address, storage_slot)`        | `(value, value_prev)`                 |
| `AccountDestructed`       | `(account_address)`                      | `(is_destructed, is_destructed_prev)` |
| `CallContext`             | `(call_id, field_tag)`                   | `(value)`                             |
| `Stack`                   | `(call_id, stack_address)`               | `(value)`                             |
| `Memory`                  | `(call_id, memory_address)`              | `(byte)`                              |

Different tags have different constraints on their grouping and values.

Most tags also keep the previous value `*_prev` for convenience, which helps reduce the lookup when EVM circuit is performing a write with a `diff` to the current value, or performing a write with a reversion.

## Lazy initialization

EVM's memory expands implicitly, for example, when the memory is empty and it enounters a `mload(32)`, EVM first expands to memory size to `64`, and then loads the bytes just initialized to push to the stack, which is always a `0`.

The implicit expansion behavior makes even the simple `MLOAD` and `MSTORE` complicated in EVM circuit, so we have a trick to outsource the effort to State circuit by constraining the first record of each memory unit to be a write or have value `0`. It saves the variable amount of effort to expand memory and ignore those never used memory, only used memory addresses will be initlized with `0` so as lazy initialization.

> This concept is also used in another case: the opcode `SELFDESTRUCT` also has ability to update the variable amount of data. It resets the `balance`, `nonce`, `code_hash`, and every `storage_slot` even if it's not used in the step. So for each state under account, we can add a `revision_id` handle such case, see [Design Notes, State Write Reversion Note2, SELFDESTRUCT](./state-write-reversion2.md#selfdestruct) for details.
> ==TODO== Convert this into an issue for discussion
>
> **han**

## Trie opening and incrementally update

# Constraints

## `main`

==TODO== Explain each tag

<!-- 
##### `tx_access_list_account` 
##### `tx_access_list_storage_slot`
##### `tx_refund`
##### `account_nonce`
##### `account_balance`
##### `account_code_hash`
##### `account_storage`
##### `call_state`
##### `stack`
##### `memory`
 -->

# Implementation

- [spec](https://github.com/appliedzkp/zkevm-specs/blob/master/specs/state-proof.md)
    - [python](https://github.com/appliedzkp/zkevm-specs/blob/master/src/zkevm_specs/state.py)
- [circuit](https://github.com/appliedzkp/zkevm-circuits/blob/main/zkevm-circuits/src/state_circuit.rs)
