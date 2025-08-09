#!/bin/bash

# Script para criação de cluster EKS na AWS usando Managed Node Groups
# Autor: Vinicius Fialho
# Data: $(date +%Y-%m-%d)
#
# Funcionalidades:
# 1. Managed Node Groups
#    - Controle total sobre configurações de nodes
#    - Disponível em todas as regiões AWS
#    - Flexibilidade para customizações avançadas
#
# 2. Diagnóstico de Cluster Existente
#    - Use: ./create-eks-cluster.sh --diagnose
#    - Verifica se Load Balancer Controller está funcionando

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Configurações do cluster
CLUSTER_NAME="${CLUSTER_NAME:-cluster-devops}"
REGION="${REGION:-us-east-1}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.33}"

# Configurações para Managed Node Groups
NODE_GROUP_NAME="${NODE_GROUP_NAME:-workers}"
NODE_TYPE="${NODE_TYPE:-t3a.medium}"
MIN_NODES="${MIN_NODES:-1}"
MAX_NODES="${MAX_NODES:-3}"
DESIRED_NODES="${DESIRED_NODES:-2}"

# Função para exibir configurações
show_config() {
    log "Configurações do cluster EKS com Managed Node Groups:"
    echo "  Nome do Cluster: $CLUSTER_NAME"
    echo "  Região: $REGION"
    echo "  Versão Kubernetes: $KUBERNETES_VERSION"
    echo "  Nome do Node Group: $NODE_GROUP_NAME"
    echo "  Tipo de Instância: $NODE_TYPE"
    echo "  Nós Mínimos: $MIN_NODES"
    echo "  Nós Máximos: $MAX_NODES"
    echo "  Nós Desejados: $DESIRED_NODES"
    echo ""
}
check_prerequisites() {
    log "Verificando pré-requisitos para criação do cluster EKS..."
    
    # Verificar se eksctl está instalado
    if ! command -v eksctl &> /dev/null; then
        error "eksctl não encontrado. Por favor, instale o eksctl primeiro."
        info "Instruções: https://eksctl.io/introduction/#installation"
        exit 1
    fi
    
    # Verificar versão do eksctl
    local eksctl_version=$(eksctl version -o json 2>/dev/null | grep -oP '"Version":\s*"\K[0-9.]+' || eksctl version 2>/dev/null | grep -oP 'version:\s*\K[0-9.]+')
    info "Versão do eksctl: $eksctl_version"
    
    # Verificar se AWS CLI está instalado
    if ! command -v aws &> /dev/null; then
        error "AWS CLI não encontrado. Por favor, instale o AWS CLI primeiro."
        exit 1
    fi
    
    # Verificar se kubectl está instalado
    if ! command -v kubectl &> /dev/null; then
        warn "kubectl não encontrado. Recomenda-se instalar o kubectl."
    fi
    
    # Verificar credenciais AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        error "Credenciais AWS não configuradas ou inválidas."
        info "Execute: aws configure"
        exit 1
    fi
    
    log "Pré-requisitos verificados com sucesso!"
}

# Função para criar o cluster
create_cluster() {
    create_cluster_managed_nodegroups
}



# Função para criar cluster com Managed Node Groups
create_cluster_managed_nodegroups() {
    log "Criando cluster EKS com Managed Node Groups: $CLUSTER_NAME..."
    
    # Criar arquivo de configuração temporário para Managed Node Groups
    local config_file="/tmp/eks-cluster-config-managed.yaml"
    
    cat > "$config_file" <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: $CLUSTER_NAME
  region: $REGION
  version: "$KUBERNETES_VERSION"

# Configurações de rede
vpc:
  cidr: "10.0.0.0/16"
  nat:
    gateway: HighlyAvailable

# IAM roles
iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true
  - metadata:
      name: cluster-autoscaler
      namespace: kube-system
    wellKnownPolicies:
      autoScaler: true

# Node groups gerenciados
managedNodeGroups:
- name: $NODE_GROUP_NAME
  instanceType: $NODE_TYPE
  minSize: $MIN_NODES
  maxSize: $MAX_NODES
  desiredCapacity: $DESIRED_NODES
  
  # Configurações de armazenamento
  volumeSize: 20
  volumeType: gp3
  volumeEncrypted: true
  
  # Labels
  labels:
    Environment: "production"
    ManagedBy: "eksctl"
    Team: "devops"
    
  # Configurações de rede
  privateNetworking: true
  
  # Configurações do sistema
  amiFamily: AmazonLinux2023
  
  # Políticas IAM adicionais
  iam:
    attachPolicyARNs:
    - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Addons
addons:
- name: vpc-cni
  version: latest
- name: coredns
  version: latest
- name: kube-proxy
  version: latest
- name: aws-ebs-csi-driver
  version: latest
  wellKnownPolicies:
    ebsCSIController: true

# Logging
cloudWatch:
  clusterLogging:
    enableTypes: ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    logRetentionInDays: 7

EOF

    info "Configuração gerada em: $config_file"
    
    # Criar o cluster
    log "Iniciando criação do cluster (isso pode levar 15-20 minutos)..."
    if eksctl create cluster -f "$config_file" --verbose 4; then
        log "Cluster criado com sucesso!"
        rm -f "$config_file"
        return 0
    else
        error "Falha na criação do cluster"
        rm -f "$config_file"
        return 1
    fi
}

