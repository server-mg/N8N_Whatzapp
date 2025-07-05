#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Configurando sistema de backup...${NC}"

# Criar diretório de backup
BACKUP_DIR="/opt/whatsapp-automation/backups"
mkdir -p $BACKUP_DIR

# Criar script de backup
cat > /opt/whatsapp-automation/backup.sh << 'EOL'
#!/bin/bash

# Diretórios
BACKUP_DIR="/opt/whatsapp-automation/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"

# Parar containers
cd /opt/whatsapp-automation
docker-compose stop

# Backup dos volumes
tar -czf $BACKUP_FILE \
    -C /var/lib/docker/volumes/ n8n_data \
    -C /var/lib/docker/volumes/ evolution_instances \
    -C /var/lib/docker/volumes/ evolution_store \
    -C /var/lib/docker/volumes/ postgres_data \
    -C /var/lib/docker/volumes/ redis_data

# Reiniciar containers
docker-compose start

# Manter apenas os últimos 7 backups
find $BACKUP_DIR -type f -name "backup_*.tar.gz" -mtime +7 -delete
EOL

# Dar permissão de execução
chmod +x /opt/whatsapp-automation/backup.sh

# Configurar cron para backup diário às 3 da manhã
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/whatsapp-automation/backup.sh") | crontab -

echo -e "${GREEN}Sistema de backup configurado com sucesso!${NC}"
echo -e "Backups serão realizados diariamente às 3h da manhã"
echo -e "Local dos backups: $BACKUP_DIR" 