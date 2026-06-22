# Antigravity AES-NI Emulation Patch

This script resolves CPU compatibility issues (like "Illegal instruction" errors) for the **Antigravity** suite (IDE, Language Server, and CLI) on systems that lack native **AES-NI** instruction set support (such as older Intel Core 2 Duo, Pentium, Celeron, or AMD Phenom CPUs, and certain virtual machine configurations).

It works by wrapping the native Antigravity ELF binaries inside a script wrapper that runs them via the QEMU User Space Emulator (`qemu-x86_64`) with a target CPU architecture (`-cpu Westmere`) that supports AES-NI instruction emulation.

## Requirements

- **Linux** (x86_64)
- **QEMU User Space Emulator** (`qemu-x86_64` binary)
  - On Debian/Ubuntu: `sudo apt install qemu-user`
  - On Fedora/RHEL: `sudo dnf install qemu-user`
  - On Arch Linux: `sudo pacman -S qemu-user`
  - On macOS/Linux Homebrew: `brew install qemu`

## Features

- **Automated Scanning**: Scans common installation roots recursively (up to 5 levels deep) to find installed components:
  - Homebrew Caskroom (e.g. `Caskroom/antigravity-*`)
  - `/opt/`
  - `~/Applications/`
  - `~/.local/`
  - `/usr/local/`
  - `/usr/share/`
- **Idempotent and Safe**: Identifies whether a binary has already been patched or is an existing shell wrapper script, and safely skips it to prevent double-wrapping and execution errors.
- **Custom Configuration**: Allows specifying custom paths to `qemu-x86_64` and custom directories to search for Antigravity installations via flags or environment variables.

## Usage

### Direct Run

Make the script executable and run it:

```bash
chmod +x antigravity_aesni_emu_patch.sh
./antigravity_aesni_emu_patch.sh
```

### Options

```text
Usage: antigravity_aesni_emu_patch.sh [options]

Options:
  -q, --qemu-path <path>    Specify custom path to qemu-x86_64 binary.
  -p, --path <path>         Specify custom path/directory to search for Antigravity installations (repeatable).
  -r, --revert              Revert the patch (restores original binaries).
  -h, --help                Show this help message.

Environment Variables:
  QEMU_PATH                 Override path to qemu-x86_64.
  ANTIGRAVITY_SEARCH_PATH   Alternative way to supply custom search paths (comma-separated).
```

### Examples

**Use a custom QEMU binary path:**

```bash
./antigravity_aesni_emu_patch.sh --qemu-path /usr/local/bin/qemu-x86_64
```

**Use a custom search path:**

```bash
./antigravity_aesni_emu_patch.sh --path /my/custom/installation/directory
```

**Uninstall / Revert the patch:**
To remove the wrappers and restore all original binaries, run with the `-r` or `--revert` flag:

```bash
./antigravity_aesni_emu_patch.sh --revert
```

## How It Works Under the Hood

For each detected ELF binary (`language_server`, `language_server_linux_x64`, `antigravity`, `agy`):

1. The script renames the original binary (e.g. `antigravity` to `antigravity.real`).
2. A bash script replaces the original binary path.
3. This bash wrapper executes the `.real` binary inside QEMU:

   ```bash
   #!/bin/bash
   DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   exec "/path/to/qemu-x86_64" -cpu Westmere "$DIR/antigravity.real" "$@"
   ```

4. Subsequent calls to the binary (or wrapper scripts pointing to them) run transparently via emulation.
