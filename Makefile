.PHONY: test test-file test-interactive clean help

# Run all tests in headless mode
test:
	@echo "Running all tests..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

# Run a specific test file (usage: make test-file FILE=tests/diff_spec.lua)
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter required. Usage: make test-file FILE=tests/diff_spec.lua"; \
		exit 1; \
	fi
	@echo "Running tests in $(FILE)..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"

# Run tests interactively in Neovim
test-interactive:
	@echo "Opening Neovim with test runner..."
	@nvim -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

# Clean up any test artifacts
clean:
	@echo "Cleaning test artifacts..."
	@find . -name "*.lua~" -delete
	@find . -name ".DS_Store" -delete

# Show help
help:
	@echo "Available targets:"
	@echo "  make test              - Run all tests in headless mode"
	@echo "  make test-file FILE=.. - Run a specific test file"
	@echo "  make test-interactive  - Run tests in interactive Neovim session"
	@echo "  make clean             - Remove test artifacts"
	@echo "  make help              - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make test"
	@echo "  make test-file FILE=tests/diff_spec.lua"
