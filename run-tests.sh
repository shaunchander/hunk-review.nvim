#!/usr/bin/env bash

# run-tests.sh - Test runner for hunk-review.nvim
# This script provides an alternative to make for running tests

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_help() {
  echo "hunk-review.nvim Test Runner"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help              Show this help message"
  echo "  -f, --file FILE         Run tests in specific file"
  echo "  -i, --interactive       Run tests interactively in Neovim"
  echo "  -v, --verbose           Enable verbose output"
  echo ""
  echo "Examples:"
  echo "  $0                      # Run all tests"
  echo "  $0 -f tests/diff_spec.lua   # Run specific test file"
  echo "  $0 -i                   # Run tests interactively"
}

run_all_tests() {
  echo -e "${GREEN}Running all tests...${NC}"
  nvim --headless -u tests/minimal_init.lua \
    -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
}

run_test_file() {
  local file=$1
  if [ ! -f "$file" ]; then
    echo -e "${RED}Error: File '$file' not found${NC}"
    exit 1
  fi

  echo -e "${GREEN}Running tests in $file...${NC}"
  nvim --headless -u tests/minimal_init.lua \
    -c "PlenaryBustedFile $file"
}

run_interactive() {
  echo -e "${GREEN}Opening Neovim with test runner...${NC}"
  nvim -u tests/minimal_init.lua \
    -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
}

# Check if nvim is installed
if ! command -v nvim &> /dev/null; then
  echo -e "${RED}Error: Neovim (nvim) is not installed or not in PATH${NC}"
  exit 1
fi

# Parse command line arguments
INTERACTIVE=false
TEST_FILE=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      print_help
      exit 0
      ;;
    -f|--file)
      TEST_FILE="$2"
      shift 2
      ;;
    -i|--interactive)
      INTERACTIVE=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      print_help
      exit 1
      ;;
  esac
done

# Run tests based on options
if [ "$INTERACTIVE" = true ]; then
  run_interactive
elif [ -n "$TEST_FILE" ]; then
  run_test_file "$TEST_FILE"
else
  run_all_tests
fi

echo -e "${GREEN}Done!${NC}"
