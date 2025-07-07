#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Iniciando instalação do ambiente de automação WhatsApp${NC}"

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${YELLOW}Por favor, execute como root (sudo)${NC}"
  exit
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
    docker.io \
    docker-compose

# Habilitar e iniciar Docker
systemctl enable docker
systemctl start docker

# Criar diretório do projeto
mkdir -p /opt/whatsapp-automation
cd /opt/whatsapp-automation

# Criar arquivo .env
cat > .env << EOL
# Configurações N8N
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http

# Banco de Dados
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=n8npass

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Evolution API
SERVER_URL=http://localhost:8080

# Grafana
GRAFANA_PASSWORD=admin

# Timezone
TZ=America/Sao_Paulo
EOL

# Baixar o arquivo do agente
echo -e "${GREEN}Baixando arquivo do agente...${NC}"
mkdir -p workflows
cp ../Agente_SDR_Premium_ACADEMIA_CRIADOR_DIGITALJSON.json.json workflows/

# Iniciar os containers
echo -e "${GREEN}Iniciando containers...${NC}"
docker-compose up -d

# Aguardar serviços iniciarem
echo -e "${YELLOW}Aguardando serviços iniciarem...${NC}"
sleep 30

# Importar workflow do agente
echo -e "${GREEN}Importando workflow do agente...${NC}"
curl -X POST http://localhost:5678/rest/workflows \
  -H "Content-Type: application/json" \
  -d @workflows/Agente_SDR_Premium_ACADEMIA_CRIADOR_DIGITALJSON.json.json

echo -e "${GREEN}Instalação concluída!${NC}"
echo -e "${BLUE}Acessos:${NC}"
echo -e "N8N: http://localhost:5678"
echo -e "Evolution API: http://localhost:8080"
echo -e "Grafana: http://localhost:3001" 