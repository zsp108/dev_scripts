# Makefile for dev_scripts project
# This project contains installation, management and uninstall scripts for development tools & servers

# Variables
SHELL := /bin/bash
SCRIPTS_DIR := scripts

# Scripts definition
GO_INSTALL_SCRIPT          := $(SCRIPTS_DIR)/go_install.sh
NODEJS_INSTALL_SCRIPT      := $(SCRIPTS_DIR)/nodejs_install.sh
GITLINT_INSTALL_SCRIPT     := $(SCRIPTS_DIR)/gitlint_install.sh
GIT_INSTALL_SCRIPT         := $(SCRIPTS_DIR)/git_install.sh
DOCKER_INSTALL_SCRIPT      := $(SCRIPTS_DIR)/docker_install.sh
FILEBROWSER_INSTALL_SCRIPT := $(SCRIPTS_DIR)/filebrowser_install.sh
SAMBA_INSTALL_SCRIPT       := $(SCRIPTS_DIR)/samba_install.sh
NGINX_DOWNLOAD_SCRIPT      := $(SCRIPTS_DIR)/nginx_download_install.sh
DERPER_INSTALL_SCRIPT      := $(SCRIPTS_DIR)/derper_install.sh
PROTOBUF_INSTALL_SCRIPT    := $(SCRIPTS_DIR)/protobuf_install.sh
VIM_GO_INSTALL_SCRIPT      := $(SCRIPTS_DIR)/vim_go_install.sh
ENV_INIT_SCRIPT            := $(SCRIPTS_DIR)/env_init.sh

# Default versions and arguments
GO_VERSION   ?= 1.25.3
GIT_VERSION  ?= 2.42.0
PB_VERSION   ?= v25.3
GEN_GO_VER   ?= v1.5.2

# Gitlint configuration
GITLINT_REGEX := ^(feat|fix|docs|style|refactor|test|chore|ci|perf)(\([a-zA-Z0-9-_/]+\))?:.+

