# Makefile for CentOS 7 Go Development Environment Docker Image
# Author: zsp108

# Variables
IMAGE_NAME = centos7-godev
CONTAINER_NAME = el7_mygodev
DEV_PATH = /path/workspace
GO_VERSION ?= 1.25.3
GIT_VERSION ?= 2.42.0
DOCKERFILE = Dockerfile
PACKAGES_DIR = packages
SCRIPTS_DIR = scripts
GO_INSTALL_SCRIPT := $(SCRIPTS_DIR)/go_install.sh
GIT_INSTALL_SCRIPT := $(SCRIPTS_DIR)/git_install.sh
GITLINT_INSTALL_SCRIPT := $(SCRIPTS_DIR)/gitlint_install.sh
SCRIPTS_SOURCE_DIR := ../../scripts
GIT_PACKAGE := $(PACKAGES_DIR)/git-$(GIT_VERSION).tar.gz
GO_PACKAGE := $(PACKAGES_DIR)/go$(GO_VERSION).linux-amd64.tar.gz

.PHONY: prepare
prepare:
	@echo "Preparing build environment..."
	@echo "Copying scripts from $(SCRIPTS_SOURCE_DIR) to $(SCRIPTS_DIR)..."
	@mkdir -p $(SCRIPTS_DIR)
	@cp $(SCRIPTS_SOURCE_DIR)/go_install.sh $(GO_INSTALL_SCRIPT)
	@cp $(SCRIPTS_SOURCE_DIR)/git_install.sh $(GIT_INSTALL_SCRIPT)
	@cp $(SCRIPTS_SOURCE_DIR)/gitlint_install.sh $(GITLINT_INSTALL_SCRIPT)
	@mkdir -p $(PACKAGES_DIR)
	@echo "Checking packages..."
	@if [ ! -f $(GIT_PACKAGE) ]; then \
		echo "Downloading Git $(GIT_VERSION)..."; \
		cd $(PACKAGES_DIR) && wget https://mirrors.edge.kernel.org/pub/software/scm/git/git-$(GIT_VERSION).tar.gz; \
	else \
		echo "Git package already exists: $(GIT_PACKAGE)"; \
	fi
	@if [ ! -f $(GO_PACKAGE) ]; then \
		echo "Downloading Go $(GO_VERSION)..."; \
		cd $(PACKAGES_DIR) && wget https://golang.google.cn/dl/go$(GO_VERSION).linux-amd64.tar.gz; \
	else \
		echo "Go package already exists: $(GO_PACKAGE)"; \
	fi
	@echo "Preparation completed successfully"

# Build Docker image using Dockerfile
.PHONY: build
build: prepare
	@echo "Building Docker image $(IMAGE_NAME)..."
	@echo "Go version: $(GO_VERSION)"
	@echo "Git version: $(GIT_VERSION)"
	docker build \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg GIT_VERSION=$(GIT_VERSION) \
		-t $(IMAGE_NAME):$(GO_VERSION)-git$(GIT_VERSION) \
		-t $(IMAGE_NAME):latest \
		-f $(DOCKERFILE) .
	@echo "Docker image built successfully:"
	@echo "  $(IMAGE_NAME):$(GO_VERSION)-git$(GIT_VERSION)"
	@echo "  $(IMAGE_NAME):latest"

# Build with custom tag
.PHONY: build-tag
build-tag: prepare
	@if [ -z "$(TAG)" ]; then \
		echo "Error: TAG parameter is required. Usage: make build-tag TAG=custom-tag"; \
		exit 1; \
	fi
	@echo "Building Docker image $(IMAGE_NAME) with tag $(TAG)..."
	docker build \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg GIT_VERSION=$(GIT_VERSION) \
		-t $(IMAGE_NAME):$(TAG) \
		-f $(DOCKERFILE) .
	@echo "Docker image built successfully: $(IMAGE_NAME):$(TAG)"

