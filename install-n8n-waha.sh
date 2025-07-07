#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Iniciando instalação do ambiente N8N + WAHA${NC}"

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
mkdir -p /opt/n8n-waha
cd /opt/n8n-waha

# Download do docker-compose.yml
echo -e "${GREEN}Baixando arquivo de configuração...${NC}"
wget https://raw.githubusercontent.com/devlikeapro/waha/core/docker-compose/n8n/docker-compose.yaml

# Criar arquivo .env
cat > .env << EOL
N8N_HOST=seu_dominio.com
N8N_PORT=5678
N8N_PROTOCOL=https
WAHA_HOST=seu_dominio.com
WAHA_PORT=3000
WAHA_PROTOCOL=https
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$(openssl rand -base64 32)
POSTGRES_DB=n8n
EOL

# Criar diretório para persistência
mkdir -p ./data/{n8n,waha,postgres}

# Criar script de backup
cat > backup.sh << EOL
#!/bin/bash
BACKUP_DIR="/opt/n8n-waha/backups"
DATE=\$(date +%Y%m%d_%H%M%S)

mkdir -p \$BACKUP_DIR

# Backup do Postgres
docker-compose exec -T postgres pg_dump -U n8n n8n > \$BACKUP_DIR/n8n_db_\$DATE.sql

# Backup dos dados
tar -czf \$BACKUP_DIR/data_\$DATE.tar.gz ./data

# Manter apenas últimos 7 backups
find \$BACKUP_DIR -type f -mtime +7 -delete
EOL

chmod +x backup.sh

# Criar serviço de backup
cat > /etc/systemd/system/n8n-waha-backup.service << EOL
[Unit]
Description=N8N WAHA Backup Service
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/n8n-waha/backup.sh
EOL

cat > /etc/systemd/system/n8n-waha-backup.timer << EOL
[Unit]
Description=Run N8N WAHA backup daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOL

# Habilitar backup automático
systemctl enable n8n-waha-backup.timer
systemctl start n8n-waha-backup.timer

# Iniciar serviços
echo -e "${GREEN}Iniciando serviços...${NC}"
docker-compose up -d

echo -e "${GREEN}Instalação concluída!${NC}"
echo -e "${BLUE}Acesse N8N em: http://localhost:5678${NC}"
echo -e "${BLUE}Acesse WAHA em: http://localhost:3000${NC}"
echo -e "${BLUE}Backups serão realizados diariamente em /opt/n8n-waha/backups${NC}" 