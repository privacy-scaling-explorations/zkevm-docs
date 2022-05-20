# zkEVM (Community Edition) Documentation

This is the documentation of the design and specification of the zkEVM
community edition.

This documentation is written in markdown and organized into an
[mdbook](https://github.com/rust-lang/mdBook) which can be [viewed
here](https://privacy-scaling-explorations.github.io/zkevm-docs/).

# Setup

First install mdbook and the enabled extensions:
```sh
cargo install mdbook
cargo install mdbook-mermaid
cargo install mdbook-toc
```

Now the mdbook can be built and served locally at [localhost:3000](http://localhost:3000):
```sh
mdbook serve
```
