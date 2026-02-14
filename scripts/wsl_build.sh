#!/bin/bash
export HOME=/home/byezz
export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:/home/byezz/.starkli/bin:/home/byezz/.foundry/bin:$PATH

echo "=== Tool versions ==="
scarb --version
snforge --version
starkli --version

echo ""
echo "=== Building contracts ==="
cd /mnt/c/Users/byezz/Desktop/starknet_hack/contracts
scarb build 2>&1
echo "Build exit code: $?"
