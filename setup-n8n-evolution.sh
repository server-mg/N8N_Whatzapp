#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Constantes
DOCKER_IMAGES=(
    "n8nio/n8n:latest"
    "postgres:13"
    "redis:7-alpine"
    "traefik:v2.5"
    "atendai/evolution-api:latest"
)

# Constantes de Rede e IPs
NETWORK_SUBNET="192.168.16.0/24"
TRAEFIK_IP="192.168.16.110"
N8N_IP="192.168.16.111"
POSTGRES_IP="192.168.16.112"
REDIS_IP="192.168.16.115"
EVOLUTION_IP="192.168.16.120"
N8N_PORT=5679  # Mudado de 5678 para evitar conflito
EVOLUTION_PORT=8081  # Mudado de 8080 para evitar conflito
TRAEFIK_HTTP_PORT=81  # Mudado de 80 para evitar conflito
TRAEFIK_HTTPS_PORT=444  # Mudado de 443 para evitar conflito

# Constantes de DNS e Rede
DNS_SERVER="192.168.16.1"
NETWORK_GATEWAY="192.168.16.1"

# Função para log
log() {
    local level=$1
    local msg=$2
    local color=$NC
    
    case $level in
        "INFO") color=$BLUE ;;
        "SUCCESS") color=$GREEN ;;
        "ERROR") color=$RED ;;
        "WARN") color=$YELLOW ;;
    esac
    
    echo -e "${color}[$level] $msg${NC}"
}

# Função para verificar erros
check_error() {
    if [ $? -ne 0 ]; then
        log "ERROR" "$1"
        exit 1
    fi
}

# Função para verificar se um comando existe
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "ERROR" "$1 não está instalado"
        return 1
    fi
    return 0
}

