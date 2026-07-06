#!/bin/bash
# =============================================================================
# Project Manager Script - Auto-start, Status & Restart Management
# =============================================================================
# Features:
#   - Auto-start all project components on system boot
#   - Status monitoring for all services
#   - Safe restart with load-aware LLM sequencing
#   - Health checks with detailed reporting
# =============================================================================

set -euo pipefail

# Configuration
PROJECT_DIR="/home/vector/projects"
DIFY_DIR="$PROJECT_DIR/dify/docker"
WEBAPP_DIR="$PROJECT_DIR/webapp-conversation"
LOG_DIR="$PROJECT_DIR/tmp/logs"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Create log directory
mkdir -p "$LOG_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# SERVICE DEFINITIONS
# =============================================================================

# Define all services with their types and dependencies
declare -A SERVICES=(
    ["docker"]="docker:Dify Docker Compose"
    ["nginx-1"]="systemd:Nginx Reverse Proxy"
    ["ollama"]="systemd:Ollama LLM Server"
    ["webapp"]="systemd:WebApp Next.js"
    ["qdrant"]="docker:Qdrant Vector DB"
    ["redis"]="docker:Redis Cache"
)

# LLM services that need sequential startup (load-aware)
LLM_SERVICES=("ollama")

# Startup order - services started in this order
STARTUP_ORDER=(
    "docker"
    "qdrant"
    "redis"
    "nginx-1"
    "ollama"
    "webapp"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_DIR/project-manager_${TIMESTAMP}.log"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_DIR/project-manager_${TIMESTAMP}.log"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_DIR/project-manager_${TIMESTAMP}.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/project-manager_${TIMESTAMP}.log"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &> /dev/null; then
            log_error "This script requires root privileges or sudo"
            exit 1
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# Get service status
get_service_status() {
    local service=$1
    local type=$2
    
    case $type in
        docker)
            if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
                echo "running"
            elif docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
                echo "stopped"
            else
                echo "not_found"
            fi
            ;;
        systemd)
            if systemctl is-active --quiet "${service}"; then
                echo "running"
            elif systemctl is-enabled --quiet "${service}"; then
                echo "stopped"
            else
                echo "not_found"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check service health
check_health() {
    local service=$1
    local type=$2
    
    case $service in
        docker)
            # Check if docker daemon is running
            if ! docker info &>/dev/null; then
                return 1
            fi
            # Check if Dify containers are running
            if docker ps --format '{{.Names}}' | grep -q "dify"; then
                return 0
            fi
            return 1
            ;;
        nginx-1)
            if systemctl is-active --quiet nginx; then
                # Check if nginx is responding
                if curl -sf http://localhost/health &>/dev/null || \
                   curl -sf http://localhost:80 &>/dev/null || \
                   curl -sf http://localhost:443 &>/dev/null; then
                    return 0
                fi
            fi
            return 1
            ;;
        ollama)
            if curl -sf http://localhost:11434/api/tags &>/dev/null; then
                return 0
            fi
            return 1
            ;;
        webapp)
            if curl -sf http://localhost:3000 &>/dev/null; then
                return 0
            fi
            return 1
            ;;
        qdrant)
            if curl -sf http://localhost:6333/collections &>/dev/null; then
                return 0
            fi
            return 1
            ;;
        redis)
            if docker exec dify-docker-redis-1 redis-cli -a "${REDIS_PASSWORD:-difyai123456}" ping 2>/dev/null | grep -q PONG; then
                return 0
            fi
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# =============================================================================
# STATUS COMMAND
# =============================================================================

cmd_status() {
    echo "========================================"
    echo "  PROJECT SERVICES STATUS"
    echo "========================================"
    echo ""
    
    local all_healthy=true
    
    for service in "${!SERVICES[@]}"; do
        local type="${SERVICES[$service]%%:*}"
        local desc="${SERVICES[$service]#*:}"
        
        local status=$(get_service_status "$service" "$type")
        
        # Determine status icon and color
        local icon="❌"
        local color="$RED"
        
        case $status in
            running)
                if check_health "$service" "$type"; then
                    icon="✅"
                    color="$GREEN"
                else
                    icon="⚠️"
                    color="$YELLOW"
                    all_healthy=false
                fi
                ;;
            stopped)
                color="$YELLOW"
                all_healthy=false
                ;;
            not_found)
                color="$RED"
                all_healthy=false
                ;;
        esac
        
        printf "${color}%-12s${NC} %-25s %s\n" "$icon $service" "$desc" "[$status]"
    done
    
    echo ""
    echo "========================================"
    
    if $all_healthy; then
        log_success "All services are healthy"
        return 0
    else
        log_warning "Some services need attention"
        return 1
    fi
}

# =============================================================================
# START COMMAND
# =============================================================================

