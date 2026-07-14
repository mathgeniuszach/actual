#!/usr/bin/env bash
# Script to generate the yarn offline cache hash for the flake
# Run this after updating dependencies

set -e

echo "Generating yarn offline cache hash..."
echo "This will take a while as it downloads all dependencies..."
echo ""

# Build with fake hash to get the real hash
OUTPUT=$(nix build .#actual-server 2>&1 || true)

# Extract the hash from the error message
HASH=$(echo "$OUTPUT" | grep -oP 'got:\s*\Ksha256-[A-Za-z0-9+/=]+' | head -1)

if [ -n "$HASH" ]; then
    echo "$HASH" > .yarn-hash
    echo "✓ Hash saved to .yarn-hash: $HASH"
    echo ""
    echo "You can now build the package with:"
    echo "  nix build .#actual-server"
else
    echo "✗ Could not find hash in build output"
    echo ""
    echo "Full build output:"
    echo "========================================"
    echo "$OUTPUT"
    echo "========================================"
    exit 1
fi
