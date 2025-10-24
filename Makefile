# Makefile for dev_scripts project
# This project contains installation and setup scripts for development tools

# Variables
SHELL := /bin/bash
SCRIPTS_DIR := scripts
GO_INSTALL_SCRIPT := $(SCRIPTS_DIR)/go_install.sh
GITLINT_INSTALL_SCRIPT := $(SCRIPTS_DIR)/gitlint_install.sh
GITLINT_BINARY := $(SCRIPTS_DIR)/gitlint_ub_x86-64
GO_VERSION ?= 1.23.2

# Gitlint configuration
GITLINT_REGEX := ^(feat|fix|docs|style|refactor|test|chore|ci|perf)(\([a-zA-Z0-9-_/]+\))?:.+

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

.PHONY: help install install-go install-gitlint setup gitlint check clean lint test docs pre-commit commit-msg install-hooks remove-hooks

# Default target
help: ## Show this help message
	@printf "$(BLUE)Dev Scripts Makefile$(NC)\n"
	@printf "$(BLUE)=====================$(NC)\n\n"
	@printf "$(GREEN)Available targets:$(NC)\n"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n$(GREEN)Examples:$(NC)\n"
	@printf "  make install          # Install all tools\n"
	@printf "  make install-go       # Install Go $(GO_VERSION)\n"
	@printf "  make gitlint          # Validate commit messages\n"
	@printf "  make check            # Check installations\n"

# Installation targets
install: install-go install-gitlint ## Install all development tools

install-go: ## Install Go programming language
	@printf "$(BLUE)Installing Go $(GO_VERSION)...$(NC)\n"
	@if [ -f $(GO_INSTALL_SCRIPT) ]; then \
		chmod +x $(GO_INSTALL_SCRIPT); \
		./$(GO_INSTALL_SCRIPT) $(GO_VERSION); \
	else \
		printf "$(RED)Error: Go install script not found at $(GO_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-gitlint: ## Install gitlint for commit message validation
	@printf "$(BLUE)Installing gitlint...$(NC)\n"
	@if [ -f $(GITLINT_INSTALL_SCRIPT) ]; then \
		chmod +x $(GITLINT_INSTALL_SCRIPT); \
		./$(GITLINT_INSTALL_SCRIPT); \
	else \
		printf "$(RED)Error: gitlint install script not found at $(GITLINT_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

# Setup targets
setup: install ## Complete development environment setup
	@printf "$(GREEN)✓ Development environment setup complete!$(NC)\n"

# Validation targets
gitlint: ## Run gitlint on current commit message
	@printf "$(BLUE)Validating commit message with gitlint...$(NC)\n"
	@if command -v gitlint >/dev/null 2>&1; then \
		if [ -n "$(shell git log -1 --pretty=%B 2>/dev/null)" ]; then \
			gitlint --subject-regex "$(GITLINT_REGEX)" || { \
				printf "$(RED)Commit message validation failed!$(NC)\n"; \
				printf "$(YELLOW)Expected format: <type>(<scope>): <description>$(NC)\n"; \
				printf "$(YELLOW)Types: feat, fix, docs, style, refactor, test, chore, ci, perf$(NC)\n"; \
				exit 1; \
			}; \
			printf "$(GREEN)✓ Commit message validation passed!$(NC)\n"; \
		else \
			printf "$(YELLOW)No commit messages to validate$(NC)\n"; \
		fi; \
	else \
		printf "$(RED)Error: gitlint is not installed. Run 'make install-gitlint' first.$(NC)\n"; \
		exit 1; \
	fi

gitlint-all: ## Run gitlint on all commit messages in the repo
	@printf "$(BLUE)Validating all commit messages...$(NC)\n"
	@if command -v gitlint >/dev/null 2>&1; then \
		git log --oneline --format="%H %s" | while read commit; do \
			echo "Validating: $$commit"; \
			echo "$$commit" | cut -d' ' -f2- | gitlint --subject-regex "$(GITLINT_REGEX)" || { \
				printf "$(RED)Validation failed for commit: $$commit$(NC)\n"; \
				exit 1; \
			}; \
		done; \
		printf "$(GREEN)✓ All commit messages passed validation!$(NC)\n"; \
	else \
		printf "$(RED)Error: gitlint is not installed. Run 'make install-gitlint' first.$(NC)\n"; \
		exit 1; \
	fi