cmd_start() {
    log_info "Starting project services..."
    
    for service in "${STARTUP_ORDER[@]}"; do
        local type="${SERVICES[$service]%%:*}"
        local desc="${SERVICES[$service]#*:}"
        
        log_info "Starting $service..."
        
        case $type in
            docker)
                cd "$DIFY_DIR"
                docker compose up -d
                # Wait for docker to be ready
                sleep 10
                ;;
            systemd)
                $SUDO systemctl start "${service}"
                ;;
        esac
        
        # Wait for service to be healthy
        local attempts=0
        local max_attempts=30
        
        while [ $attempts -lt $max_attempts ]; do
            if check_health "$service" "$type"; then
                log_success "$service is ready"
                break
            fi
            sleep 2
            ((attempts++))
        done
        
        if [ $attempts -ge $max_attempts ]; then
            log_warning "$service may not be fully ready yet"
        fi
        
        # Special handling for LLM services - add delay between starts
        if [[ " ${LLM_SERVICES[@]} " =~ " ${service} " ]]; then
            log_info "Waiting for LLM service to stabilize..."
            sleep 15
        fi
    done
    
    log_success "All services started"
}

# =============================================================================
# STOP COMMAND
# =============================================================================

cmd_stop() {
    log_info "Stopping project services..."
    
    # Reverse startup order for stopping
    local reverse_order=($(printf '%s\n' "${STARTUP_ORDER[@]}" | tac))
    
    for service in "${reverse_order[@]}"; do
        local type="${SERVICES[$service]%%:*}"
        
        log_info "Stopping $service..."
        
        case $type in
            docker)
                cd "$DIFY_DIR"
                docker compose stop "$service" 2>/dev/null || true
                ;;
            systemd)
                $SUDO systemctl stop "${service}" 2>/dev/null || true
                ;;
        esac
        
        log_success "$service stopped"
    done
    
    log_success "All services stopped"
}

# =============================================================================
# RESTART COMMAND (with load-aware LLM sequencing)
# =============================================================================

cmd_restart() {
    local service=${1:-""}
    
    if [ -n "$service" ]; then
        # Restart specific service
        if [ -z "${SERVICES[$service]+exists}" ]; then
            log_error "Unknown service: $service"
            echo "Available services: ${!SERVICES[@]}"
            exit 1
        fi
        
        local type="${SERVICES[$service]%%:*}"
        
        log_info "Restarting $service..."
        
        case $type in
            docker)
                cd "$DIFY_DIR"
                docker compose restart "$service"
                ;;
            systemd)
                $SUDO systemctl restart "${service}"
                ;;
        esac
        
        log_success "$service restarted"
    else
        # Restart all services with load-aware sequencing
        log_info "Restarting all services with load-aware sequencing..."
        
        # First, stop all LLM services
        for llm in "${LLM_SERVICES[@]}"; do
            local type="${SERVICES[$llm]%%:*}"
            log_info "Stopping LLM service: $llm"
            case $type in
                systemd)
                    $SUDO systemctl stop "${llm}" 2>/dev/null || true
                    ;;
            esac
        done
        
        sleep 5
        
        # Restart non-LLM services
        for service in "${STARTUP_ORDER[@]}"; do
            if [[ ! " ${LLM_SERVICES[@]} " =~ " ${service} " ]]; then
                local type="${SERVICES[$service]%%:*}"
                log_info "Restarting: $service"
                
                case $type in
                    docker)
                        cd "$DIFY_DIR"
                        docker compose restart "$service" 2>/dev/null || true
                        ;;
                    systemd)
                        $SUDO systemctl restart "${service}" 2>/dev/null || true
                        ;;
                esac
                
                sleep 5
            fi
        done
        
        # Start LLM services one by one with delay
        for llm in "${LLM_SERVICES[@]}"; do
            local type="${SERVICES[$llm]%%:*}"
            log_info "Starting LLM service: $llm (with load delay)"
            
            case $type in
                systemd)
                    $SUDO systemctl start "${llm}"
                    ;;
            esac
            
            # Wait before starting next LLM
            sleep 20
        done
        
        log_success "All services restarted with load-aware sequencing"
    fi
}

# =============================================================================
# ENABLE AUTO-START COMMAND
# =============================================================================

cmd_enable() {
    log_info "Enabling auto-start for all services..."
    
    # Enable Dify Docker Compose service
    $SUDO cp "$DIFY_DIR/systemd/dify-docker.service" /etc/systemd/system/
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable dify-docker.service
    
    # Enable other systemd services
    for service in nginx-1 ollama webapp; do
        if [ -f "$DIFY_DIR/systemd/${service}.service" ]; then
            $SUDO cp "$DIFY_DIR/systemd/${service}.service" /etc/systemd/system/
            $SUDO systemctl enable "${service}"
        fi
    done
    
    $SUDO systemctl daemon-reload
    
    log_success "Auto-start enabled for all services"
    log_info "Use 'sudo systemctl start dify-docker' to start now"
}