# Função para obter DNS atual
get_current_dns() {
    local dns_servers=()
    
    # Tentar obter do systemd-resolved primeiro
    if command -v resolvectl &>/dev/null; then
        dns_servers=($(resolvectl status | grep "DNS Servers" | awk '{$1=$2=""; print $0}'))
    fi
    
    # Se não encontrou, tentar do resolv.conf
    if [ ${#dns_servers[@]} -eq 0 ]; then
        dns_servers=($(grep "^nameserver" /etc/resolv.conf | awk '{print $2}'))
    fi
    
    # Se ainda não encontrou, usar DNS padrão
    if [ ${#dns_servers[@]} -eq 0 ]; then
        dns_servers=("192.168.16.1" "1.1.1.1" "8.8.8.8")
    fi
    
    echo "${dns_servers[0]}"
}

# Função para configurar DNS
setup_dns() {
    log "INFO" "Configurando DNS..."
    
    # Detectar DNS atual
    local current_dns=$(get_current_dns)
    DNS_SERVER="$current_dns"
    
    # Fazer backup do resolv.conf atual
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup
    fi
    
    # Configurar DNS com fallback
    cat > /etc/resolv.conf << EOL
nameserver ${DNS_SERVER}
nameserver 1.1.1.1
nameserver 8.8.8.8
EOL
    
    log "SUCCESS" "DNS configurado com sucesso (Primário: ${DNS_SERVER})"
}

# Função para configurar rede Docker
setup_docker_network() {
    log "INFO" "Configurando rede Docker..."
    
    # Remover rede antiga se existir
    if docker network inspect n8n-network &>/dev/null; then
        log "INFO" "Removendo rede Docker antiga..."
        docker network rm n8n-network
    fi
    
    # Criar nova rede
    log "INFO" "Criando nova rede Docker..."
    docker network create --subnet=${NETWORK_SUBNET} \
                         --gateway=${NETWORK_GATEWAY} \
                         --opt "com.docker.network.bridge.name=n8n-bridge" \
                         n8n-network
    
    check_error "Falha ao criar rede Docker"
}

# Função para verificar conectividade local
check_local_network() {
    log "INFO" "Verificando conectividade local..."
    local gateway=$(get_default_gateway)
    if [ -z "$gateway" ]; then
        log "WARN" "Gateway padrão não encontrado, continuando mesmo assim."
        return 0
    fi
    if ! ping -c 1 -W 2 $gateway &>/dev/null; then
        log "WARN" "Não foi possível acessar o gateway $gateway, mas continuando."
        return 0
    fi
    log "SUCCESS" "Gateway $gateway acessível."
    return 0
}

# Função para verificar conexão com internet
check_internet() {
    # Primeiro verificar rede local
    if ! check_local_network; then
        if [ "${SKIP_INTERNET_CHECK}" != "1" ]; then
            log "ERROR" "Problemas com a rede local"
            log "INFO" "Para continuar mesmo assim, execute:"
            log "INFO" "SKIP_INTERNET_CHECK=1 sudo -E ./setup-n8n-evolution.sh"
            return 1
        fi
    fi
    
    # Se SKIP_INTERNET_CHECK=1, pular verificação
    if [ "${SKIP_INTERNET_CHECK}" = "1" ]; then
        log "WARN" "Pulando verificação de internet conforme solicitado"
        return 0
    fi
    
    # Verificar conectividade com Docker Hub
    local timeout=2
    if curl --connect-timeout $timeout -Is https://registry.hub.docker.com &>/dev/null; then
        return 0
    fi
    
    log "ERROR" "Não foi possível conectar ao Docker Hub"
    log "INFO" "Verificando configuração de rede..."
    
    # Mostrar informações de rede
    log "INFO" "Configuração atual de DNS:"
    cat /etc/resolv.conf
    
    log "INFO" "Gateway padrão:"
    ip route show default
    
    log "WARN" "Para continuar mesmo sem verificação, execute:"
    log "WARN" "SKIP_INTERNET_CHECK=1 sudo -E ./setup-n8n-evolution.sh"
    
    return 1
}

# Função para verificar e criar diretório
create_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        check_error "Falha ao criar diretório $1"
    fi
}

# Função para instalar Docker seguindo a documentação oficial
install_docker() {
    log "INFO" "Instalando Docker..."
    
    # Remover versões antigas
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        apt-get remove -y $pkg &>/dev/null || true
    done
    
    # Instalar dependências
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    
    # Adicionar repositório oficial Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Instalar Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Verificar instalação
    docker --version
    check_error "Falha ao instalar Docker"
    
    # Configurar Docker para iniciar no boot
    systemctl enable docker
    systemctl start docker
}

# Função para configurar Docker
setup_docker() {
    log "INFO" "Configurando Docker..."
    
    # Criar grupo docker se não existir
    if ! getent group docker > /dev/null; then
        groupadd docker
    fi
    
    # Adicionar usuário atual ao grupo docker
    usermod -aG docker $SUDO_USER
    
    # Configurar log rotation
    cat > /etc/docker/daemon.json << EOL
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOL
    
    # Reiniciar Docker para aplicar configurações
    systemctl restart docker
}

# Função para verificar e autenticar no Docker Hub
docker_login() {
    log "INFO" "Verificando autenticação no Docker Hub..."
    
    if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
        echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
        check_error "Falha ao autenticar no Docker Hub"
    else
        log "WARN" "Credenciais do Docker Hub não fornecidas, continuando sem autenticação..."
    fi
}

# Função para verificar imagem Docker
check_docker_image() {
    local image="$1"
    
    log "INFO" "Verificando disponibilidade da imagem: $image"
    
    if ! docker pull "$image" &>/dev/null; then
        log "ERROR" "Imagem $image não encontrada"
        return 1
    fi
    
    log "SUCCESS" "✓ Imagem $image baixada com sucesso"
    return 0
}

# Função para baixar imagens Docker
pull_docker_images() {
    local failed=0
    local successful_images=()
    
    log "INFO" "Iniciando download das imagens Docker..."
    
    for image in "${DOCKER_IMAGES[@]}"; do
        if check_docker_image "$image"; then
            successful_images+=("$image")
        else
            failed=1
        fi
    done
    
    if [ $failed -eq 1 ]; then
        log "ERROR" "\nResumo de erros:"
        log "INFO" "Imagens baixadas com sucesso:"
        for img in "${successful_images[@]}"; do
            log "SUCCESS" "✓ $img"
        done
        
        log "ERROR" "\nImagens que falharam:"
        for img in "${DOCKER_IMAGES[@]}"; do
            if [[ ! " ${successful_images[@]} " =~ " ${img} " ]]; then
                log "ERROR" "✗ $img"
            fi
        done
        return 1
    fi
    
    return 0
}

# Função para verificar se uma porta está disponível
check_port() {
    local port=$1
    if netstat -tuln | grep -q ":$port "; then
        log "ERROR" "Porta $port já está em uso"
        return 1
    fi
    return 0
}

# Função para verificar se os serviços estão rodando
check_services() {
    log "INFO" "Verificando status dos serviços..."
    
    # Aguardar 10 segundos para os serviços iniciarem
    sleep 10
    
    # Verificar cada serviço
    local services=("n8n" "evolution-api" "postgres" "redis" "traefik")
    local all_running=true
    
    for service in "${services[@]}"; do
        local status=$(docker-compose ps --format json $service | grep -o '"State":"[^"]*"' | cut -d'"' -f4)
        if [ "$status" != "running" ]; then
            log "ERROR" "Serviço $service não está rodando (status: $status)"
            all_running=false
        else
            log "SUCCESS" "Serviço $service está rodando"
        fi
    done
    
    if [ "$all_running" = false ]; then
        log "ERROR" "Alguns serviços não estão rodando corretamente"
        log "INFO" "Verificando logs dos serviços com problema..."
        docker-compose logs --tail=50
        return 1
    fi
    
    return 0
}

# Função para validar configurações
validate_config() {
    local error=false
    
    # Verificar se as portas necessárias estão disponíveis
    local ports=($TRAEFIK_HTTP_PORT $TRAEFIK_HTTPS_PORT $N8N_PORT $EVOLUTION_PORT)
    for port in "${ports[@]}"; do
        if ! check_port "$port"; then
            error=true
        fi
    done
    
    # Validar rede
    if ! docker network inspect n8n-network >/dev/null 2>&1; then
        log "INFO" "Criando rede Docker n8n-network..."
        docker network create --subnet=$NETWORK_SUBNET n8n-network || {
            log "ERROR" "Falha ao criar rede Docker"
            error=true
        }
    fi
    
    return $error
}

# Função para obter gateway padrão do sistema
get_default_gateway() {
    ip route | grep default | awk '{print $3}' | head -n1
}

# Função para obter DNS do sistema
get_system_dns() {
    grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | head -n1
}

# Início do script
log "INFO" "Iniciando instalação do ambiente N8N + Evolution API"

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    log "ERROR" "Por favor, execute como root (sudo)"
    exit 1
fi

# Usar gateway padrão do sistema
NETWORK_GATEWAY=$(get_default_gateway)
if [ -z "$NETWORK_GATEWAY" ]; then
    NETWORK_GATEWAY="192.168.16.1"
fi

# Usar DNS do sistema
DNS_SERVER=$(get_system_dns)
if [ -z "$DNS_SERVER" ]; then
    DNS_SERVER="8.8.8.8"
fi

# Configurar rede Docker (padrão: bridge)
setup_docker_network

# Verificar conectividade
if ! check_local_network; then
    log "WARN" "Problemas de conectividade local, mas continuando."
fi

# Criar diretório de backup
BACKUP_DIR="/opt/whatsapp-automation-backup-$(date +%Y%m%d_%H%M%S)"
log "INFO" "Criando backup em ${BACKUP_DIR}"
create_directory "${BACKUP_DIR}"

# Atualizar sistema
log "INFO" "Atualizando sistema..."
apt update && apt upgrade -y
check_error "Falha ao atualizar o sistema"

# Instalar dependências
log "INFO" "Instalando dependências..."
apt install -y curl wget git netcat-openbsd
check_error "Falha ao instalar dependências"

# Instalar e configurar Docker
if ! check_command docker; then
    install_docker
    setup_docker
fi

# Autenticar no Docker Hub
docker_login

# Criar diretório do projeto
PROJECT_DIR="/opt/n8n-evolution"
log "INFO" "Criando diretório do projeto em ${PROJECT_DIR}"
create_directory "${PROJECT_DIR}"
cd "${PROJECT_DIR}"
check_error "Falha ao acessar diretório do projeto"

# Criar docker-compose.yml
log "INFO" "Criando arquivo docker-compose.yml"
cat > docker-compose.yml << EOL
version: '3.8'

services:
  traefik:
    image: traefik:v2.5
    container_name: traefik
    restart: always
    ports:
      - "${TRAEFIK_HTTP_PORT}:80"
      - "${TRAEFIK_HTTPS_PORT}:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_data:/letsencrypt
    dns:
      - ${DNS_SERVER}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: always
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    volumes:
      - n8n_data:/home/node/.n8n
    dns:
      - ${DNS_SERVER}
    depends_on:
      - postgres
      - redis
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  postgres:
    image: postgres:13
    container_name: postgres
    restart: always
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
      - POSTGRES_NON_ROOT_USER=n8n_user
      - POSTGRES_NON_ROOT_PASSWORD=${POSTGRES_NON_ROOT_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    dns:
      - ${DNS_SERVER}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    volumes:
      - redis_data:/data
    dns:
      - ${DNS_SERVER}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  evolution-api:
    image: atendai/evolution-api:latest
    container_name: evolution-api
    restart: always
    ports:
      - "${EVOLUTION_PORT}:8080"
    volumes:
      - evolution_data:/evolution/instances
    environment:
      - API_KEY=${EVOLUTION_API_KEY}
    dns:
      - ${DNS_SERVER}
    depends_on:
      - redis
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  n8n_data:
  postgres_data:
  redis_data:
  traefik_data:
  evolution_data:
EOL
check_error "Falha ao criar docker-compose.yml"

# Criar arquivo .env
log "INFO" "Criando arquivo .env"
cat > .env << EOL
# Configurações de Rede
NETWORK_GATEWAY=${NETWORK_GATEWAY}
DNS_SERVER=${DNS_SERVER}
N8N_PORT=5679
EVOLUTION_PORT=8081
TRAEFIK_HTTP_PORT=81
TRAEFIK_HTTPS_PORT=444

# IPs dos Serviços (opcional, se usar rede customizada)
TRAEFIK_IP=192.168.16.110
N8N_IP=192.168.16.111
POSTGRES_IP=192.168.16.112
REDIS_IP=192.168.16.115
EVOLUTION_IP=192.168.16.120

# Configurações N8N
N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)

# Postgres
POSTGRES_PASSWORD=$(openssl rand -base64 32)
POSTGRES_NON_ROOT_PASSWORD=$(openssl rand -base64 32)

# Evolution API
EVOLUTION_API_KEY=$(openssl rand -base64 32)

# Docker Hub (opcional)
DOCKER_USERNAME=
DOCKER_PASSWORD=
EOL
check_error "Falha ao criar arquivo .env"

# Criar diretórios para volumes
log "INFO" "Criando diretórios para volumes"
for dir in n8n postgres redis evolution; do
    create_directory "data/$dir"
done

# Criar volumes Docker
log "INFO" "Criando volumes Docker"
for volume in n8n_data postgres_data redis_data traefik_data evolution_data; do
    docker volume create "$volume"
    check_error "Falha ao criar volume $volume"
done

# Baixar imagens Docker
pull_docker_images
check_error "Falha ao baixar algumas imagens Docker"

# Antes de iniciar os serviços
log "INFO" "Validando configurações..."
validate_config
check_error "Falha na validação das configurações"

# Iniciar serviços
log "INFO" "Iniciando serviços..."
docker-compose up -d
check_error "Falha ao iniciar serviços"

# Verificar status dos serviços
check_services
check_error "Falha na verificação dos serviços"

log "SUCCESS" "Instalação concluída!"

# Mostrar URLs de acesso com validação
log "INFO" "Acesse N8N em: http://${N8N_IP}:${N8N_PORT}"
log "INFO" "Evolution API em: http://${EVOLUTION_IP}:${EVOLUTION_PORT}"
log "INFO" "Traefik Dashboard em: http://${TRAEFIK_IP}:${TRAEFIK_HTTP_PORT}/dashboard/"
log "INFO" "Credenciais salvas em: ${PROJECT_DIR}/.env"

# Mostrar informações adicionais
log "INFO" "Para verificar os logs dos serviços:"
log "INFO" "  docker-compose logs -f [serviço]"
log "INFO" "Serviços disponíveis: n8n, evolution-api, postgres, redis, traefik" 