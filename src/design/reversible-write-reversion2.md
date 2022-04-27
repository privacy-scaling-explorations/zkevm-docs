# Reversible Write Reversion Note 2

# ZKEVM - State Circuit Extension - `StateDB`

## Reversion

In EVM, there are multiple kinds of `StateDB` updates that could be reverted when any internal call fails.

- `tx_access_list_account` - `(tx_id, address) -> accessed`
- `tx_access_list_storage_slot` - `(tx_id, address, storage_slot) -> accessed`
- `account_nonce` - `address -> nonce`
- `account_balance` - `address -> balance`
- `account_code_hash` - `address -> code_hash`
- `account_storage` - `(address, storage_slot) -> storage`

The complete list can be found [here](https://github.com/ethereum/go-ethereum/blob/master/core/state/journal.go#L87-L141).  For `tx_refund`, `tx_log`, `account_destructed` we don't need to write and revert because those state changes don't affect future execution, so we only write them when `is_persistent=1`.

### Visualization

![](./state-write-reversion2_call-depth.png)

- Black arrow represents the time, which is composed by points of sequential `rw_counter`.
- Red circle represents the revert section.

The actions that write to the `StateDB` inside the red box will also revert themselves in the revert section (red circle), but in reverse order.

Each call needs to know its `rw_counter_end_of_revert_section` to revert with the correct `rw_counter`. If callee is a success call but in some red box (`is_persistent=0`), we need to copy caller's `rw_counter_end_of_revert_section` and `reversible_write_counter` to callee's.

## `SELFDESTRUCT`

The opcode `SELFDESTRUCT` sets the flag `is_destructed` of the account, but before that transaction ends, the account can still be executed, receive ether, and access storage as usual. The flag `is_destructed` takes effect only after a transaction ends.

In particular, the state trie gets finalized after each transaction, and only when state trie gets finalized the account is actually deleted. After the transaction with `SELFDESTRUCT` is finalized, any further transaction treats the account as an empty account.

> So if some contract executed `SELFDESTRUCT` but then receive some ether, those ether will vanish into thin air after the transaction is finalized. Soooo weird.
>
> **han**

The `SELFDESTRUCT` is a powerful opcode that makes many state changes at the same time including:

- `account_nonce`
- `account_balance`
- `account_code_hash`
- all slots of `account_storage`

The first 3 values are relatively easy to handle in circuit: we could track an extra `selfdestruct_counter` and `rw_counter_end_of_tx` and set them to empty value at `rw_counter_end_of_tx - selfdestruct_counter`, which is just how we handle reverts.

However, the `account_storage` is tricky because we don't track the storage trie and update it after each transaction, instead we only track each used slot in storage trie and update the storage trie after the whole block.

### Workaround for consistency check

It seems that we need to annotate each account with a `revision_id`. The `revision_id` increases only when `is_destructed` is set and `tx_id` changes. With the different `revision_id`s we can reset the values in State circuit for `nonce`, `balance`, `code_hash`, and each `storage` just like we initialize the memroy.

So `address -> is_destructed` becomes `(tx_id, address) -> (revision_id, is_destructed)`.

Then we add an extra `revision_id` to `nonce`, `balance`, `code_hash` and `storage`. For `nonce`, `balance` and `code_hash` we group them by `(address, revision_id) -> {nonce,balance,code_hash}`, for `storage` we group them by `(address, storage_slot, revision_id) -> storage_value`.

Here is an example of `account_balance` with `revision_id`:

$$
\begin{array}{|c|c|}
\hline
\texttt{address} & \texttt{revision_id} & \texttt{rwc} & \texttt{balance} & \texttt{balance_prev} & \texttt{is_write} & \text{note} \\\\\hline
\color{#aaa}{\texttt{0xfd}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\texttt{0xfe} & \texttt{1} & \color{#aaa}{\texttt{x}} & \texttt{10} & \color{#aaa}{\texttt{x}} & \texttt{1} & \text{open from trie} \\\\\hline
\texttt{0xfe} & \texttt{1} & \texttt{23} & \texttt{20} & \texttt{10} & \texttt{1} \\\\\hline
\texttt{0xfe} & \texttt{1} & \texttt{45} & \texttt{20} & \texttt{20} & \texttt{0} \\\\\hline
\texttt{0xfe} & \texttt{1} & \texttt{60} & \texttt{0} & \texttt{20} & \texttt{1} \\\\\hline
\texttt{0xfe} & \color{#f00}{\texttt{1}} & \texttt{63} & \texttt{5} & \texttt{0} & \texttt{1} \\\\\hline
\texttt{0xfe} & \color{#f00}{\texttt{2}} & \color{#aaa}{\texttt{x}} & \color{#f00}{\texttt{0}} & \color{#aaa}{\texttt{x}} & \texttt{1} & \text{reset} \\\\\hline
\texttt{0xfe} & \texttt{2} & \texttt{72} & \texttt{0} & \texttt{0} & \texttt{0} \\\\\hline
\color{#aaa}{\texttt{0xff}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\end{array}
$$

Note that after contract selfdestructs, it can still receive ether, but the ether will vanish into thin air after transaction gets finalized. The reset is like the lazy initlization of memory, **the value is set to `0` when `revision_id` is different**.

Here is how we increase the `revision_id`:

$$
\begin{array}{|c|c|}
\hline
\texttt{address} & \texttt{tx_id} & \texttt{rwc} & \texttt{revision_id} & \texttt{is_destructed} & \texttt{is_destructed_prev} & \texttt{is_write} & \text{note} \\\\\hline
\color{#aaa}{\texttt{0xfd}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\texttt{0xff} & \texttt{1} & \color{#aaa}{\texttt{x}} & \texttt{1} & \texttt{0} & \color{#aaa}{\texttt{x}} & \texttt{1} & \text{init} \\\\\hline
\texttt{0xff} & \texttt{1} & \texttt{11} & \texttt{1} & \texttt{0} & \texttt{0} & \texttt{0} \\\\\hline
\texttt{0xff} & \texttt{1} & \texttt{17} & \texttt{1} & \texttt{1} & \texttt{0} & \texttt{1} & \text{self destruct} \\\\\hline
\texttt{0xff} & \color{#f00}{\texttt{1}} & \texttt{29} & \texttt{1} & \color{#f00}{\texttt{1}} & \texttt{1} & \texttt{1} & \text{self destruct again} \\\\\hline
\texttt{0xff} & \color{#f00}{\texttt{2}} & \color{#aaa}{\texttt{x}} & \color{#f00}{\texttt{2}} & \texttt{0} & \color{#aaa}{\texttt{x}} & \texttt{1} & \text{increase} \\\\\hline
\texttt{0xff} & \texttt{2} & \texttt{40} & \texttt{2} & \texttt{0} & \texttt{0} & \texttt{0} \\\\\hline
\texttt{0xff} & \texttt{3} & \color{#aaa}{\texttt{x}} & \texttt{2} & \texttt{0} & \color{#aaa}{\texttt{x}} & \texttt{1} & \text{no increase} \\\\\hline
\color{#aaa}{\texttt{0xff}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} & \color{#aaa}{\texttt{-}} \\\\\hline
\end{array}
$$

Because self destruct only takes effect after the transaction, we **increase the `revision_id` only when `tx_id` is different and `is_destructed` is set**.

### Workaround for trie update

The State circuit not only checks consistency, it also triggers the update of the storage tries and state trie.

Originally, some part of State circuit would assign the first row value and collect the last row value of each account's `nonce`, `balance`, `code_hash` as well as the first & last used slots of storage, then update the state trie.

With `revision_id`, it needs to peek the final `revision_id` first, and collect the last row value with the `revision_id` to make sure all values are actually reset.

## Reference

- [`journal.go`](https://github.com/ethereum/go-ethereum/blob/master/core/state/journal.go)
- [Pragmatic destruction of `SELFDESTRUCT`](https://hackmd.io/@vbuterin/selfdestruct#SELFDESTRUCT-is-the-only-opcode-that-breaks-important-invariants)
