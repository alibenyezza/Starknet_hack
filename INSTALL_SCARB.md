# Installing Scarb on Windows

Scarb is the package manager for Cairo/Starknet. Here are the installation methods for Windows:

## Method 1: Using WSL (Windows Subsystem for Linux) - Recommended

Since Scarb works best on Linux/macOS, the recommended approach for Windows is to use WSL:

1. **Install WSL** (if not already installed):
   ```powershell
   wsl --install
   ```
   Restart your computer after installation.

2. **Open WSL terminal** and run:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.starkup.sh | sh
   ```
   This installs Scarb via Starkup (recommended method).

3. **Verify installation**:
   ```bash
   scarb --version
   ```

4. **Navigate to your project in WSL**:
   ```bash
   cd /mnt/c/Users/byezz/Desktop/starknet_hack/contracts
   scarb build
   ```

## Method 2: Using Rust/Cargo (Native Windows)

If you have Rust installed on Windows:

```powershell
cargo install --locked scarb
```

Then verify:
```powershell
scarb --version
```

## Method 3: Download Pre-built Binary (Windows)

1. Visit: https://github.com/software-mansion/scarb/releases
2. Download the latest Windows release (`.zip` file for x86_64-pc-windows-msvc)
3. Extract to a folder (e.g., `C:\Program Files\scarb`)
4. Add `C:\Program Files\scarb\bin` to your PATH environment variable
5. Restart PowerShell and verify:
   ```powershell
   scarb --version
   ```

## Verify Installation

After installation, verify it works:

```powershell
scarb --version
```

You should see output like:
```
scarb 2.6.3 (commit_hash date)
cairo: 2.6.3
sierra: 1.x.x
```

## Next Steps

Once Scarb is installed, you can build the project:

```powershell
cd contracts
scarb build
```

This will:
- Download dependencies (OpenZeppelin contracts, etc.)
- Compile all Cairo contracts
- Generate Sierra and CASM files in `target/` directory

## Troubleshooting

If you encounter issues:
- Make sure you're in the `contracts` directory (where `Scarb.toml` is located)
- Check that Scarb is in your PATH: `where.exe scarb` (PowerShell) or `which scarb` (WSL)
- For Windows-specific issues, consider using WSL as it's the most reliable option
