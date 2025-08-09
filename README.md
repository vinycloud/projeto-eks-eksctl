# Cluster EKS AWS 

## 📋 Pré-requisitos

### Ferramentas Necessárias

1. **AWS CLI v2**
   ```bash
   # Ubuntu/Debian
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   
   # Verificar instalação
   aws --version
   ```

2. **eksctl**
   ```bash
   # Linux
   curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
   sudo mv /tmp/eksctl /usr/local/bin
   
   # Verificar instalação
   eksctl version
   ```

3. **kubectl**
   ```bash
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   
   # Verificar instalação
   kubectl version --client
   ```

4. **Helm** (opcional, mas recomendado)
   ```bash
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

### Configuração AWS

1. **Configurar credenciais AWS:**
   ```bash
   aws configure
   ```
   
   Você precisará de:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (us-east-1)
   - Default output format (json)

2. **Verificar configuração:**
   ```bash
   aws sts get-caller-identity
   ```

## 🚀 Scripts Disponíveis

### 1. `eks-config.sh`
Arquivo de configuração central com todas as variáveis do cluster.

**Configurações principais:**
- Nome do cluster
- Região AWS
- Versão do Kubernetes
- Tipo de instância dos worker nodes
- Número de nós (min/max/desired)

### 2. `create-eks-cluster.sh`
Script principal para criação do cluster EKS.

**Características do cluster criado:**
- ✅ Node groups gerenciados
- ✅ VPC dedicada com subnets públicas e privadas
- ✅ OIDC provider habilitado
- ✅ AWS Load Balancer Controller configurado
- ✅ Cluster Autoscaler configurado
- ✅ Logging habilitado (CloudWatch)
- ✅ Addons essenciais (VPC CNI, CoreDNS, kube-proxy, EBS CSI)
- ✅ Criptografia de volumes EBS
- ✅ Tags para organização
- ✅ Service accounts com IAM roles

### 3. `delete-eks-cluster.sh`
Script para deleção segura do cluster e limpeza de recursos.

## 📖 Como Usar

### 1. Configurar o Cluster

Edite o arquivo `eks-config.sh` com suas configurações:

```bash
# Exemplo de configuração
export CLUSTER_NAME="meu-cluster-eks"
export REGION="us-east-1"
export NODE_TYPE="t3.medium"
export DESIRED_NODES="2"
```

### 2. Criar o Cluster

```bash
# Dar permissão de execução
chmod +x create-eks-cluster.sh

# Executar criação
./create-eks-cluster.sh
```

O script irá:
1. Verificar pré-requisitos
2. Exibir configurações
3. Solicitar confirmação
4. Criar o cluster (15-20 minutos)
5. Configurar kubectl
6. Instalar componentes adicionais

### 3. Verificar o Cluster

```bash
# Verificar nós
kubectl get nodes

# Verificar pods do sistema
kubectl get pods -A

# Verificar status do cluster
eksctl get cluster --region us-east-1
```

### 4. Deletar o Cluster

```bash
# Dar permissão de execução
chmod +x delete-eks-cluster.sh

# Executar deleção
./delete-eks-cluster.sh
```

## 🏗️ Arquitetura do Cluster

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Account                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  EKS Cluster                        │   │
│  │  ┌─────────────────┐  ┌─────────────────────────┐   │   │
│  │  │   Control Plane │  │     Managed Node Group  │   │   │
│  │  │                 │  │  ┌─────┐ ┌─────┐ ┌─────┐│   │   │
│  │  │  - API Server   │  │  │Node1│ │Node2│ │Node3││   │   │
│  │  │  - etcd         │  │  └─────┘ └─────┘ └─────┘│   │   │
│  │  │  - Scheduler    │  └─────────────────────────┘   │   │
│  │  │  - Controller   │                              │   │
│  │  │    Manager      │                              │   │
│  │  └─────────────────┘                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    VPC                              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │   Public    │  │   Private   │  │   Private   │ │   │
│  │  │   Subnet    │  │   Subnet    │  │   Subnet    │ │   │
│  │  │    AZ-1a    │  │    AZ-1b    │  │    AZ-1c    │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 💰 Estimativa de Custos

### Custos Base (us-east-1):
- **EKS Control Plane**: ~$73/mês
- **Worker Nodes**: Varia por tipo de instância
  - t3.medium (2 nós): ~$60/mês
  - t3.large (2 nós): ~$120/mês
  - m5.large (2 nós): ~$140/mês

### Custos Adicionais:
- EBS volumes: ~$2-5/mês por volume
- Data transfer: Varia por uso
- Load Balancers: ~$16-23/mês cada
- NAT Gateway: ~$45/mês

**Total estimado para setup básico: $130-200/mês**

> ⚠️ **Importante**: Sempre monitore seus custos através do AWS Cost Explorer e configure billing alerts.

## 🔧 Personalização

### Modificar Tipo de Instância
```bash
# No eks-config.sh
export NODE_TYPE="t3.large"  # ou m5.large, c5.xlarge, etc.
```

### Adicionar Tags Personalizadas
Edite o arquivo YAML de configuração no script `create-eks-cluster.sh`:

```yaml
tags:
  Environment: "production"
  Project: "meu-projeto"
  Team: "devops"
  CostCenter: "engineering"