# Run container from built image
.PHONY: run
run:
	@echo "Running container $(CONTAINER_NAME) from image $(IMAGE_NAME)..."
	@mkdir -p $(DEV_PATH)
	docker run -itd --rm \
		--name $(CONTAINER_NAME) \
		-v $(DEV_PATH):$(DEV_PATH) \
		$(IMAGE_NAME):latest 

# Run container with custom tag
.PHONY: run-tag
run-tag:
	@if [ -z "$(TAG)" ]; then \
		echo "Error: TAG parameter is required. Usage: make run-tag TAG=custom-tag"; \
		exit 1; \
	fi
	@echo "Running container $(CONTAINER_NAME) from image $(IMAGE_NAME):$(TAG)..."
	@mkdir -p $(DEV_PATH)
	docker run -itd --rm \
		--name $(CONTAINER_NAME) \
		-v $(DEV_PATH):$(DEV_PATH) \
		$(IMAGE_NAME):$(TAG)

# Run container interactively (for immediate shell access)
.PHONY: shell
shell:
	@echo "Running interactive shell in container $(CONTAINER_NAME)..."
	@mkdir -p $(HOME)/workspace
	docker run -it --rm \
		--name $(CONTAINER_NAME)-shell \
		-v $(HOME)/workspace:/root/workspace \
		$(IMAGE_NAME):latest \
		/bin/bash

# Enter running container
.PHONY: exec
exec:
	@if ! docker ps --format "table {{.Names}}" | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "Error: Container $(CONTAINER_NAME) is not running. Please start it first with 'make run' or 'make run-tag'"; \
		exit 1; \
	fi
	@echo "Entering running container $(CONTAINER_NAME)..."
	docker exec -it $(CONTAINER_NAME) /bin/bash

# Push image to registry
.PHONY: push
push:
	@echo "Pushing image $(IMAGE_NAME):$(GO_VERSION)-git$(GIT_VERSION) to registry..."
	docker push $(IMAGE_NAME):$(GO_VERSION)-git$(GIT_VERSION)
	@echo "Pushing image $(IMAGE_NAME):latest to registry..."
	docker push $(IMAGE_NAME):latest

# Clean up built images
.PHONY: clean
clean:
	@echo "Cleaning up Docker images and containers..."
	# Stop and remove any running containers using our image
	@docker ps -q --filter "ancestor=$(IMAGE_NAME):latest" | xargs -r docker stop
	@docker ps -aq --filter "ancestor=$(IMAGE_NAME):latest" | xargs -r docker rm
	# Stop and remove containers by name
	@docker ps -q --filter "name=$(CONTAINER_NAME)" | xargs -r docker stop
	@docker ps -aq --filter "name=$(CONTAINER_NAME)" | xargs -r docker rm
	# Remove images
	@docker images $(IMAGE_NAME) -q | xargs -r docker rmi -f
	@echo "Cleanup completed"

# Show image information
.PHONY: images
images:
	@echo "Available $(IMAGE_NAME) images:"
	@docker images $(IMAGE_NAME)

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  prepare     - Prepare build environment (download packages and copy scripts)"
	@echo "  build       - Build Docker image using Dockerfile"
	@echo "  build-tag   - Build Docker image with custom tag (use TAG=custom-tag)"
	@echo "  run         - Run container from latest image (detached mode)"
	@echo "  run-tag     - Run container from custom tag (detached mode)"
	@echo "  shell       - Run interactive shell in container (immediate access)"
	@echo "  exec        - Enter running container shell"
	@echo "  push        - Push image to registry"
	@echo "  clean       - Clean up built Docker images"
	@echo "  images      - Show available images"
	@echo "  help        - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  GO_VERSION  - Go version (default: $(GO_VERSION))"
	@echo "  GIT_VERSION - Git version (default: $(GIT_VERSION))"
	@echo "  IMAGE_NAME  - Docker image name (default: $(IMAGE_NAME))"
	@echo "  TAG         - Custom tag for build-tag and run-tag targets"