check: ## Check if development tools are properly installed
	@printf "$(BLUE)Checking development tools...$(NC)\n"
	@printf "Go: "
	@if command -v go >/dev/null 2>&1; then \
		printf "$(GREEN)✓ Installed $(shell go version)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not found$(NC)\n"; \
	fi
	@printf "Gitlint: "
	@if command -v gitlint >/dev/null 2>&1; then \
		printf "$(GREEN)✓ Installed$(NC)\n"; \
	else \
		printf "$(RED)✗ Not found$(NC)\n"; \
	fi
	@printf "Git: "
	@if command -v git >/dev/null 2>&1; then \
		printf "$(GREEN)✓ Installed $(shell git --version)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not found$(NC)\n"; \
	fi

# Development targets
lint: ## Lint shell scripts
	@printf "$(BLUE)Linting shell scripts...$(NC)\n"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPTS_DIR)/*.sh || { \
			printf "$(RED)Shellcheck found issues$(NC)\n"; \
			exit 1; \
		}; \
		printf "$(GREEN)✓ Shell scripts passed linting$(NC)\n"; \
	else \
		printf "$(YELLOW)shellcheck not installed. Install with: apt install shellcheck$(NC)\n"; \
	fi

test: ## Test the installation scripts
	@printf "$(BLUE)Testing installation scripts...$(NC)\n"
	@for script in $(SCRIPTS_DIR)/*.sh; do \
		if [ -f "$$script" ]; then \
			echo "Testing syntax of $$script..."; \
			bash -n "$$script" || { \
				printf "$(RED)Syntax error in $$script$(NC)\n"; \
				exit 1; \
			}; \
		fi; \
	done
	@printf "$(GREEN)✓ All scripts passed syntax check$(NC)\n"

# Documentation targets
docs: ## Show documentation
	@printf "$(BLUE)Project Documentation:$(NC)\n\n"
	@if [ -f README.md ]; then \
		printf "$(YELLOW)README.md:$(NC)\n"; \
		cat README.md; \
		printf "\n"; \
	fi
	@if [ -f docs/git-commit-guide.md ]; then \
		printf "$(YELLOW)Git Commit Guidelines:$(NC)\n"; \
		cat docs/git-commit-guide.md; \
	fi

# Utility targets
clean: ## Clean temporary files and logs
	@printf "$(BLUE)Cleaning temporary files...$(NC)\n"
	@find . -name "*.log" -type f -delete 2>/dev/null || true
	@find . -name "*.tmp" -type f -delete 2>/dev/null || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@printf "$(GREEN)✓ Cleanup complete$(NC)\n"

version: ## Show version information
	@printf "$(BLUE)Dev Scripts Version Information$(NC)\n"
	@printf "Makefile: 1.0.0\n\n"
	@printf "$(YELLOW)Tool versions:$(NC)\n"
	@printf "Go: "
	@if command -v go >/dev/null 2>&1; then \
		go version; \
	else \
		printf "Not installed\n"; \
	fi
	@printf "Gitlint: "
	@if command -v gitlint >/dev/null 2>&1; then \
		gitlint --version 2>/dev/null || printf "Installed (version unknown)\n"; \
	else \
		printf "Not installed\n"; \
	fi
	@printf "Git: "
	@if command -v git >/dev/null 2>&1; then \
		git --version; \
	else \
		printf "Not installed\n"; \
	fi

# CI/CD helper targets
ci-setup: ## Setup for CI/CD environments
	@printf "$(BLUE)Setting up CI/CD environment...$(NC)\n"
	@mkdir -p ~/.local/bin
	@echo 'export PATH=$$HOME/.local/bin:$$PATH' >> ~/.bashrc
	@export PATH=$$HOME/.local/bin:$$PATH

pre-commit: ## Install pre-commit hook for code quality checks
	@printf "$(BLUE)Setting up pre-commit hook...$(NC)\n"
	@echo "#!/bin/bash" > .git/hooks/pre-commit
	@echo "# Pre-commit hook for code quality checks" >> .git/hooks/pre-commit
	@echo "printf \"\033[0;34mRunning pre-commit checks...\033[0m\\n\"" >> .git/hooks/pre-commit
	@echo "make gitlint || exit 1" >> .git/hooks/pre-commit
	@echo "printf \"\033[0;32m✓ Pre-commit checks passed!\033[0m\\n\"" >> .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@printf "$(GREEN)✓ Pre-commit hook installed$(NC)\n"

commit-msg: ## Install commit-msg hook for commit message validation
	@printf "$(BLUE)Setting up commit-msg hook...$(NC)\n"
	@echo "#!/bin/bash" > .git/hooks/commit-msg
	@echo "# Commit-msg hook for validating commit messages" >> .git/hooks/commit-msg
	@echo "commit_msg=\"\$$1\"" >> .git/hooks/commit-msg
	@echo "if [ -f \"\$$commit_msg\" ]; then" >> .git/hooks/commit-msg
	@echo "    message=\$$(cat \"\$$commit_msg\")" >> .git/hooks/commit-msg
	@echo "    printf \"\033[0;34mValidating commit message...\033[0m\\n\"" >> .git/hooks/commit-msg
	@echo "    echo \"\$$message\" | grep -qE \"$(GITLINT_REGEX)\" || {" >> .git/hooks/commit-msg
	@echo "        printf \"\033[0;31m✗ Commit message validation failed!\033[0m\\n\"" >> .git/hooks/commit-msg
	@echo "        printf \"\033[1;33mExpected format: <type>(<scope>): <description>\033[0m\\n\"" >> .git/hooks/commit-msg
	@echo "        printf \"\033[1;33mTypes: feat, fix, docs, style, refactor, test, chore, ci, perf\033[0m\\n\"" >> .git/hooks/commit-msg
	@echo "        printf \"\033[1;33mExamples: feat: add new feature\033[0m\\n\"" >> .git/hooks/commit-msg
	@echo "        printf \"\033[1;33m          fix(ui): resolve button alignment\033[0m\\n\"" >> .git/hooks/commit-msg
	@echo "        exit 1" >> .git/hooks/commit-msg
	@echo "    }" >> .git/hooks/commit-msg
	@echo "    printf \"\033[0;32m✓ Commit message validation passed!\033[0m\\n\"" >> .git/hooks/commit-msg
	@echo "fi" >> .git/hooks/commit-msg
	@chmod +x .git/hooks/commit-msg
	@printf "$(GREEN)✓ Commit-msg hook installed$(NC)\n"

install-hooks: pre-commit commit-msg ## Install all git hooks (pre-commit and commit-msg)
	@printf "$(GREEN)✓ All git hooks installed successfully!$(NC)\n"

remove-hooks: ## Remove installed git hooks
	@printf "$(BLUE)Removing git hooks...$(NC)\n"
	@rm -f .git/hooks/pre-commit .git/hooks/commit-msg
	@printf "$(GREEN)✓ Git hooks removed$(NC)\n"

# Custom gitlint regex helper
show-regex: ## Show the gitlint regex pattern
	@printf "$(BLUE)Gitlint Subject Regex Pattern:$(NC)\n"
	@printf "$(GITLINT_REGEX)\n\n"
	@printf "$(YELLOW)Examples:$(NC)\n"
	@printf "feat: add new feature\n"
	@printf "fix(ui): resolve button alignment issue\n"
	@printf "docs: update installation guide\n"
	@printf "refactor(auth): simplify login flow\n"