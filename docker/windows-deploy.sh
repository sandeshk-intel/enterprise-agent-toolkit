#!/usr/bin/env bash
# Windows 11 Deployment Helper Script
# Run this in WSL2 Ubuntu terminal
#
# Usage: ./windows-deploy.sh [start|stop|restart|status|logs|test]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running in WSL2
check_wsl2() {
    if ! grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
        log_error "This script must be run in WSL2 Ubuntu"
        log_error "Open Windows Terminal → Ubuntu, then run this script"
        exit 1
    fi
    log_success "Running in WSL2 ✓"
}

# Check Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found"
        log_error "Ensure Docker Desktop is running and WSL2 integration is enabled"
        log_error "Docker Desktop → Settings → Resources → WSL Integration"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running"
        log_error "Start Docker Desktop for Windows"
        exit 1
    fi

    log_success "Docker available ✓"
}

# Start services
start_services() {
    log_info "Starting Agentic AI Stack..."

    cd "$PROJECT_ROOT"

    if [ ! -f "docker/.env" ]; then
        log_warn ".env file not found, running deployment script..."
        ./deploy-agentic-stack.sh --platform=docker
    else
        log_info "Starting with existing configuration..."
        docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml up -d
    fi

    log_success "Services started"
    echo ""
    show_status
}

# Stop services
stop_services() {
    log_info "Stopping services..."
    cd "$PROJECT_ROOT"
    docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml down
    log_success "Services stopped (data preserved)"
}

# Restart services
restart_services() {
    log_info "Restarting services..."
    cd "$PROJECT_ROOT"
    docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml restart
    log_success "Services restarted"
    echo ""
    show_status
}

# Show status
show_status() {
    log_info "Service Status:"
    cd "$PROJECT_ROOT"
    docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml ps

    echo ""
    log_info "Quick Health Check:"

    # LiteLLM
    if curl -sf http://localhost:4000/health/liveliness &> /dev/null; then
        log_success "LiteLLM: healthy (http://localhost:4000/ui)"
    else
        log_warn "LiteLLM: not responding"
    fi

    # vLLM
    if curl -sf http://localhost:2080/health &> /dev/null; then
        log_success "vLLM: healthy (http://localhost:2080/docs)"
    else
        log_warn "vLLM: not responding (may still be loading model)"
    fi

    # PostgreSQL
    if docker exec agentic-postgres pg_isready -U postgres &> /dev/null; then
        log_success "PostgreSQL: accepting connections"
    else
        log_warn "PostgreSQL: not ready"
    fi

    # Redis
    source docker/.env 2>/dev/null || true
    if docker exec agentic-redis redis-cli -a "${REDIS_PASSWORD:-}" ping 2>/dev/null | grep -q PONG; then
        log_success "Redis: responding"
    else
        log_warn "Redis: not responding"
    fi
}

# Show logs
show_logs() {
    cd "$PROJECT_ROOT"

    if [ $# -eq 0 ]; then
        log_info "Showing all logs (Ctrl+C to exit)..."
        docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml logs -f
    else
        log_info "Showing logs for: $1"
        docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml logs -f "$1"
    fi
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    cd "$PROJECT_ROOT"

    # Source environment
    if [ ! -f "docker/.env" ]; then
        log_error "docker/.env not found. Run deployment first."
        exit 1
    fi

    source docker/.env

    # Test LiteLLM health
    log_info "Testing LiteLLM..."
    if curl -sf http://localhost:4000/health/liveliness | grep -q "healthy"; then
        log_success "LiteLLM health check passed"
    else
        log_error "LiteLLM health check failed"
        return 1
    fi

    # Test model listing
    log_info "Testing model listing..."
    LITELLM_KEY=$(grep LITELLM_MASTER_KEY docker/.env | cut -d= -f2 | tr -d '"')

    if curl -sf http://localhost:4000/v1/models \
        -H "Authorization: Bearer ${LITELLM_KEY}" | grep -q "data"; then
        log_success "Model listing works"
    else
        log_error "Model listing failed"
        return 1
    fi

    # Test inference
    log_info "Testing inference..."
    RESPONSE=$(curl -sf http://localhost:4000/v1/chat/completions \
        -H "Authorization: Bearer ${LITELLM_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$(grep "^models=" docker/config.cfg | cut -d= -f2 | cut -d, -f1)"'",
            "messages": [{"role": "user", "content": "Say hello"}],
            "max_tokens": 10
        }' 2>/dev/null)

    if echo "$RESPONSE" | grep -q "choices"; then
        log_success "Inference test passed"
        echo ""
        log_info "Sample response:"
        echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null || echo "$RESPONSE"
    else
        log_error "Inference test failed"
        log_error "Response: $RESPONSE"
        return 1
    fi

    echo ""
    log_success "All tests passed!"
    echo ""
    log_info "Access points:"
    echo "  • LiteLLM UI: http://localhost:4000/ui"
    echo "  • vLLM Docs:  http://localhost:2080/docs"
    echo "  • API Key:    ${LITELLM_KEY}"
}

# System requirements check
check_requirements() {
    log_info "Checking Windows 11 system requirements..."
    echo ""

    # WSL2
    if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
        log_success "✓ Running in WSL2"
    else
        log_error "✗ Not running in WSL2"
    fi

    # Memory
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -ge 60 ]; then
        log_success "✓ RAM: ${TOTAL_MEM} GB (adequate)"
    else
        log_warn "⚠ RAM: ${TOTAL_MEM} GB (need 64+ GB for 14B models)"
    fi

    # Disk
    AVAIL_DISK=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAIL_DISK" -ge 80 ]; then
        log_success "✓ Disk: ${AVAIL_DISK} GB free (adequate)"
    else
        log_warn "⚠ Disk: ${AVAIL_DISK} GB free (need 80+ GB)"
    fi

    # CPU
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -ge 16 ]; then
        log_success "✓ CPU: ${CPU_CORES} cores (adequate)"
    else
        log_warn "⚠ CPU: ${CPU_CORES} cores (need 16+ cores)"
    fi

    # Docker
    if command -v docker &> /dev/null; then
        DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "✓ Docker: ${DOCKER_VER}"
    else
        log_error "✗ Docker not found"
    fi

    # Docker Compose
    if command -v docker compose &> /dev/null; then
        COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "unknown")
        log_success "✓ Docker Compose: ${COMPOSE_VER}"
    else
        log_error "✗ Docker Compose not found"
    fi

    echo ""
    log_info "Docker Desktop resource allocation:"
    log_info "  Set in: Docker Desktop → Settings → Resources"
    log_info "  Memory: 64+ GB recommended"
    log_info "  CPUs: 16+ cores recommended"
}

