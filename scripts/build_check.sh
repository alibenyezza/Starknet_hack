#!/bin/bash
export HOME=/home/byezz
export PATH=/home/byezz/.asdf/shims:/home/byezz/.local/bin:/home/byezz/.starkli/bin:/home/byezz/.foundry/bin:$PATH

echo "=== Scarb version ==="
scarb --version

echo ""
echo "=== Building contracts ==="
cd /mnt/c/Users/byezz/Desktop/starknethackathon/nouveaupush_starknet/Starknet_hack/contracts
scarb build 2>&1
echo "Build exit code: $?"
