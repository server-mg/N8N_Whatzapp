#!/bin/bash

# Configurações do container
CTID="200"  # ID do container
HOSTNAME="n8n-waha"
MEMORY="4096"  # 4GB RAM
SWAP="2048"   # 2GB SWAP
CORES="2"
DISK="20"     # 20GB
TEMPLATE="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.gz"

# Criar container
pct create $CTID $TEMPLATE \
  --hostname $HOSTNAME \
  --memory $MEMORY \
  --swap $SWAP \
  --cores $CORES \
  --rootfs local-lvm:$DISK \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --onboot 1 \
  --features nesting=1 \
  --unprivileged 1

# Iniciar container
pct start $CTID

# Aguardar container iniciar
sleep 10

# Copiar scripts de instalação
pct push $CTID setup.sh /root/setup.sh
pct push $CTID docker-compose.yml /root/docker-compose.yml

# Dar permissão de execução
pct exec $CTID -- chmod +x /root/setup.sh

# Executar instalação
echo "Container criado e iniciado. Para completar a instalação, execute:"
echo "pct enter $CTID"
echo "cd /root && ./setup.sh"

echo "Container criado e configurado com sucesso!"
echo "Acesse o container via: pct enter $CTID"
echo "N8N estará disponível em: http://<IP-DO-CONTAINER>:5678"
echo "WAHA estará disponível em: http://<IP-DO-CONTAINER>:3000"
echo "Grafana estará disponível em: http://<IP-DO-CONTAINER>:3001" 