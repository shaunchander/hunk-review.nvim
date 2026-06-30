# hunk-review.nvim Tests

This directory contains the test suite for hunk-review.nvim using [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

## Prerequisites

Before running tests, ensure you have:

1. **Neovim** (v0.9.0 or later recommended)
2. **plenary.nvim** installed (required for test harness)
3. **snacks.nvim** installed (required dependency for hunk-review)

If you're using lazy.nvim or another package manager, these should already be installed in your Neovim data directory.

## Running Tests

### Run all tests

```bash
make test
```

Or directly with plenary:

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

### Run a specific test file

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/diff_spec.lua"
```

### Run tests interactively

To run tests with output in a Neovim buffer:

```vim
:PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }
```

Or for a single file:

```vim
:PlenaryBustedFile tests/diff_spec.lua
```

## Test Structure

```
tests/
├── minimal_init.lua      # Minimal Neovim config for testing
├── diff_spec.lua         # Tests for diff module
├── git_spec.lua          # Tests for git operations
├── plugin_spec.lua       # Tests for main plugin functionality
├── export_spec.lua       # Tests for export functionality
├── tree_spec.lua         # Tests for file tree rendering
└── health_spec.lua       # Tests for health checks
```

## Test Coverage

The test suite covers:

- **diff module**: Hunk parsing, change block detection, comment key generation
- **git module**: Git operations, branch detection, diff loading
- **plugin**: Commands, public API, buffer setup, highlights
- **export**: JSON export, clipboard formatting, payload generation
- **tree**: File tree building, rendering, ordering
- **health**: Health check execution

## Writing Tests

Tests use the [busted](https://olivinelabs.com/busted/) test framework via plenary.nvim.

Basic test structure:

```lua
describe("module name", function()
  describe("function name", function()
    it("does something specific", function()
      local result = some_function()
      assert.are.equal(expected, result)
    end)
  end)
end)
```

### Common Assertions

- `assert.are.equal(expected, actual)`
- `assert.are_not.equal(expected, actual)`
- `assert.is_true(value)`
- `assert.is_false(value)`
- `assert.is_nil(value)`
- `assert.is_not_nil(value)`
- `assert.is_string(value)`
- `assert.is_table(value)`
- `assert.is_function(value)`

### Test Hooks

- `before_each(function() ... end)` - Run before each test
- `after_each(function() ... end)` - Run after each test
- `pending("reason")` - Skip a test with a reason

## Continuous Integration

Tests can be run in CI environments (GitHub Actions, etc.) using the headless mode.

See the example in `.github/workflows/test.yml` for GitHub Actions integration.

## Troubleshooting

### Tests fail with "module not found"

Ensure `tests/minimal_init.lua` correctly sets up the runtime path. The test file assumes plenary.nvim and snacks.nvim are installed in the standard Neovim data directory.

### Git-related tests fail

Some tests require being run from within a git repository. Run tests from the plugin's root directory.

### Health check tests fail

Health check tests may produce different results depending on your environment (git installed, inside a repo, etc.). This is expected behavior.