# Colors for output
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
NC     := \033[0m # No Color

.PHONY: help install setup check clean lint test docs \
        install-go uninstall-go list-go-versions \
        install-nodejs uninstall-nodejs list-nodejs-versions \
        install-git uninstall-git list-git-versions \
        install-docker uninstall-docker \
        install-gitlint uninstall-gitlint \
        install-protobuf uninstall-protobuf list-protobuf-versions \
        install-vim-go uninstall-vim-go \
        init-env clean-env \
        install-filebrowser uninstall-filebrowser \
        install-samba uninstall-samba \
        install-nginx-download uninstall-nginx-download \
        install-derper uninstall-derper \
        gitlint gitlint-all pre-commit commit-msg install-hooks remove-hooks list-scripts info version show-regex

# Default target
help: ## Show this help message
	@printf "$(BLUE)========================================================$(NC)\n"
	@printf "$(BLUE)             Dev Scripts Makefile Management            $(NC)\n"
	@printf "$(BLUE)========================================================$(NC)\n\n"
	@printf "$(CYAN)Available targets:$(NC)\n"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-25s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n$(CYAN)Usage Examples:$(NC)\n"
	@printf "  make list-go-versions                  # List available Go versions\n"
	@printf "  make install-go [GO_VERSION=1.25.3]    # Install Go\n"
	@printf "  make uninstall-go                      # Uninstall Go\n"
	@printf "  make install-filebrowser               # Install FileBrowser with multi-user isolation\n"
	@printf "  make check                             # Check all installed tools & services\n"
	@printf "  make test                              # Validate syntax of all shell scripts\n"

# ========================================================
# 1. 基础开发环境工具 (Dev Tools)
# ========================================================
install: install-go install-nodejs install-git install-docker install-gitlint ## Install all basic development tools

setup: install ## Complete development environment setup
	@printf "$(GREEN)✓ Development environment setup complete!$(NC)\n"

list-go-versions: ## List available Go versions from official source
	@if [ -f $(GO_INSTALL_SCRIPT) ]; then \
		./$(GO_INSTALL_SCRIPT) list; \
	else \
		printf "$(RED)Error: Go install script not found at $(GO_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-go: ## Install Go programming language (override via GO_VERSION=x.y.z)
	@printf "$(BLUE)Installing Go $(GO_VERSION)...$(NC)\n"
	@if [ -f $(GO_INSTALL_SCRIPT) ]; then \
		chmod +x $(GO_INSTALL_SCRIPT); \
		sudo ./$(GO_INSTALL_SCRIPT) $(GO_VERSION); \
	else \
		printf "$(RED)Error: Go install script not found at $(GO_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-go: ## Uninstall Go environment and clean PATH configuration
	@printf "$(YELLOW)Uninstalling Go...$(NC)\n"
	@if [ -f $(GO_INSTALL_SCRIPT) ]; then \
		chmod +x $(GO_INSTALL_SCRIPT); \
		sudo ./$(GO_INSTALL_SCRIPT) uninstall $(GO_VERSION); \
	else \
		printf "$(RED)Error: Go script not found at $(GO_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

list-nodejs-versions: ## List Node.js LTS and current releases
	@if [ -f $(NODEJS_INSTALL_SCRIPT) ]; then \
		./$(NODEJS_INSTALL_SCRIPT) list; \
	else \
		printf "$(RED)Error: Node.js script not found at $(NODEJS_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-nodejs: ## Install Node.js LTS and npm
	@printf "$(BLUE)Installing Node.js...$(NC)\n"
	@if [ -f $(NODEJS_INSTALL_SCRIPT) ]; then \
		chmod +x $(NODEJS_INSTALL_SCRIPT); \
		sudo ./$(NODEJS_INSTALL_SCRIPT); \
	else \
		printf "$(RED)Error: Node.js install script not found at $(NODEJS_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-nodejs: ## Uninstall Node.js and clean packages
	@printf "$(YELLOW)Uninstalling Node.js...$(NC)\n"
	@if [ -f $(NODEJS_INSTALL_SCRIPT) ]; then \
		chmod +x $(NODEJS_INSTALL_SCRIPT); \
		sudo ./$(NODEJS_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: Node.js script not found at $(NODEJS_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

list-git-versions: ## List available Git release versions
	@if [ -f $(GIT_INSTALL_SCRIPT) ]; then \
		./$(GIT_INSTALL_SCRIPT) list; \
	else \
		printf "$(RED)Error: Git script not found at $(GIT_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-git: ## Compile and install Git (override via GIT_VERSION=x.y.z)
	@printf "$(BLUE)Installing Git $(GIT_VERSION)...$(NC)\n"
	@if [ -f $(GIT_INSTALL_SCRIPT) ]; then \
		chmod +x $(GIT_INSTALL_SCRIPT); \
		sudo ./$(GIT_INSTALL_SCRIPT) $(GIT_VERSION); \
	else \
		printf "$(RED)Error: Git install script not found at $(GIT_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-git: ## Uninstall compiled Git and clean PATH
	@printf "$(YELLOW)Uninstalling Git...$(NC)\n"
	@if [ -f $(GIT_INSTALL_SCRIPT) ]; then \
		chmod +x $(GIT_INSTALL_SCRIPT); \
		sudo ./$(GIT_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: Git script not found at $(GIT_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

list-protobuf-versions: ## List recommended Protobuf and protoc-gen-go versions
	@if [ -f $(PROTOBUF_INSTALL_SCRIPT) ]; then \
		./$(PROTOBUF_INSTALL_SCRIPT) list; \
	else \
		printf "$(RED)Error: Protobuf script not found at $(PROTOBUF_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-protobuf: ## Install Protobuf compiler and protoc-gen-go
	@printf "$(BLUE)Installing Protobuf $(PB_VERSION)...$(NC)\n"
	@if [ -f $(PROTOBUF_INSTALL_SCRIPT) ]; then \
		chmod +x $(PROTOBUF_INSTALL_SCRIPT); \
		./$(PROTOBUF_INSTALL_SCRIPT) $(PB_VERSION) $(GEN_GO_VER); \
	else \
		printf "$(RED)Error: Protobuf install script not found at $(PROTOBUF_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-protobuf: ## Uninstall Protobuf compiler, libraries and protoc-gen-go
	@printf "$(YELLOW)Uninstalling Protobuf...$(NC)\n"
	@if [ -f $(PROTOBUF_INSTALL_SCRIPT) ]; then \
		chmod +x $(PROTOBUF_INSTALL_SCRIPT); \
		./$(PROTOBUF_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: Protobuf script not found at $(PROTOBUF_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-vim-go: ## Install vim-go plugin and Go IDE development tools
	@printf "$(BLUE)Installing vim-go IDE environment...$(NC)\n"
	@if [ -f $(VIM_GO_INSTALL_SCRIPT) ]; then \
		chmod +x $(VIM_GO_INSTALL_SCRIPT); \
		./$(VIM_GO_INSTALL_SCRIPT); \
	else \
		printf "$(RED)Error: vim-go install script not found at $(VIM_GO_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-vim-go: ## Uninstall vim-go plugin and clean .vimrc
	@printf "$(YELLOW)Uninstalling vim-go...$(NC)\n"
	@if [ -f $(VIM_GO_INSTALL_SCRIPT) ]; then \
		chmod +x $(VIM_GO_INSTALL_SCRIPT); \
		./$(VIM_GO_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: vim-go script not found at $(VIM_GO_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

init-env: ## Initialize shell environment (workspace, charset and proxy functions)
	@printf "$(BLUE)Initializing environment...$(NC)\n"
	@if [ -f $(ENV_INIT_SCRIPT) ]; then \
		chmod +x $(ENV_INIT_SCRIPT); \
		./$(ENV_INIT_SCRIPT) env; \
	else \
		printf "$(RED)Error: env_init script not found at $(ENV_INIT_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

clean-env: ## Clean environment and proxy settings from .bashrc
	@printf "$(YELLOW)Cleaning environment settings...$(NC)\n"
	@if [ -f $(ENV_INIT_SCRIPT) ]; then \
		chmod +x $(ENV_INIT_SCRIPT); \
		./$(ENV_INIT_SCRIPT) clean; \
	else \
		printf "$(RED)Error: env_init script not found at $(ENV_INIT_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

# ========================================================
# 2. 服务与网络中间件 (Services & Servers)
# ========================================================
install-filebrowser: ## Install & configure FileBrowser web file manager
	@printf "$(BLUE)Starting FileBrowser installation wizard...$(NC)\n"
	@if [ -f $(FILEBROWSER_INSTALL_SCRIPT) ]; then \
		chmod +x $(FILEBROWSER_INSTALL_SCRIPT); \
		sudo ./$(FILEBROWSER_INSTALL_SCRIPT) install; \
	else \
		printf "$(RED)Error: FileBrowser script not found at $(FILEBROWSER_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-filebrowser: ## Uninstall FileBrowser service and optional database
	@printf "$(YELLOW)Uninstalling FileBrowser...$(NC)\n"
	@if [ -f $(FILEBROWSER_INSTALL_SCRIPT) ]; then \
		chmod +x $(FILEBROWSER_INSTALL_SCRIPT); \
		sudo ./$(FILEBROWSER_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: FileBrowser script not found at $(FILEBROWSER_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-samba: ## Install & configure Samba multi-user file sharing server
	@printf "$(BLUE)Starting Samba installation wizard...$(NC)\n"
	@if [ -f $(SAMBA_INSTALL_SCRIPT) ]; then \
		chmod +x $(SAMBA_INSTALL_SCRIPT); \
		sudo ./$(SAMBA_INSTALL_SCRIPT) install; \
	else \
		printf "$(RED)Error: Samba script not found at $(SAMBA_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-samba: ## Uninstall Samba service and configurations
	@printf "$(YELLOW)Uninstalling Samba...$(NC)\n"
	@if [ -f $(SAMBA_INSTALL_SCRIPT) ]; then \
		chmod +x $(SAMBA_INSTALL_SCRIPT); \
		sudo ./$(SAMBA_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: Samba script not found at $(SAMBA_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-nginx-download: ## Deploy Nginx HTTP file download server and index watcher
	@printf "$(BLUE)Deploying Nginx file download server...$(NC)\n"
	@if [ -f $(NGINX_DOWNLOAD_SCRIPT) ]; then \
		chmod +x $(NGINX_DOWNLOAD_SCRIPT); \
		sudo ./$(NGINX_DOWNLOAD_SCRIPT); \
	else \
		printf "$(RED)Error: Nginx download script not found at $(NGINX_DOWNLOAD_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-nginx-download: ## Uninstall Nginx download site and stop watcher/downloader services
	@printf "$(YELLOW)Uninstalling Nginx download server...$(NC)\n"
	@if [ -f $(NGINX_DOWNLOAD_SCRIPT) ]; then \
		chmod +x $(NGINX_DOWNLOAD_SCRIPT); \
		sudo ./$(NGINX_DOWNLOAD_SCRIPT) --uninstall; \
	else \
		printf "$(RED)Error: Nginx download script not found at $(NGINX_DOWNLOAD_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

install-derper: ## Install Tailscale DERP custom relay server
	@printf "$(BLUE)Installing Tailscale DERP server...$(NC)\n"
	@if [ -f $(DERPER_INSTALL_SCRIPT) ]; then \
		chmod +x $(DERPER_INSTALL_SCRIPT); \
		sudo ./$(DERPER_INSTALL_SCRIPT); \
	else \
		printf "$(RED)Error: DERP script not found at $(DERPER_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-derper: ## Stop and uninstall Tailscale DERP service
	@printf "$(YELLOW)Uninstalling Tailscale DERP server...$(NC)\n"
	@if [ -f $(DERPER_INSTALL_SCRIPT) ]; then \
		chmod +x $(DERPER_INSTALL_SCRIPT); \
		sudo ./$(DERPER_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: DERP script not found at $(DERPER_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

# ========================================================
# 3. 容器 (Docker)
# ========================================================
install-docker: ## Install Docker Engine
	@printf "$(BLUE)Installing Docker...$(NC)\n"
	@if [ -f $(DOCKER_INSTALL_SCRIPT) ]; then \
		chmod +x $(DOCKER_INSTALL_SCRIPT); \
		sudo ./$(DOCKER_INSTALL_SCRIPT); \
	else \
		printf "$(RED)Error: Docker install script not found at $(DOCKER_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-docker: ## Completely uninstall Docker and container runtimes
	@printf "$(YELLOW)Uninstalling Docker...$(NC)\n"
	@if [ -f $(DOCKER_INSTALL_SCRIPT) ]; then \
		chmod +x $(DOCKER_INSTALL_SCRIPT); \
		sudo ./$(DOCKER_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: Docker script not found at $(DOCKER_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

# ========================================================
# 4. 代码质量与 Git 钩子 (Quality & Git Hooks)
# ========================================================
install-gitlint: ## Install gitlint for commit message validation
	@printf "$(BLUE)Installing gitlint...$(NC)\n"
	@if [ -f $(GITLINT_INSTALL_SCRIPT) ]; then \
		chmod +x $(GITLINT_INSTALL_SCRIPT); \
		./$(GITLINT_INSTALL_SCRIPT); \
	else \
		printf "$(RED)Error: gitlint install script not found at $(GITLINT_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

uninstall-gitlint: ## Uninstall gitlint tool
	@printf "$(YELLOW)Uninstalling gitlint...$(NC)\n"
	@if [ -f $(GITLINT_INSTALL_SCRIPT) ]; then \
		chmod +x $(GITLINT_INSTALL_SCRIPT); \
		./$(GITLINT_INSTALL_SCRIPT) uninstall; \
	else \
		printf "$(RED)Error: gitlint script not found at $(GITLINT_INSTALL_SCRIPT)$(NC)\n"; \
		exit 1; \
	fi

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

pre-commit: ## Install pre-commit hook for code quality checks
	@printf "$(BLUE)Setting up pre-commit hook...$(NC)\n"
	@echo "#!/bin/bash" > .git/hooks/pre-commit
	@echo "# Pre-commit hook for code quality checks" >> .git/hooks/pre-commit
	@echo "printf "\033[0;34mRunning pre-commit checks...\033[0m\\n"" >> .git/hooks/pre-commit
	@echo "make gitlint || exit 1" >> .git/hooks/pre-commit
	@echo "printf "\033[0;32m✓ Pre-commit checks passed!\033[0m\\n"" >> .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@printf "$(GREEN)✓ Pre-commit hook installed$(NC)\n"

commit-msg: ## Install commit-msg hook for commit message validation
	@printf "$(BLUE)Setting up commit-msg hook...$(NC)\n"
	@if [ -f "$(SCRIPTS_DIR)/templates/commit-msg.sample" ]; then \
		cp "$(SCRIPTS_DIR)/templates/commit-msg.sample" .git/hooks/commit-msg; \
		chmod +x .git/hooks/commit-msg; \
		printf "$(GREEN)✓ Commit-msg hook installed from template$(NC)\n"; \
	else \
		printf "$(RED)Error: Commit-msg template not found at $(SCRIPTS_DIR)/templates/commit-msg.sample$(NC)\n"; \
		exit 1; \
	fi

install-hooks: pre-commit commit-msg ## Install all git hooks (pre-commit and commit-msg)
	@printf "$(GREEN)✓ All git hooks installed successfully!$(NC)\n"

remove-hooks: ## Remove installed git hooks
	@printf "$(BLUE)Removing git hooks...$(NC)\n"
	@rm -f .git/hooks/pre-commit .git/hooks/commit-msg
	@printf "$(GREEN)✓ Git hooks removed$(NC)\n"

# ========================================================
# 5. 检测、测试与工具 (Check, Test & Utilities)
# ========================================================
check: ## Check status of all development tools and services
	@printf "$(BLUE)========================================================$(NC)\n"
	@printf "$(BLUE)           Development Tools & Services Status          $(NC)\n"
	@printf "$(BLUE)========================================================$(NC)\n"
	@printf "%-15s: " "Go"
	@if command -v go >/dev/null 2>&1; then \
		printf "$(GREEN)✓ $$(go version)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "%-15s: " "Node.js"
	@if command -v node >/dev/null 2>&1; then \
		printf "$(GREEN)✓ $$(node -v)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "%-15s: " "Git"
	@if command -v git >/dev/null 2>&1; then \
		printf "$(GREEN)✓ $$(git --version)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "%-15s: " "Docker"
	@if command -v docker >/dev/null 2>&1; then \
		printf "$(GREEN)✓ $$(docker --version)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "%-15s: " "Protobuf"
	@if command -v protoc >/dev/null 2>&1; then \
		printf "$(GREEN)✓ $$(protoc --version)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "%-15s: " "FileBrowser"
	@if [ -f /usr/local/bin/filebrowser ]; then \
		printf "$(GREEN)✓ Installed (/usr/local/bin/filebrowser)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "%-15s: " "Samba"
	@if command -v smbd >/dev/null 2>&1; then \
		printf "$(GREEN)✓ Installed $$(smbd -V)$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "%-15s: " "Gitlint"
	@if command -v gitlint >/dev/null 2>&1; then \
		printf "$(GREEN)✓ Installed$(NC)\n"; \
	else \
		printf "$(RED)✗ Not installed$(NC)\n"; \
	fi
	@printf "$(BLUE)========================================================$(NC)\n"

lint: ## Lint all shell scripts with shellcheck
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

test: ## Test syntax of all shell scripts (bash -n)
	@printf "$(BLUE)Testing syntax of all shell scripts...$(NC)\n"
	@for script in $(SCRIPTS_DIR)/*.sh; do \
		if [ -f "$$script" ]; then \
			printf "  Checking $$script... "; \
			bash -n "$$script" || { \
				printf "$(RED)FAILED$(NC)\n"; \
				exit 1; \
			}; \
			printf "$(GREEN)OK$(NC)\n"; \
		fi; \
	done
	@printf "$(GREEN)✓ All scripts passed syntax check!$(NC)\n"

list-scripts: ## List all available scripts in repository
	@printf "$(BLUE)Available scripts in $(SCRIPTS_DIR):$(NC)\n"
	@for script in $(SCRIPTS_DIR)/*.sh $(SCRIPTS_DIR)/tools/*.sh; do \
		if [ -f "$$script" ]; then \
			printf "  $(GREEN)%-35s$(NC)\n" "$$script"; \
		fi; \
	done

clean: ## Clean temporary files and logs
	@printf "$(BLUE)Cleaning temporary files...$(NC)\n"
	@rm -rf logs 2>/dev/null || true
	@find . -name "*.log" -type f -delete 2>/dev/null || true
	@find . -name "*.tmp" -type f -delete 2>/dev/null || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@printf "$(GREEN)✓ Cleanup complete$(NC)\n"

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

version: ## Show version information
	@printf "$(BLUE)Dev Scripts Version: 2.0.0$(NC)\n"
	@$(MAKE) check

show-regex: ## Show the gitlint regex pattern
	@printf "$(BLUE)Gitlint Subject Regex Pattern:$(NC)\n"
	@printf "$(GITLINT_REGEX)\n\n"
	@printf "$(YELLOW)Examples:$(NC)\n"
	@printf "  feat: add new feature\n"
	@printf "  fix(ui): resolve button alignment issue\n"
	@printf "  docs: update installation guide\n"
	@printf "  refactor(auth): simplify login flow\n"
