# Opcode Fetching

<!-- toc -->

# Introduction

For opcode fetching, we might have 3 sources in different situation:

1. When contract interaction, we lookup `bytecode_table` to read bytecode.
2. When contract creation in root call, we lookup `tx_table` to read transaction's calldata.
3. When contract creation in internal call, we lookup `rw_table` to read caller's memory.

Also we need to handle 2 kinds of annoying EVM features:

1. Implicit `STOP` returning if fetching out of range.
2. For `JUMP*`, we need to verify:
    1. destination is a `JUMPDEST`
    2. destination is not a data section of `PUSH*`

Since for each step `program_counter` only changes in 3 situation:

```python
if opcode in [JUMP, JUMPI]:
    program_counter = dest
elif opcode in range(PUSH1, PUSH1 + 32):
    program_counter += opcode - PUSH1 + 1
else:
    program_counter += 1
```

For all opcodes except for `JUMP*` and `PUSH*`, we only need to worry about first issue, and we can solve it by checking if `bytecode_length <= program_counter` then detect such case.

For `PUSH*` we can do the lookup only when `program_counter + x < bytecode_length` and simulate the "implicit `0`". (Other opcodes like `CALLDATALOAD`, `CALLDATACOPY`, `CODECOPY`, `EXTCODECOPY` also encounter such "implicit `0`" problem, and we need to handle them carefully).

However, for `JUMP*` we need one more trick to handle, especially for the **issue 2.2.**, which seems not possible to check if we don't scan through all opcodes from the beginning to the end.

Focus on solving the **issue 2.2.**, my thought went through 2 steps:

## Step #1 - `is_code` Annotation

If the opcode is layouted to be adjacent like the `bytecode_table` or `tx_table`, we can annotate each row with `push_data_rindex` and `is_code`:

> `push_data_rindex` means push data's reverse index, which starts from `1` instead of `0`.
>
> **han**

$$
\begin{array}{|c|c|}
\hline
\texttt{{bytecode_hash,tx_id}} & \texttt{index} & \texttt{opcode} & \texttt{push_data_rindex} & \texttt{is_code} & \text{note} \\\\\hline
\color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\texttt{0xff} & \texttt{0} & \texttt{PUSH1} & \texttt{0} & \texttt{1} \\\\\hline
\texttt{0xff} & \texttt{1} & \texttt{0xef} & \texttt{1} & \texttt{0} \\\\\hline
\texttt{0xff} & \texttt{2} & \texttt{0xee} & \texttt{0} & \texttt{1} \\\\\hline
\texttt{0xff} & \texttt{3} & \texttt{PUSH2} & \texttt{0} & \texttt{1} \\\\\hline
\texttt{0xff} & \texttt{4} & \texttt{PUSH1} & \texttt{2} & \texttt{0} & \text{is not code} \\\\\hline
\texttt{0xff} & \texttt{5} & \texttt{PUSH1} & \texttt{1} & \texttt{0} & \text{is not code} \\\\\hline
\texttt{0xff} & \texttt{6} & \texttt{JUMPDEST} & \texttt{0} & \texttt{1} & \text{is code!} \\\\\hline
\color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\end{array}
$$

The constraint would be like:

```python
class Row:
    code_hash_or_tx_id: int
    index: int
    opcode: int
    push_data_rindex: int
    is_code: int

def constraint(prev: Row, curr: Row, is_first_row: bool):
    same_source = curr.code_hash_or_tx_id == prev.code_hash_or_tx_id

    assert curr.is_code == is_zero(curr.push_data_rindex)

    if is_first_row or same_source:
        assert curr.push_data_rindex == 0
    else:
        if prev.is_code:
            if (prev.opcode - PUSH1) in range(32):
                assert curr.push_data_rindex == prev.opcode - PUSH1 + 1
            else:
                assert curr.push_data_rindex == 0
        else:
            assert curr.push_data_rindex == prev.push_data_rindex - 1
```

And when handling `JUMP*` we can check `is_code` for verification.

However, the memory in the State circuit it's layouted to be `memory_address` and then `rw_counter`, which we can't select at some specific point to do such analysis. So this approach seems not work on all situations.

## Step #2 - Explicitly copy memory to bytecode_table

It seems inevitable to copy the memory to `bytecode_table` since the `CREATE*` needs it to know the `bytecode_hash`. So maybe we can abuse such constraint to also copy the creation bytecode to the `bytecode_table`. Althought the hash of it means nothing, we still can use it as a unique identifier to index out the opcode.

