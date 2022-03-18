# Introduction

The zkEVM aims to specify and implement a solution to validate Ethereum blocks
via zero knowledge proofs.  The project aims to achieve 100% compatibility with
the Ethereum's EVM. It's an open-source project that is contributed and owned
by the community. Check out the contributors at
[here](https://github.com/appliedzkp/zkevm-circuits/graphs/contributors) and
[here](https://github.com/appliedzkp/zkevm-specs/graphs/contributors).

This book contains general documentation of the project.

The project currently has two goals:

## zkRollup

Build a solution that allows deploying a layer 2 network that is compatible
with the Ethereum ecosystem (by following the Ethereum specification) and
submits zero knowledge proofs of correctly constructed new blocks to a layer 1
smart contract which validates such proofs (and acts as a consensus layer).

The usage of zero knowledge proofs to validate blocks allows clients to
validate transactions quicker than it takes to process them, offering benefits
in scalability.

## Validity proofs

Build a solution that allows generating zero knowledge proofs of blocks from an
existing Ethereum network (such as mainnet), and publish them in a smart
contract in the same network.

The usage of zero knowledge proofs to validate blocks allows light clients to
quickly synchronize many blocks with low resource consumption, while
guaranteeing the correctness of the blocks without needing trust on external
parties.

# Status

The zkEVM project is not yet complete, so you may find parts that are not yet
implemented, incomplete, or don't have a specification.  At the same time,
other parts which are already implemented may be changed in the future.

# Links

- [Implementation](https://github.com/appliedzkp/zkevm-circuits)
- [Specification](https://github.com/appliedzkp/zkevm-specs)