# Função para configurar kubectl
configure_kubectl() {
    log "Configurando kubectl..."
    
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
    
    if [ $? -eq 0 ]; then
        log "kubectl configurado com sucesso!"
        
        # Testar conexão
        info "Testando conexão com o cluster..."
        kubectl get nodes
        kubectl get pods -A
    else
        error "Falha na configuração do kubectl"
        exit 1
    fi
}


install_additional_components() {
    log "Instalando componentes adicionais para Managed Node Groups..."
    
    # AWS Load Balancer Controller
    info "Instalando AWS Load Balancer Controller..."
    
    # Instalar via Helm (se disponível) ou manifests
    if command -v helm &> /dev/null; then
        helm repo add eks https://aws.github.io/eks-charts
        helm repo update
        
        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName="$CLUSTER_NAME" \
            --set serviceAccount.create=false \
            --set serviceAccount.name=aws-load-balancer-controller
    else
        warn "Helm não encontrado. AWS Load Balancer Controller pode ser instalado manualmente."
        info "Para instalar manualmente:"
        echo "  1. Instale o Helm: https://helm.sh/docs/intro/install/"
        echo "  2. Execute o script novamente ou instale manualmente via manifests YAML"
    fi
    
    # Metrics Server (se não estiver presente)
    info "Verificando Metrics Server..."
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        info "Instalando Metrics Server..."
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    else
        log "Metrics Server já está instalado."
    fi
    
    log "Componentes adicionais instalados!"
}

# Função para exibir informações finais
show_cluster_info() {
    log "Informações do cluster EKS com Managed Node Groups criado:"
    
    echo ""
    info "Comandos úteis para Managed Node Groups:"
    echo "  # Verificar status do cluster:"
    echo "  eksctl get cluster --region $REGION"
    echo ""
    echo "  # Verificar node groups:"
    echo "  eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION"
    echo ""
    echo "  # Verificar nós:"
    echo "  kubectl get nodes -o wide"
    echo ""
    echo "  # Verificar pods do sistema:"
    echo "  kubectl get pods -A"
    echo ""
    echo "  # Verificar service accounts com IRSA:"
    echo "  kubectl get serviceaccounts -A"
    echo ""
    echo "  # Verificar addons instalados:"
    echo "  aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION"
    echo ""
    echo "  # Testar o Load Balancer Controller:"
    echo "  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/examples/2048/2048_full.yaml"
    echo ""
    echo "  # Atualizar kubeconfig (caso necessário):"
    echo "  aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
    echo ""
    
    info "Características dos Managed Node Groups:"
    echo "  ✓ Controle total sobre configurações de nodes"
    echo "  ✓ Disponível em todas as regiões AWS"
    echo "  ✓ Flexibilidade para customizações"
    echo "  ✓ Suporte a múltiplos tipos de instância"
    echo "  ✓ Escalabilidade automática configurável"
    echo "  ✓ Suporte para diferentes tipos de AMI"
    echo ""
    
    warn "IMPORTANTE:"
    echo "  - O cluster criado incorre em custos na AWS"
    echo "  - Para deletar o cluster: eksctl delete cluster --name $CLUSTER_NAME --region $REGION"
    echo "  - Monitore os custos através do AWS Cost Explorer"
    echo ""
}

