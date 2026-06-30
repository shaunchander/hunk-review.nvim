# Test Suite Summary

This document provides an overview of the complete test suite created for hunk-review.nvim.

## 📁 Files Created

### Test Files
- `tests/minimal_init.lua` - Minimal Neovim configuration for test environment
- `tests/diff_spec.lua` - Tests for diff module (hunk parsing, change blocks, comment keys)
- `tests/git_spec.lua` - Tests for git operations (branch detection, diff loading, hunk parsing)
- `tests/plugin_spec.lua` - Tests for main plugin functionality (commands, API, buffers, highlights)
- `tests/export_spec.lua` - Tests for export functionality (JSON export, clipboard formatting)
- `tests/tree_spec.lua` - Tests for file tree rendering and ordering
- `tests/health_spec.lua` - Tests for health check functionality
- `tests/integration_spec.lua` - Integration tests for full plugin workflow
- `tests/README.md` - Comprehensive testing documentation

### Build & CI Files
- `Makefile` - Make targets for running tests easily
- `run-tests.sh` - Shell script alternative to Make for running tests
- `.github/workflows/test.yml` - GitHub Actions CI workflow
- `.luacheckrc` - Luacheck configuration for linting

### Documentation
- `CONTRIBUTING.md` - Contribution guidelines with testing requirements
- Updated `README.md` - Added testing section

## 🎯 Test Coverage

### Core Modules Tested

#### 1. Diff Module (`diff_spec.lua`)
- ✅ Hunk ID generation
- ✅ Change block ID creation
- ✅ Range and line comment key generation
- ✅ Change block detection (additions, deletions, multiple blocks)
- ✅ Source line mapping
- ✅ File icon handling
- ✅ File entry extraction
- ✅ Range comment filtering and sorting

#### 2. Git Module (`git_spec.lua`)
- ✅ Base branch configuration
- ✅ Base branch detection
- ✅ Git root detection
- ✅ Target branch detection
- ✅ Hunk loading for different modes
- ✅ Unified diff parsing
- ✅ Multi-file and multi-hunk parsing
- ✅ New file and deletion handling

#### 3. Plugin (`plugin_spec.lua`)
- ✅ Setup and configuration
- ✅ Command registration (HunkReview, HunkReviewRefresh, etc.)
- ✅ Public API exposure
- ✅ Buffer and filetype setup
- ✅ Highlight groups
- ✅ Reset functionality

#### 4. Export Module (`export_spec.lua`)
- ✅ Pretty JSON encoding
- ✅ Payload generation with metadata
- ✅ Comment filtering (only hunks with comments)
- ✅ Change block and range comment inclusion
- ✅ Clipboard text formatting
- ✅ Custom prompt support

#### 5. Tree Module (`tree_spec.lua`)
- ✅ File tree building from flat lists
- ✅ Nested directory handling
- ✅ Tree node rendering
- ✅ Directory collapsing/expanding
- ✅ File selection marking
- ✅ Change count display
- ✅ File ordering and sorting

#### 6. Health Check (`health_spec.lua`)
- ✅ Health check execution
- ✅ Git dependency verification
- ✅ Snacks.nvim dependency verification

#### 7. Integration Tests (`integration_spec.lua`)
- ✅ Full open/close workflow
- ✅ Navigation operations
- ✅ Comment operations
- ✅ Export operations
- ✅ File operations
- ✅ Tab navigation
- ✅ Multiple setup calls
- ✅ Command execution order
- ✅ Command line interface
- ✅ Buffer and window management

## 🚀 Running Tests

### Quick Start
```bash
# Run all tests
make test

# Or using the shell script
./run-tests.sh
```

### Specific Test Files
```bash
# Using Make
make test-file FILE=tests/diff_spec.lua

# Using shell script
./run-tests.sh -f tests/diff_spec.lua
```

### Interactive Mode
```bash
# Using Make
make test-interactive

# Using shell script
./run-tests.sh -i
```

### In Neovim
```vim
:PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }
```

## 🔄 Continuous Integration

Tests run automatically on:
- Every push to main branch
- Every pull request
- Against both Neovim stable and nightly versions

The CI workflow:
1. Sets up Neovim (stable and nightly)
2. Installs dependencies (plenary.nvim, snacks.nvim)
3. Runs full test suite
4. Runs luacheck linter

## 📊 Test Statistics

- **Total test files**: 8
- **Core module tests**: 6
- **Integration tests**: 1
- **Test cases**: 100+ individual test cases
- **Coverage areas**: 
  - Git operations
  - Diff parsing
  - UI rendering
  - Export functionality
  - Navigation
  - Commenting
  - Commands

## 🛡️ Regression Prevention

The test suite prevents regressions in:

1. **Plugin Display**
   - Buffer creation and properties
   - Filetype assignment
   - Highlight group definitions
   - Window layout integrity

2. **Command Functionality**
   - All 4 user commands work correctly
   - Commands handle edge cases gracefully
   - Commands can be called in any order

3. **Core Logic**
   - Diff parsing accuracy
   - Change block detection
   - Comment key uniqueness
   - Export format consistency

4. **User Workflows**
   - Opening and closing review
   - Navigation between hunks and changes
   - Adding and deleting comments
   - Exporting reviews
   - Filtering files

## 🔧 For Contributors

When contributing:

1. **Run tests before submitting PR**
   ```bash
   make test
   ```

2. **Add tests for new features**
   - Create tests in appropriate `*_spec.lua` file
   - Follow existing test patterns
   - Use descriptive test names

3. **Verify linting**
   ```bash
   luacheck lua/ plugin/
   ```

4. **Check CI passes**
   - GitHub Actions will run automatically
   - Fix any failures before merging

## 📝 Notes

- Some tests may skip if not in a git repository (expected behavior)
- Tests use headless Neovim for CI/automated runs
- Interactive mode useful for debugging test failures
- All tests are non-destructive and safe to run repeatedly

## 🎯 Next Steps

Potential test improvements:
- [ ] Add performance benchmarks
- [ ] Test LSP integration (peek functionality)
- [ ] Test snacks.nvim picker integration
- [ ] Add test coverage reporting
- [ ] Mock git operations for fully isolated unit tests

---

For detailed testing documentation, see [tests/README.md](tests/README.md).
