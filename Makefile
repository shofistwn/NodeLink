# ==============================================================================
# NodeLink - Docker Makefile
# ==============================================================================

# Variables
SERVICE        ?= nodelink
CONTAINER      ?= nodelink_app
COMPOSE_FILE   ?= docker-compose.yml

# Detect docker compose command (modern CLI v2 'docker compose', legacy 'docker-compose', or 'podman-compose')
DOCKER_COMPOSE ?= $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; elif command -v podman-compose >/dev/null 2>&1; then echo "podman-compose"; else echo "docker compose"; fi)
DOCKER_BIN     ?= $(shell if command -v docker >/dev/null 2>&1; then echo "docker"; elif command -v podman >/dev/null 2>&1; then echo "podman"; else echo "docker"; fi)

# Git metadata for build args
GIT_COMMIT     ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH     ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_TIME     ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# ANSI Color codes for terminal formatting
CYAN   := \033[36m
GREEN  := \033[32m
YELLOW := \033[33m
RED    := \033[31m
RESET  := \033[0m

.PHONY: all help build build-nc up start down stop restart logs ps shell sh stats pull clean rebuild prune

all: help

## Display list of available commands
help:
	@printf "\n"
	@printf "$(CYAN)╔═══════════════════════════════════════════════════════════════╗$(RESET)\n"
	@printf "$(CYAN)║                  NodeLink Docker Manager                      ║$(RESET)\n"
	@printf "$(CYAN)╚═══════════════════════════════════════════════════════════════╝$(RESET)\n"
	@printf "\n"
	@printf "$(YELLOW)Usage:$(RESET) make [target]\n\n"
	@printf "$(GREEN)Build & Lifecycle:$(RESET)\n"
	@printf "  $(CYAN)make build$(RESET)       Build Docker image with Git & build-time metadata\n"
	@printf "  $(CYAN)make build-nc$(RESET)    Build Docker image without cache (--no-cache)\n"
	@printf "  $(CYAN)make up$(RESET)          Run container in the background (detached mode)\n"
	@printf "  $(CYAN)make down$(RESET)        Stop and remove containers, networks, and orphans\n"
	@printf "  $(CYAN)make start$(RESET)       Alias for 'make up'\n"
	@printf "  $(CYAN)make stop$(RESET)        Stop running containers without removing them\n"
	@printf "  $(CYAN)make restart$(RESET)     Restart the NodeLink container\n"
	@printf "  $(CYAN)make rebuild$(RESET)     Down, rebuild image, and start container (up)\n"
	@printf "\n"
	@printf "$(GREEN)Monitoring & Debugging:$(RESET)\n"
	@printf "  $(CYAN)make logs$(RESET)        Stream container logs in real time (follow)\n"
	@printf "  $(CYAN)make ps$(RESET)          Show status of running containers\n"
	@printf "  $(CYAN)make shell$(RESET)       Open an interactive shell inside the container (/bin/sh)\n"
	@printf "  $(CYAN)make stats$(RESET)       Monitor container CPU & Memory resource usage\n"
	@printf "\n"
	@printf "$(GREEN)Maintenance & Cleanup:$(RESET)\n"
	@printf "  $(CYAN)make pull$(RESET)        Pull latest images from the registry\n"
	@printf "  $(CYAN)make clean$(RESET)       Stop containers and delete volumes & networks\n"
	@printf "  $(CYAN)make prune$(RESET)       Remove unused Docker images and build cache\n"
	@printf "\n"

## Build Docker image with build-args metadata
build:
	@printf "$(YELLOW)Building Docker image ($(SERVICE))...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) build \
		--build-arg GIT_COMMIT=$(GIT_COMMIT) \
		--build-arg GIT_BRANCH=$(GIT_BRANCH) \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		$(SERVICE)
	@printf "$(GREEN)✓ Build finished successfully!$(RESET)\n"

## Build Docker image without cache
build-nc:
	@printf "$(YELLOW)Building Docker image without cache...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) build --no-cache \
		--build-arg GIT_COMMIT=$(GIT_COMMIT) \
		--build-arg GIT_BRANCH=$(GIT_BRANCH) \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		$(SERVICE)
	@printf "$(GREEN)✓ No-cache build finished successfully!$(RESET)\n"

## Run container in the background
up:
	@printf "$(YELLOW)Starting NodeLink container...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) up -d $(SERVICE)
	@printf "$(GREEN)✓ NodeLink is running in the background.$(RESET)\n"
	@printf "$(CYAN)Use 'make logs' to view logs or 'make ps' to check status.$(RESET)\n"

start: up

## Stop and remove containers and network
down:
	@printf "$(YELLOW)Stopping and removing NodeLink container...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) down
	@printf "$(GREEN)✓ Containers stopped and removed.$(RESET)\n"

## Pause/stop container without removing
stop:
	@printf "$(YELLOW)Stopping container processes...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) stop $(SERVICE)
	@printf "$(GREEN)✓ Service $(SERVICE) stopped.$(RESET)\n"

## Restart container
restart:
	@printf "$(YELLOW)Restarting NodeLink container...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) restart $(SERVICE)
	@printf "$(GREEN)✓ Container restarted.$(RESET)\n"

## Rebuild and restart container
rebuild: down build up

## Stream container logs
logs:
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) logs -f $(SERVICE)

## Check container status
ps:
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) ps

## Open interactive shell inside container
shell:
	@printf "$(YELLOW)Opening shell in container $(CONTAINER)...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) exec $(SERVICE) /bin/sh

sh: shell

## Monitor resource usage statistics
stats:
	@$(DOCKER_BIN) stats $(CONTAINER)

## Pull latest image from registry
pull:
	@printf "$(YELLOW)Pulling latest images...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) pull $(SERVICE)
	@printf "$(GREEN)✓ Pull completed!$(RESET)\n"

## Remove container, volumes, and network
clean:
	@printf "$(RED)Cleaning up containers, volumes, and networks...$(RESET)\n"
	@$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) down -v --remove-orphans
	@printf "$(GREEN)✓ Cleanup completed.$(RESET)\n"

## Remove unused container images & build cache
prune:
	@printf "$(YELLOW)Pruning unused Docker images & build cache...$(RESET)\n"
	@$(DOCKER_BIN) system prune -f
	@printf "$(GREEN)✓ Docker prune completed.$(RESET)\n"
