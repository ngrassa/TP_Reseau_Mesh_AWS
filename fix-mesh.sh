#!/bin/bash
#============================================================================
# fix-mesh.sh — Configurer le réseau mesh via VXLAN sur AWS
# Exécuter depuis la machine de contrôle (ip-172-31-45-47)
#============================================================================

SSH_KEY="$HOME/.ssh/labuser.pem"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Nœuds : IP_PUBLIQUE DERNIER_OCTET
NODES=(
  "52.87.188.48 11"
  "3.82.54.142 12"
  "54.198.184.37 13"
  "32.192.209.229 14"
  "34.230.28.56 15"
)

for entry in "${NODES[@]}"; do
  set -- $entry
  PUB_IP=$1
  LAST=$2
  echo "=== Configuration VXLAN sur node${LAST} (${PUB_IP}) ==="

  ssh $SSH_OPTS -i "$SSH_KEY" ubuntu@$PUB_IP "sudo bash -s" <<REMOTE_SCRIPT
set -e

# ── Nettoyer tout ──
systemctl stop olsrd 2>/dev/null || true
ip link del mesh0 2>/dev/null || true
ip link del vxmesh 2>/dev/null || true
# Supprimer les anciens tunnels GRE
for iface in \$(ip -o link show | grep -oP 'tun\d+|gretap\d+' | sort -u); do
  ip link del \$iface 2>/dev/null || true
done

# ── Créer l'interface VXLAN ──
# VNI 42, groupe multicast remplacé par unicast via bridge fdb
ip link add vxmesh type vxlan id 42 dev eth0 dstport 4789 local 10.0.1.${LAST} nolearning
ip addr add 192.168.100.${LAST}/24 dev vxmesh
ip link set vxmesh up

# ── Ajouter les voisins statiques (unicast, pas de multicast) ──
for REMOTE in 11 12 13 14 15; do
  if [ \$REMOTE != ${LAST} ]; then
    bridge fdb append 00:00:00:00:00:00 dev vxmesh dst 10.0.1.\${REMOTE}
  fi
done

echo "  Interfaces :"
ip addr show vxmesh | grep -E "inet |state"

# ── Configurer OLSR ──
cat > /etc/olsrd/olsrd.conf <<ENDCONF
DebugLevel  1
IpVersion   4
UseHysteresis       no
LinkQualityLevel            2
LinkQualityFishEye          1
LinkQualityAlgorithm        "etx_ff"

LoadPlugin "olsrd_txtinfo.so.1.1"
{
    PlParam "port"   "2006"
    PlParam "accept" "0.0.0.0"
}

Interface "vxmesh"
{
    HelloInterval       2.0
    HelloValidityTime   6.0
    TcInterval          5.0
    TcValidityTime      15.0
    MidInterval         5.0
    MidValidityTime     15.0
    HnaInterval         5.0
    HnaValidityTime     15.0
}
ENDCONF

systemctl restart olsrd
echo "  ✓ node${LAST} OK"
REMOTE_SCRIPT
done

echo ""
echo "=== Attente de la convergence (15s) ==="
sleep 15

echo ""
echo "=== Vérification depuis node11 ==="
ssh $SSH_OPTS -i "$SSH_KEY" ubuntu@${NODES[0]%% *} '
echo "--- VOISINS ---"
curl -s http://localhost:2006/neigh
echo ""
echo "--- ROUTES ---"
curl -s http://localhost:2006/routes
echo ""
echo "--- PING mesh ---"
for i in 11 12 13 14 15; do
  ping -c 1 -W 1 192.168.100.$i 2>/dev/null | grep -E "from|100%"
done
'