```

### Configurar Acesso SSH (Opcional)
```bash
# 1. Criar key pair na AWS
aws ec2 create-key-pair --key-name minha-chave --query 'KeyMaterial' --output text > minha-chave.pem

# 2. Descomentar no eks-config.sh
export SSH_KEY_NAME="minha-chave"
```

## 🛠️ Troubleshooting

### Problemas Comuns

1. **Erro de permissões IAM**
   ```
   Erro: insufficient permissions
   ```
   **Solução**: Verifique se seu usuário AWS tem as permissões necessárias:
   - AmazonEKSClusterPolicy
   - AmazonEKSWorkerNodePolicy
   - AmazonEC2FullAccess
   - IAMFullAccess

2. **Timeout na criação**
   ```
   Erro: timed out waiting for the condition
   ```
   **Solução**: Aguarde mais tempo ou verifique os logs no CloudWatch

3. **Erro de quotas**
   ```
   Erro: You have requested more instances than your current limit
   ```
   **Solução**: Solicite aumento de quota no AWS Service Quotas

4. **Kubectl não conecta**
   ```bash
   # Reconfigurar kubeconfig
   aws eks update-kubeconfig --region us-east-1 --name seu-cluster
   ```

### Logs e Monitoramento

```bash
# Ver logs do cluster
aws logs describe-log-groups --log-group-name-prefix /aws/eks/

# Monitorar recursos
kubectl top nodes
kubectl top pods -A

# Verificar eventos
kubectl get events --sort-by=.metadata.creationTimestamp
```

## 📚 Comandos Úteis

### Gerenciamento do Cluster
```bash
# Listar clusters
eksctl get cluster --region us-east-1

# Escalar node group
eksctl scale nodegroup --cluster=meu-cluster --name=workers --nodes=3

# Atualizar cluster
eksctl update cluster --name=meu-cluster --region=us-east-1

# Ver configuração do cluster
eksctl get cluster meu-cluster -o yaml
```

### Debugging
```bash
# Verificar status dos nós
kubectl describe nodes

# Ver logs de um pod
kubectl logs -f pod-name -n namespace

# Executar pod de debug
kubectl run debug --image=busybox -it --rm --restart=Never -- sh
```

## 🔒 Segurança

### Boas Práticas Implementadas:
- ✅ Private subnets para worker nodes
- ✅ Criptografia de volumes EBS
- ✅ RBAC habilitado
- ✅ Network policies suportadas
- ✅ Logging habilitado
- ✅ IAM roles com least privilege

### Configurações Adicionais Recomendadas:
- [ ] Pod Security Standards
- [ ] Network Policies
- [ ] Service Mesh (Istio/Linkerd)
- [ ] Image scanning
- [ ] Runtime security

## 📄 Licença

Este projeto é open source e está disponível sob a [MIT License](LICENSE).

## 🤝 Contribuições

Contribuições são bem-vindas! Por favor:

1. Faça um fork do repositório
2. Crie uma branch para sua feature
3. Commit suas mudanças
4. Push para a branch
5. Abra um Pull Request

## 📞 Suporte

Para dúvidas ou problemas:
- Abra uma issue no GitHub
- Consulte a [documentação oficial do EKS](https://docs.aws.amazon.com/eks/)
- Consulte a [documentação do eksctl](https://eksctl.io/)

---

**Desenvolvido por**: DevOps Senior  
**Data**: $(date +%Y-%m-%d)  
**Versão**: 1.0.0
