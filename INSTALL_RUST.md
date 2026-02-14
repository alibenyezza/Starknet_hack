# Installing Rust in WSL

Scarb needs Rust/cargo for some dependency operations. Here's how to install it:

## Quick Install (Recommended)

Run this in your WSL terminal:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Follow the prompts (press Enter to accept defaults).

Then reload your shell:
```bash
source ~/.cargo/env
# or
source ~/.bashrc
```

Verify installation:
```bash
rustc --version
cargo --version
```

## After Installation

Once Rust is installed, try building again:

```bash
cd /mnt/c/Users/byezz/Desktop/starknet_hack/contracts
scarb build
```
