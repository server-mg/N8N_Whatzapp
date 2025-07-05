#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Iniciando instalação do ambiente N8N + WhatsApp API${NC}"

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

# Download dos arquivos de configuração
echo -e "${GREEN}Baixando arquivos de configuração...${NC}"
wget -O docker-compose.yml https://raw.githubusercontent.com/seu-repo/docker-compose.yml

# Criar diretórios para persistência
mkdir -p ./data/{n8n,waha,evolution,postgres,prometheus,grafana}

# Gerar senha segura para Postgres
POSTGRES_PASSWORD=$(openssl rand -base64 32)
EVOLUTION_API_KEY=$(openssl rand -base64 32)

# Criar arquivo .env
cat > .env << EOL
# Configurações N8N
N8N_HOST=n8n.seudominio.com
N8N_PORT=5678
N8N_PROTOCOL=https

# Configurações WAHA
WAHA_HOST=waha.seudominio.com
WAHA_PORT=3000
WAHA_PROTOCOL=https

# Configurações Evolution API
EVOLUTION_HOST=evolution.seudominio.com
EVOLUTION_API_KEY=${EVOLUTION_API_KEY}

# Configurações Postgres
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=n8n

# Configurações de Backup
BACKUP_RETENTION_DAYS=7
BACKUP_TIME="0 0 * * *" # Todo dia à meia-noite
EOL

# Criar script de backup
cat > backup.sh << EOL
#!/bin/bash
BACKUP_DIR="/opt/whatsapp-automation/backups"
DATE=\$(date +%Y%m%d_%H%M%S)

mkdir -p \$BACKUP_DIR

# Backup do Postgres
docker-compose exec -T postgres pg_dump -U n8n n8n > \$BACKUP_DIR/n8n_db_\$DATE.sql

# Backup dos dados
tar -czf \$BACKUP_DIR/data_\$DATE.tar.gz ./data

# Manter apenas backups recentes
find \$BACKUP_DIR -type f -mtime +\${BACKUP_RETENTION_DAYS:-7} -delete
EOL

chmod +x backup.sh

# Criar serviço de backup
cat > /etc/systemd/system/whatsapp-automation-backup.service << EOL
[Unit]
Description=WhatsApp Automation Backup Service
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/whatsapp-automation/backup.sh
EOL

cat > /etc/systemd/system/whatsapp-automation-backup.timer << EOL
[Unit]
Description=Run WhatsApp Automation backup daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOL

# Habilitar backup automático
systemctl enable whatsapp-automation-backup.timer
systemctl start whatsapp-automation-backup.timer

# Iniciar serviços
echo -e "${GREEN}Iniciando serviços...${NC}"
docker-compose up -d

echo -e "${GREEN}Instalação concluída!${NC}"
echo -e "${BLUE}Acesse:${NC}"
echo -e "N8N: https://n8n.seudominio.com"
echo -e "WAHA: https://waha.seudominio.com"
echo -e "Evolution API: https://evolution.seudominio.com"
echo -e "Grafana: https://grafana.seudominio.com"
echo -e "\n${YELLOW}IMPORTANTE: Guarde estas credenciais geradas:${NC}"
echo -e "Postgres Password: ${POSTGRES_PASSWORD}"
echo -e "Evolution API Key: ${EVOLUTION_API_KEY}"
echo -e "\n${YELLOW}Para visualizar os logs:${NC}"
echo -e "docker-compose logs -f" 