# Clean deployment (full cleanup)
clean_deployment() {
    log_warn "⚠️  FULL CLEANUP - This will remove all data including models"
    echo ""
    log_info "What will be deleted:"
    echo "  • All containers"
    echo "  • All volumes (models, databases, cache)"
    echo "  • Generated configurations (.env, vault.yml)"
    echo ""
    log_info "What will be kept:"
    echo "  • Source code and documentation"
    echo "  • Your config.cfg settings"
    echo ""

    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled"
        return 0
    fi

    log_info "Stopping and removing containers..."
    cd "$PROJECT_ROOT"
    docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml down --volumes

    log_info "Removing generated files..."
    rm -f docker/.env docker/vault.yml docker/docker-compose.vllm.yml

    log_success "Cleanup complete!"
    echo ""
    log_info "Disk space freed: Run 'docker system df' to see"
    log_info "To deploy again: ./windows-deploy.sh start"
}

# Clean but keep models
clean_keep_models() {
    log_warn "⚠️  CLEANUP (keeping models) - Removes containers and data but keeps model cache"
    echo ""
    log_info "What will be deleted:"
    echo "  • All containers"
    echo "  • Database data"
    echo "  • Redis cache"
    echo "  • Generated configurations"
    echo ""
    log_info "What will be kept:"
    echo "  • Downloaded models (~28 GB per model)"
    echo "  • Source code and documentation"
    echo "  • Your config.cfg settings"
    echo ""

    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled"
        return 0
    fi

    log_info "Stopping containers..."
    cd "$PROJECT_ROOT"
    docker compose -f docker/docker-compose.yml -f docker/docker-compose.vllm.yml down

    log_info "Removing non-model volumes..."
    docker volume rm docker_postgres-data docker_redis-data docker_flowise-data \
                     docker_clickhouse-data docker_minio-data 2>/dev/null || true

    log_info "Removing generated files..."
    rm -f docker/.env docker/vault.yml docker/docker-compose.vllm.yml

    log_success "Cleanup complete!"
    echo ""
    log_info "Model cache preserved"
    log_info "Next deployment will reuse downloaded models (faster startup)"
    log_info "To deploy again: ./windows-deploy.sh start"
}

# Show usage
usage() {
    cat <<EOF
Windows 11 Deployment Helper - Agentic AI Stack

Usage: ./windows-deploy.sh [command]

Commands:
  start            Start all services
  stop             Stop all services (keep data)
  restart          Restart all services
  status           Show service status and health
  logs [svc]       Show logs (optionally for specific service)
  test             Run deployment tests
  check            Check system requirements
  clean            Full cleanup (remove everything including models)
  clean-keep-models Cleanup but keep downloaded models
  help             Show this help

Examples:
  ./windows-deploy.sh start                # Start everything
  ./windows-deploy.sh status               # Check health
  ./windows-deploy.sh logs                 # View all logs
  ./windows-deploy.sh logs litellm         # View LiteLLM logs only
  ./windows-deploy.sh test                 # Test API functionality
  ./windows-deploy.sh clean                # Full cleanup (remove all data)
  ./windows-deploy.sh clean-keep-models    # Cleanup but keep models

Service names:
  - agentic-postgres
  - agentic-redis
  - agentic-litellm
  - agentic-vllm-*
  - agentic-flowise (if enabled)
  - agentic-langfuse-* (if enabled)

Access from Windows browser:
  • LiteLLM: http://localhost:4000/ui
  • vLLM:    http://localhost:2080/docs
  • Flowise: http://localhost:3000 (if enabled)
EOF
}

# Main
main() {
    case "${1:-help}" in
        start)
            check_wsl2
            check_docker
            start_services
            ;;
        stop)
            check_wsl2
            check_docker
            stop_services
            ;;
        restart)
            check_wsl2
            check_docker
            restart_services
            ;;
        status)
            check_wsl2
            check_docker
            show_status
            ;;
        logs)
            check_wsl2
            check_docker
            show_logs "${2:-}"
            ;;
        test)
            check_wsl2
            check_docker
            test_deployment
            ;;
        check)
            check_requirements
            ;;
        clean)
            check_wsl2
            check_docker
            clean_deployment
            ;;
        clean-keep-models)
            check_wsl2
            check_docker
            clean_keep_models
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
