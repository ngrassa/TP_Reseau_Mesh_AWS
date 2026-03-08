# TP Mesh OLSR sur AWS — Guide Terraform

## Prérequis

1. **Terraform** installé :
```bash
wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
sudo apt-get install -y unzip
unzip /tmp/terraform.zip -d /tmp
sudo mv /tmp/terraform /usr/local/bin/
terraform version
```

2. **AWS CLI v2** installé et configuré :
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install
aws configure
```

3. **Clé SSH** : `~/.ssh/testkey1.pem` (chmod 400)

## Déploiement

```bash
cd tp-mesh-tf

# Initialiser Terraform (télécharge le provider AWS)
terraform init

# Voir ce qui va être créé
terraform plan

# Déployer l'infrastructure + provisioning OLSR
terraform apply
```

Répondre `yes` à la confirmation.

## Vérification

```bash
# Afficher les IPs et commandes SSH
terraform output mesh_nodes

# Se connecter à un nœud
ssh -i ~/.ssh/testkey1.pem ubuntu@<IP_PUBLIQUE>

# Vérifier OLSR
curl http://localhost:2006/neigh    # Voisins
curl http://localhost:2006/routes   # Table de routage
curl http://localhost:2006/all      # Tout

# Ping entre nœuds
ping -c 3 10.0.1.12

# Test bande passante
# Sur node2 : iperf3 -s
# Sur node1 : iperf3 -c 10.0.1.12

# Capture trafic OLSR
sudo tcpdump -i ens5 udp port 698 -v
```

## Suppression

```bash
terraform destroy
```

Répondre `yes` — tout est nettoyé automatiquement.
