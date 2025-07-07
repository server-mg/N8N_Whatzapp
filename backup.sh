#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configurações
BACKUP_DIR="/opt/whatsapp-automation-backups"
MAX_BACKUPS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Por favor, execute como root (sudo)${NC}"
    exit 1
fi

# Criar diretório de backup se não existir
mkdir -p $BACKUP_DIR

# Parar containers para backup consistente
echo -e "${YELLOW}Parando containers...${NC}"
cd /opt/whatsapp-automation
docker-compose stop

# Criar backup
echo -e "${GREEN}Criando backup...${NC}"
backup_file="$BACKUP_DIR/whatsapp-automation-$TIMESTAMP.tar.gz"
tar -czf $backup_file /opt/whatsapp-automation

# Reiniciar containers
echo -e "${YELLOW}Reiniciando containers...${NC}"
docker-compose start

# Remover backups antigos
echo -e "${BLUE}Removendo backups antigos...${NC}"
ls -t $BACKUP_DIR/*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm

# Mostrar status
echo -e "${GREEN}Backup concluído: $backup_file${NC}"
echo -e "${BLUE}Backups disponíveis:${NC}"
ls -lh $BACKUP_DIR/*.tar.gz | awk '{print $9, "(" $5 ")"}' 