# =============================================================================
# DISABLE AUTO-START COMMAND
# =============================================================================

cmd_disable() {
    log_info "Disabling auto-start for all services..."
    
    $SUDO systemctl disable dify-docker 2>/dev/null || true
    $SUDO systemctl disable nginx-1 2>/dev/null || true
    $SUDO systemctl disable ollama 2>/dev/null || true
    $SUDO systemctl disable webapp 2>/dev/null || true
    
    $SUDO rm -f /etc/systemd/system/dify-docker.service
    $SUDO rm -f /etc/systemd/system/nginx-1.service
    $SUDO rm -f /etc/systemd/system/ollama.service
    $SUDO rm -f /etc/systemd/system/webapp.service
    
    $SUDO systemctl daemon-reload
    
    log_success "Auto-start disabled for all services"
}

# =============================================================================
# LOGS COMMAND
# =============================================================================

cmd_logs() {
    local service=${1:-""}
    local lines=${2:-50}
    
    if [ -n "$service" ]; then
        case $service in
            docker)
                cd "$DIFY_DIR"
                docker compose logs --tail="$lines" -f
                ;;
            ollama|webapp)
                $SUDO journalctl -u "${service}" -n "$lines" -f
                ;;
            *)
                log_error "Unknown service: $service"
                ;;
        esac
    else
        # Show all logs
        echo "Showing recent logs from all services..."
        echo ""
        echo "=== Dify Docker ==="
        cd "$DIFY_DIR" && docker compose logs --tail=20
        echo ""
        echo "=== Systemd Services ==="
        for svc in ollama webapp nginx-1; do
            echo "--- $svc ---"
            $SUDO journalctl -u "${svc}" -n 10 --no-pager 2>/dev/null || echo "No logs available"
        done
    fi
}

# =============================================================================
# HEALTH CHECK COMMAND
# =============================================================================

cmd_health() {
    echo "========================================"
    echo "  HEALTH CHECK REPORT"
    echo "  $(date)"
    echo "========================================"
    echo ""
    
    local issues=0
    
    # Check system resources
    echo "--- System Resources ---"
    local mem_available=$(free -h | awk '/^Mem:/ {print $7}')
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    
    echo "Memory available: $mem_available"
    echo "Disk usage: $disk_usage"
    echo "Load average:$load_avg"
    echo ""
    
    # Check each service
    echo "--- Service Health ---"
    for service in "${!SERVICES[@]}"; do
        local type="${SERVICES[$service]%%:*}"
        local status=$(get_service_status "$service" "$type")
        
        if check_health "$service" "$type"; then
            printf "${GREEN}✓${NC} %-15s Healthy\n" "$service"
        else
            printf "${RED}✗${NC} %-15s Unhealthy (status: $status)\n" "$service"
            ((issues++))
        fi
    done
    
    echo ""
    echo "========================================"
    
    if [ $issues -eq 0 ]; then
        log_success "All health checks passed"
        return 0
    else
        log_error "$issues issue(s) detected"
        return 1
    fi
}

# =============================================================================
# QUICK FIX COMMAND
# =============================================================================

cmd_fix() {
    log_info "Running quick fix..."
    
    # Restart failed services
    for service in "${!SERVICES[@]}"; do
        local type="${SERVICES[$service]%%:*}"
        local status=$(get_service_status "$service" "$type")
        
        if [ "$status" != "running" ] || ! check_health "$service" "$type"; then
            log_warning "Fixing: $service"
            
            case $type in
                docker)
                    cd "$DIFY_DIR"
                    docker compose restart "$service" 2>/dev/null || \
                    docker compose up -d "$service"
                    ;;
                systemd)
                    $SUDO systemctl restart "${service}"
                    ;;
            esac
            
            sleep 5
        fi
    done
    
    log_success "Quick fix completed"
    cmd_status
}

# =============================================================================
# MAIN
# =============================================================================

show_help() {
    cat << EOF
Project Manager - Auto-start and Service Management

Usage: $0 <command> [service]

Commands:
    status          Show status of all services
    start           Start all services
    stop            Stop all services
    restart [svc]   Restart all services or specific service
    enable          Enable auto-start on boot
    disable         Disable auto-start on boot
    logs [svc]      Show logs (default: 50 lines)
    health          Run health check
    fix             Auto-fix failed services

Examples:
    $0 status
    $0 start
    $0 restart ollama
    $0 logs docker
    $0 health
    $0 fix

Auto-start Setup:
    sudo $0 enable

EOF
}

# Main entry point
main() {
    check_permissions
    
    local command=${1:-help}
    shift || true
    
    case $command in
        status)
            cmd_status
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart "$@"
            ;;
        enable)
            cmd_enable
            ;;
        disable)
            cmd_disable
            ;;
        logs)
            cmd_logs "$@"
            ;;
        health)
            cmd_health
            ;;
        fix)
            cmd_fix
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"