#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Função para verificar se um serviço está rodando
check_service() {
    local host=$1
    local port=$2
    local service=$3
    local max_attempts=$4
    local attempt=1

    echo -e "${YELLOW}Aguardando $service iniciar (max $max_attempts tentativas)...${NC}"
    
    while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            echo -e "${RED}Timeout aguardando $service${NC}"
            return 1
        fi
        echo -n "."
        sleep 5
        ((attempt++))
    done
    echo -e "\n${GREEN}$service está rodando!${NC}"
    return 0
}

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Por favor, execute como root (sudo)${NC}"
    exit 1
fi

# Verificar portas em uso
ports=(5678 8080 3000 3001 6379 9090)
for port in "${ports[@]}"; do
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null; then
        echo -e "${RED}Erro: Porta $port já está em uso${NC}"
        exit 1
    fi
done

# Definir arquivos necessários
AGENT_FILE="Agente_SDR_Premium_ACADEMIA_CRIADOR_DIGITALJSON.json.json"

# Verificar arquivos necessários
echo -e "${BLUE}Verificando arquivos necessários...${NC}"
REQUIRED_FILES=("docker-compose.yml" "$AGENT_FILE")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo -e "${RED}Os seguintes arquivos estão faltando:${NC}"
    printf '%s\n' "${MISSING_FILES[@]}"
    exit 1
fi

# Criar backup do ambiente atual se existir
if [ -d "/opt/whatsapp-automation" ]; then
    backup_dir="/opt/whatsapp-automation-backup-$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Criando backup em $backup_dir${NC}"
    cp -r /opt/whatsapp-automation $backup_dir
fi

# Atualizar sistema
echo -e "${GREEN}Atualizando sistema...${NC}"
apt update && apt upgrade -y

# Instalar dependências
echo -e "${GREEN}Instalando dependências...${NC}"
apt install -y \
    curl \
    wget \
    git \
    netcat-openbsd

# Instalar Docker usando o script oficial
echo -e "${GREEN}Instalando Docker...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Instalar Docker Compose
echo -e "${GREEN}Instalando Docker Compose...${NC}"
curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Habilitar e iniciar Docker
systemctl enable docker || true
systemctl start docker || true

# Verificar se Docker está rodando
if ! systemctl is-active --quiet docker; then
    echo -e "${RED}Erro: Docker não está rodando${NC}"
    exit 1
fi

# Criar diretório do projeto
mkdir -p /opt/whatsapp-automation
cd /opt/whatsapp-automation

# Criar diretório para workflows e data
mkdir -p workflows
mkdir -p data/waha

# Copiar arquivos necessários
echo -e "${GREEN}Copiando arquivos necessários...${NC}"
cp "$OLDPWD/docker-compose.yml" .
cp "$OLDPWD/$AGENT_FILE" workflows/

# Criar arquivo .env com senha aleatória
RANDOM_PASSWORD=$(openssl rand -base64 12)
cat > .env << EOL
# Configurações N8N
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http

# Banco de Dados
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$RANDOM_PASSWORD

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Evolution API
SERVER_URL=http://localhost:8080

# Grafana
GRAFANA_PASSWORD=$RANDOM_PASSWORD

# Timezone
TZ=America/Sao_Paulo

DOMAIN_NAME=seu_dominio.com
SUBDOMAIN=n8n
SSL_EMAIL=seu_email@exemplo.com
EOL

# Iniciar os containers com verificação
echo -e "${GREEN}Iniciando containers...${NC}"
if ! docker-compose pull; then
    echo -e "${RED}Erro ao baixar as imagens dos containers${NC}"
    exit 1
fi

if ! docker-compose up -d; then
    echo -e "${RED}Erro ao iniciar os containers${NC}"
    exit 1
fi

# Aguardar serviços iniciarem com tempo maior
echo -e "${YELLOW}Aguardando serviços iniciarem...${NC}"
sleep 30  # Dar mais tempo para os serviços iniciarem

# Verificar cada serviço
for service in "N8N:5678" "Evolution API:8080" "Grafana:3001"; do
    name="${service%:*}"
    port="${service#*:}"
    
    echo -e "${YELLOW}Verificando $name na porta $port...${NC}"
    attempt=1
    max_attempts=12
    
    while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            echo -e "${RED}Timeout aguardando $name${NC}"
            echo -e "${YELLOW}Verificando logs do container...${NC}"
            docker-compose logs "$name" | tail -n 50
            exit 1
        fi
        echo -n "."
        sleep 10
        ((attempt++))
    done
    echo -e "\n${GREEN}$name está rodando!${NC}"
done

# Importar workflow do agente
echo -e "${GREEN}Importando workflow do agente...${NC}"
curl -X POST http://localhost:5678/rest/workflows \
    -H "Content-Type: application/json" \
    -d @workflows/Agente_SDR_Premium_ACADEMIA_CRIADOR_DIGITALJSON.json.json

# Criar arquivo com credenciais
echo -e "${GREEN}Salvando credenciais...${NC}"
cat > /opt/whatsapp-automation/credentials.txt << EOL
=== Credenciais do Ambiente ===
N8N: http://localhost:5678
Evolution API: http://localhost:8080
Grafana: http://localhost:3001

Usuário Postgres: n8n
Senha Postgres: $RANDOM_PASSWORD

Usuário Grafana: admin
Senha Grafana: $RANDOM_PASSWORD

Mantenha este arquivo em local seguro!
EOL

chmod 600 /opt/whatsapp-automation/credentials.txt

echo -e "${GREEN}Instalação concluída!${NC}"
echo -e "${BLUE}Acessos:${NC}"
echo -e "N8N: http://localhost:5678"
echo -e "Evolution API: http://localhost:8080"
echo -e "Grafana: http://localhost:3001"
echo -e "\n${YELLOW}As credenciais foram salvas em /opt/whatsapp-automation/credentials.txt${NC}" 