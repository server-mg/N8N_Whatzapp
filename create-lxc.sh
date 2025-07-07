#!/bin/bash

# Verificar se está rodando como root
if [ "$(id -u)" != "0" ]; then
   echo "Este script precisa ser executado como root" 
   exit 1
fi

# Verificar se o template existe
TEMPLATE_PATH="/var/lib/vz/template/cache/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "Template não encontrado. Tentando baixar..."
    pveam update
    pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
fi

# Configurações do container
CTID="200"  # ID do container
HOSTNAME="n8n-waha"
MEMORY="4096"  # 4GB RAM
SWAP="2048"   # 2GB SWAP
CORES="2"
DISK="20"     # 20GB

# Criar container
pct create $CTID "$TEMPLATE_PATH" \
  --hostname $HOSTNAME \
  --memory $MEMORY \
  --swap $SWAP \
  --cores $CORES \
  --rootfs local-lvm:$DISK \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --onboot 1 \
  --features nesting=1 \
  --unprivileged 1

# Definir senha root para SSH
pct set $CTID --password 'automacao'

# Verificar se o container foi criado com sucesso
if [ $? -ne 0 ]; then
    echo "Erro ao criar o container"
    exit 1
fi

# Iniciar container
pct start $CTID

# Aguardar container iniciar
echo "Aguardando o container iniciar..."
sleep 15

# Verificar se o container está rodando
if ! pct status $CTID | grep -q running; then
    echo "Erro: Container não está rodando"
    exit 1
fi

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
echo "A senha SSH do root do container é: automacao"