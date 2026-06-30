# Contributing to hunk-review.nvim

Thank you for your interest in contributing to hunk-review.nvim! This document provides guidelines and instructions for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/hunk-review.nvim.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Run tests to ensure nothing broke
6. Commit your changes
7. Push to your fork
8. Open a pull request

## Development Setup

### Prerequisites

- Neovim 0.9.0 or later
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for testing)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (required dependency)
- Git

### Testing

**Always run tests before submitting a pull request.**

```bash
# Run all tests
make test

# Or use the shell script
./run-tests.sh

# Run a specific test file
make test-file FILE=tests/diff_spec.lua
./run-tests.sh -f tests/diff_spec.lua

# Run tests interactively
make test-interactive
./run-tests.sh -i
```

### Writing Tests

When adding new features or fixing bugs:

1. Add tests for your changes in the appropriate `tests/*_spec.lua` file
2. If adding a new module, create a new test file
3. Ensure all tests pass before submitting

Test files use the [busted](https://olivinelabs.com/busted/) framework via plenary.nvim.

Example test:

```lua
describe("your feature", function()
  it("does something specific", function()
    local result = your_function()
    assert.are.equal(expected, result)
  end)
end)
```

See [tests/README.md](tests/README.md) for more details.

## Code Style

- Follow the existing code style in the project
- Use 2 spaces for indentation
- Keep functions focused and single-purpose
- Add comments for complex logic
- Use descriptive variable names

### Linting

The project uses [luacheck](https://github.com/mpeterv/luacheck) for linting:

```bash
# Install luacheck
luarocks install luacheck

# Run linter
luacheck lua/ plugin/
```

Configuration is in `.luacheckrc`.

## Pull Request Guidelines

### Before Submitting

- [ ] All tests pass (`make test`)
- [ ] Code passes linting (`luacheck lua/ plugin/`)
- [ ] New features have tests
- [ ] Bug fixes have regression tests
- [ ] Documentation is updated if needed
- [ ] Commit messages are clear and descriptive

### PR Description

Please include in your PR description:

- **What** changed
- **Why** it changed
- **How** to test the changes
- Any **breaking changes** or migration notes
- Screenshots/recordings for UI changes

### Commit Messages

Use clear, descriptive commit messages:

- Start with a verb in present tense: "Add", "Fix", "Update", "Remove"
- Be specific: "Fix hunk navigation when no changes exist" vs "Fix bug"
- Reference issues when applicable: "Fix #123: Handle empty diffs"

Good examples:
- `Add support for custom diff context`
- `Fix comment deletion in line mode`
- `Update README with testing instructions`
- `Remove deprecated export function`

## Reporting Issues

When reporting bugs, please include:

- Neovim version (`nvim --version`)
- Plugin version or commit hash
- Steps to reproduce
- Expected vs actual behavior
- Error messages (if any)
- Minimal config to reproduce (if applicable)

## Feature Requests

Feature requests are welcome! Please:

- Search existing issues first to avoid duplicates
- Describe the use case and problem it solves
- Provide examples of how the feature would be used
- Consider whether it fits the plugin's scope and philosophy

## Questions

Have questions? Feel free to:

- Open a discussion on GitHub
- Open an issue with the "question" label
- Check existing documentation and issues first

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see LICENSE file).

## Thank You!

Your contributions make this plugin better for everyone. Thank you for taking the time to contribute! 🎉
