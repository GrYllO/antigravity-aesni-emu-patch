#!/bin/bash
# Unified Antigravity AES-NI Emulation Patch Script
# Resolves CPU compatibility issues on hosts lacking AES-NI instructions.
# Requires QEMU user emulator (qemu-x86_64).
#
# Copyright (c) 2026 Felipe Grilo (aka GrYllO)
# MIT License: <https://opensource.org/license/mit/>

# Default paths
DEFAULT_QEMU_NAME="qemu-x86_64"
QEMU_PATH=""
REVERT_MODE=false

# User-specified custom search paths
CUSTOM_PATHS=()

# Determine default Caskroom location using Homebrew if available
BREW_PREFIX=$(which brew &>/dev/null && brew --prefix)
if [ -n "$BREW_PREFIX" ]; then
    DEFAULT_CASKROOM="$BREW_PREFIX/Caskroom"
else
    DEFAULT_CASKROOM="/home/linuxbrew/.linuxbrew/Caskroom"
fi

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  -q, --qemu-path <path>    Specify custom path to qemu-x86_64 binary.
  -p, --path <path>         Specify custom path/directory to search for Antigravity installations (repeatable).
  -r, --revert              Revert the patch (restores original binaries).
  -h, --help                Show this help message.

Environment Variables:
  QEMU_PATH                 Override path to qemu-x86_64.
  ANTIGRAVITY_SEARCH_PATH   Alternative way to supply custom search paths (comma-separated).
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--qemu-path)
            QEMU_PATH="$2"
            shift 2
            ;;
        -p|--path)
            CUSTOM_PATHS+=("$2")
            shift 2
            ;;
        -r|--revert)
            REVERT_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Resolve QEMU path if not reverting
if [ "$REVERT_MODE" = false ] && [ -z "$QEMU_PATH" ]; then
    # 1. Check system PATH
    if which "$DEFAULT_QEMU_NAME" &>/dev/null; then
        QEMU_PATH=$(which "$DEFAULT_QEMU_NAME")
    # 2. Check Homebrew default path
    elif [ -n "$BREW_PREFIX" ] && [ -f "$BREW_PREFIX/bin/$DEFAULT_QEMU_NAME" ]; then
        QEMU_PATH="$BREW_PREFIX/bin/$DEFAULT_QEMU_NAME"
    # 3. Check hardcoded common paths
    elif [ -f "/home/linuxbrew/.linuxbrew/bin/$DEFAULT_QEMU_NAME" ]; then
        QEMU_PATH="/home/linuxbrew/.linuxbrew/bin/$DEFAULT_QEMU_NAME"
    elif [ -f "/usr/bin/$DEFAULT_QEMU_NAME" ]; then
        QEMU_PATH="/usr/bin/$DEFAULT_QEMU_NAME"
    else
        echo "Error: $DEFAULT_QEMU_NAME not found in PATH or standard directories."
        echo "Please install QEMU or specify the path using --qemu-path."
        exit 1
    fi
fi

if [ "$REVERT_MODE" = true ]; then
    echo "Running in Revert mode (restoring original binaries)..."
else
    echo "Using QEMU: $QEMU_PATH"
fi

# Function to patch a binary via backing up and creating a wrapper shell script
patch_binary() {
    local bin_path="$1"
    
    if [ -z "$bin_path" ] || [ ! -f "$bin_path" ]; then
        return 1
    fi
    
    local dir
    dir=$(dirname "$bin_path")
    local bin_name
    bin_name=$(basename "$bin_path")
    
    # Check if it's already a script wrapper (starts with shebang)
    if head -n 1 "$bin_path" | grep -q "^#!"; then
        echo "Skipping $bin_path (already a script wrapper)."
        return 0
    fi
    
    # Ensure it is an ELF binary
    if ! file "$bin_path" 2>/dev/null | grep -q "ELF"; then
        echo "Skipping $bin_path (not an ELF binary)."
        return 0
    fi
    
    cd "$dir" || return 1
    
    if [ ! -f "${bin_name}.real" ]; then
        echo "Patching binary: $bin_path"
        mv "$bin_name" "${bin_name}.real"
        cat << EOF > "$bin_name"
#!/bin/bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec "$QEMU_PATH" -cpu Westmere "\$DIR/${bin_name}.real" "\$@"
EOF
        chmod +x "$bin_name"
        echo "Successfully patched $bin_name"
    else
        echo "Binary $bin_name in $dir is already patched."
    fi
}

# Function to revert a binary back to its original name
revert_binary() {
    local real_path="$1"
    
    if [ -z "$real_path" ] || [ ! -f "$real_path" ]; then
        return 1
    fi
    
    local dir
    dir=$(dirname "$real_path")
    local real_name
    real_name=$(basename "$real_path")
    local bin_name="${real_name%.real}"
    
    cd "$dir" || return 1
    
    if [ -f "$bin_name" ] && head -n 1 "$bin_name" | grep -q "^#!"; then
        echo "Reverting patch: restoring $bin_name from $real_name"
        mv -f "$real_name" "$bin_name"
        echo "Successfully reverted $bin_name"
    else
        echo "Could not safely revert $bin_name (original wrapper script not found or unrecognized format)."
    fi
}

# Resolve search roots
SEARCH_ROOTS=()
if [ ${#CUSTOM_PATHS[@]} -gt 0 ]; then
    # Use command-line supplied paths
    SEARCH_ROOTS=("${CUSTOM_PATHS[@]}")
elif [ -n "$ANTIGRAVITY_SEARCH_PATH" ]; then
    # Use environment variable paths (comma-separated)
    IFS=',' read -r -a SEARCH_ROOTS <<< "$ANTIGRAVITY_SEARCH_PATH"
else
    # Fall back to default standard locations
    SEARCH_ROOTS=(
        "$DEFAULT_CASKROOM"
        "/opt"
        "$HOME/Applications"
        "$HOME/.local"
        "/usr/local"
        "/usr/share"
    )
fi

# Keep track of directories searched to avoid double work
declare -A SEARCHED_DIRS

# Find and patch/revert files
for root in "${SEARCH_ROOTS[@]}"; do
    # Expand tilde if any path contains it literally
    root="${root/#\~/$HOME}"
    
    if [ -n "$root" ] && [ -d "$root" ]; then
        # Skip if already searched (e.g. nested paths)
        if [ "${SEARCHED_DIRS[$root]}" ]; then continue; fi
        SEARCHED_DIRS[$root]=1
        
        echo "Searching installation directory: $root"
        
        if [ "$REVERT_MODE" = true ]; then
            # Revert files
            find "$root" -type f \( -name "*.real" \) -maxdepth 5 2>/dev/null | while read -r real_file; do
                revert_binary "$real_file"
            done
        else
            # Patch files
            find "$root" -type f \( -name "language_server" -o -name "language_server_linux_x64" -o -name "agy" -o -name "antigravity" \) -maxdepth 5 2>/dev/null | while read -r bin_file; do
                patch_binary "$bin_file"
            done
        fi
    else
        echo "Search directory not found: $root"
    fi
done

echo "=== Done ==="