Then we can define an internal multi-step execution result `COPY_MEMORY_TO_BYTECODE` which can only transit from `CREATE*` or `RETURN`, and copy the memory from offset with length to the `bytecode_table`.

Although it costs many steps to copy the creation code, it makes the opcode fetching source become simpler with only `bytecode_table` and `tx_table`. The issue of memory's unfriendly layout is also gone, **issue 2.2.** is then resolved.

> Memory copy on creation code seems terrible since a prover can reuse the same large chunk of memory to call multiple times of `CREATE*`, and we always need to copy them, which might cost many steps.
> We need some benchmark to see if a block contains full of such `CREATE*` to know how much gas we can verify in a block, then know if it's aligned to current gas cost model or not, and decide whether to further optimize it.
>
> **han**

## Random Thought

### Memory copy optimization

When it comes to "memory copy", it means in EVM circuit we lookup both `rw_table` and `bytecode_table` to make sure the chunk of memory indeed exists in the latter table. However, EVM circuit doesn't have a friendly layout to do such operation (it costs many expressions to achieve so).

If we want to further optimize "memory copy" in respect to the concern hilighted in [Step #2](## Step #2 - Explicitly copy memory to bytecode_table), since we know the memory to be copied is in chunk, and in `bytecode_table` it also exists in chunk, then we seem to let Bytecode circuit to do such operation with correct `rw_counter`, and in EVM circuit we only need to "trigger" such operation. We can add extra selector columns to enable it like:

$$
\begin{array}{|c|c|}
\hline
\texttt{call_id} & \texttt{memory_offset} & \texttt{rw_counter} & \texttt{bytecode_hash} & \texttt{bytecode_length} & \texttt{index} & \texttt{opcode} \\\\\hline
\color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\texttt{3} & \texttt{64} & \texttt{38} & \texttt{0xff} & \texttt{4} & \texttt{0} & \texttt{PUSH1} \\\\\hline
\texttt{3} & \texttt{64} & \texttt{39} & \texttt{0xff} & \texttt{4} & \texttt{1} & \texttt{0x00} \\\\\hline
\texttt{3} & \texttt{64} & \texttt{40} & \texttt{0xff} & \texttt{4} & \texttt{2} & \texttt{DUP1} \\\\\hline
\texttt{3} & \texttt{64} & \texttt{41} & \texttt{0xff} & \texttt{4} & \texttt{3} & \texttt{RETURN} \\\\\hline
\color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\end{array}
$$

> `bytecode_length` is required no matter we adopt this or not. It's ignored previously for simplicity
>
> **han**

Then the constraint in Bytecode circuit might look like:

```python
class Row:
    call_id: int
    memory_offset: int
    rw_counter: int

    bytecode_hash: int
    bytecode_length: int
    index: int
    opcode: int

def copy_memory_constraint(prev: Row, curr: Row, is_first_row: bool):
    same_source = curr.bytecode_hash == prev.bytecode_hash
    
    if same_source:
        assert curr.call_id == prev.call_id
        assert curr.memory_offset == prev.memory_offset
        assert curr.rw_counter == prev.rw_counter + 1

    if curr.call_id is not 0:
        assert (
            curr.rw_counter,                 # rw_counter
            False,                           # is_write
            Memory,                          # tag
            curr.call_id,                    # call_id
            curr.memory_offset + curr.index, # memory_address
            curr.opcode,                     # byte
            0,
            0,
        ) in rw_table
```

And in EVM circuit we only needs to make sure the first row of such series exist, then transit the `rw_counter` by `bytecode_length` to next step.

### Memory copy generalizaiton

For opcodes like `PUSH*`, `CALLDATALOAD`, `CALLDATACOPY`, `CODECOPY`, `EXTCODECOPY` we need to copy bytecode to memory and it seems that we can reuse the `COPY_MEMORY_TO_BYTECODE`, with a small tweak to change the `is_write` to memory to `True`.

### Tx calldata copy

Since we already copy memory, why not also copy the calldata part of `tx_table` to `bytecode_table`? We can use the same trick as in [Memory copy optimization](#Memory-copy-optimization) to make sure tx calldata is copied to `bytecode_table`. Then we only have a single source to do opcode fetching, which simplifies a lot of things.

> The only concern is, will this cost much on `bytecode_table`'s capacity? We still need actual benchmark to see if it's adoptable.
>
> **han**

> I think so it would be better to maintain only one byte_code_table for all related using if it is feasible, calldata copy of contract creation seems double the table size  
>
> **dream**