# Função para diagnosticar cluster existente
diagnose_existing_cluster() {
    log "Modo de diagnóstico para cluster existente"
    
    # Verificar se kubectl está configurado
    if ! kubectl cluster-info &>/dev/null; then
        error "kubectl não está configurado ou cluster não está acessível"
        info "Configure o kubectl: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
        exit 1
    fi
    
    # Obter informações do cluster atual
    local current_cluster=$(kubectl config current-context | cut -d'/' -f2 2>/dev/null || echo "unknown")
    log "Diagnosticando cluster: $current_cluster"
    
    echo ""
    info "=== DIAGNÓSTICO DO CLUSTER ==="
    
    # 1. Verificar namespace kube-system
    info "1. Verificando namespace kube-system..."
    kubectl get namespace kube-system &>/dev/null && log "✓ Namespace kube-system existe" || warn "✗ Namespace kube-system não encontrado"
    
    # 2. Verificar nodes
    info "2. Verificando nodes do cluster..."
    kubectl get nodes -o wide
    
    # 3. Verificar pods do sistema
    info "3. Verificando pods do sistema..."
    kubectl get pods -n kube-system
    
    # 4. Verificar addons EKS
    info "4. Verificando addons EKS..."
    local addons=$(aws eks list-addons --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'addons' --output text 2>/dev/null)
    if [[ -n "$addons" ]]; then
        log "✓ Addons encontrados: $addons"
    else
        warn "✗ Nenhum addon encontrado no cluster"
    fi
    
    # 5. Verificar AWS Load Balancer Controller
    info "5. Verificando AWS Load Balancer Controller..."
    if kubectl get deployment aws-load-balancer-controller -n kube-system &>/dev/null; then
        log "✓ AWS Load Balancer Controller encontrado"
        kubectl get deployment aws-load-balancer-controller -n kube-system
    else
        warn "✗ AWS Load Balancer Controller não encontrado"
    fi
    
    # 6. Verificar Service Accounts
    info "6. Verificando Service Accounts com IRSA..."
    kubectl get serviceaccounts -A | grep -E "aws-load-balancer-controller|cluster-autoscaler" || info "Nenhum service account específico encontrado"
    
    echo ""
    info "=== COMANDOS PARA SOLUÇÃO MANUAL ==="
    echo ""
    echo "# 1. Instalar Load Balancer Controller como addon:"
    echo "aws eks create-addon \\"
    echo "  --cluster-name $CLUSTER_NAME \\"
    echo "  --addon-name aws-load-balancer-controller \\"
    echo "  --region $REGION \\"
    echo "  --resolve-conflicts OVERWRITE"
    echo ""
    echo "# 2. Verificar status do addon:"
    echo "aws eks describe-addon \\"
    echo "  --cluster-name $CLUSTER_NAME \\"
    echo "  --addon-name aws-load-balancer-controller \\"
    echo "  --region $REGION"
    echo ""
    echo "# 3. Se addon falhar, instalar via Helm:"
    echo "helm repo add eks https://aws.github.io/eks-charts"
    echo "helm install aws-load-balancer-controller eks/aws-load-balancer-controller \\"
    echo "  -n kube-system \\"
    echo "  --set clusterName=$CLUSTER_NAME \\"
    echo "  --set serviceAccount.create=true \\"
    echo "  --set serviceAccount.name=aws-load-balancer-controller"
}

# Verificar se script foi chamado com parâmetro de diagnóstico
if [[ "${1:-}" == "--diagnose" || "${1:-}" == "-d" ]]; then
    diagnose_existing_cluster
    exit 0
fi
main() {
    log "Script de criação de cluster EKS com Managed Node Groups"
    echo ""
    
    # Exibir configurações
    show_config
    
    # Confirmar criação
    read -p "Deseja continuar com a criação do cluster? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operação cancelada pelo usuário."
        exit 0
    fi
    
    check_prerequisites
    
    # Criar o cluster
    if create_cluster; then
        configure_kubectl
        install_additional_components
        show_cluster_info
        log "Processo concluído com sucesso!"
    else
        error "Falha na criação do cluster com Managed Node Groups"
        exit 1
    fi
}

# Função de limpeza em caso de erro
cleanup() {
    error "Script interrompido. Executando limpeza..."
    # Adicionar comandos de limpeza se necessário
    exit 1
}

# Trap para capturar sinais de interrupção
trap cleanup INT TERM

# Verificar se o script está sendo executado como root (não recomendado)
if [[ $EUID -eq 0 ]]; then
    warn "Executando como root. Recomenda-se usar um usuário não-root."
fi

# Executar função principal
main "$@"
