#!/usr/bin/env bash

# verify-tests.sh - Quick verification that tests can run
# This script does a sanity check before running the full test suite

set -e

echo "🔍 Verifying test setup..."
echo ""

# Check Neovim is installed
if ! command -v nvim &> /dev/null; then
  echo "❌ Neovim not found in PATH"
  exit 1
fi
echo "✅ Neovim found: $(nvim --version | head -1)"

# Check plenary.nvim exists
PLENARY_PATH="$HOME/.local/share/nvim/lazy/plenary.nvim"
if [ ! -d "$PLENARY_PATH" ]; then
  echo "❌ plenary.nvim not found at $PLENARY_PATH"
  echo "   Please install plenary.nvim first"
  exit 1
fi
echo "✅ plenary.nvim found"

# Check snacks.nvim exists
SNACKS_PATH="$HOME/.local/share/nvim/lazy/snacks.nvim"
if [ ! -d "$SNACKS_PATH" ]; then
  echo "❌ snacks.nvim not found at $SNACKS_PATH"
  echo "   Please install snacks.nvim first"
  exit 1
fi
echo "✅ snacks.nvim found"

# Check test directory exists
if [ ! -d "tests" ]; then
  echo "❌ tests/ directory not found"
  echo "   Make sure you're running this from the plugin root directory"
  exit 1
fi
echo "✅ tests/ directory found"

# Check minimal_init.lua exists
if [ ! -f "tests/minimal_init.lua" ]; then
  echo "❌ tests/minimal_init.lua not found"
  exit 1
fi
echo "✅ tests/minimal_init.lua found"

# Count test files
TEST_COUNT=$(find tests -name "*_spec.lua" | wc -l | tr -d ' ')
echo "✅ Found $TEST_COUNT test files"

echo ""
echo "🎉 Test setup verification complete!"
echo ""
echo "Ready to run tests with:"
echo "  make test              # Run all tests"
echo "  ./run-tests.sh         # Alternative using shell script"
echo "  make test-interactive  # Run interactively in Neovim"
