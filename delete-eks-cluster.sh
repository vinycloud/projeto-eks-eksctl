#!/bin/bash

# Descrição: Este script automatiza o processo de deleção de um cluster EKS,
# incluindo a remoção de recursos associados como node groups, fargate profiles,
# e a limpeza de configurações do kubectl.
# Uso: ./delete-eks-cluster.sh
# Data: $(date +%Y-%m-%d)
# Autor: Vinicius Fialho

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de logging
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Carregar configurações se disponível
if [[ -f "eks-config.sh" ]]; then
    source eks-config.sh
else
    # Configurações padrão
    CLUSTER_NAME="${CLUSTER_NAME:-cluster-devops}"
    REGION="${REGION:-us-east-1}"
fi

# Função para verificar se o cluster existe
check_cluster_exists() {
    log "Verificando se o cluster '$CLUSTER_NAME' existe..."
    
    if eksctl get cluster --name "$CLUSTER_NAME" --region "$REGION" &> /dev/null; then
        log "Cluster encontrado: $CLUSTER_NAME"
        return 0
    else
        error "Cluster '$CLUSTER_NAME' não encontrado na região '$REGION'"
        return 1
    fi
}

# Função para listar recursos do cluster
list_cluster_resources() {
    log "Listando recursos do cluster..."
    
    echo ""
    info "Cluster Info:"
    eksctl get cluster --name "$CLUSTER_NAME" --region "$REGION" || true
    
    echo ""
    info "Node Groups:"
    eksctl get nodegroup --cluster "$CLUSTER_NAME" --region "$REGION" || true
    
    echo ""
    info "Fargate Profiles (se existirem):"
    eksctl get fargateprofile --cluster "$CLUSTER_NAME" --region "$REGION" || true
    
    echo ""
    info "OIDC Identity Provider:"
    eksctl get iamidentitymapping --cluster "$CLUSTER_NAME" --region "$REGION" || true
    
    echo ""
}

# Função para deletar recursos do cluster
delete_cluster() {
    log "Iniciando deleção do cluster '$CLUSTER_NAME'..."
    
    # Confirmar deleção
    warn "ATENÇÃO: Esta operação é IRREVERSÍVEL!"
    warn "Todos os dados e configurações do cluster serão perdidos."
    echo ""
    read -p "Tem certeza que deseja deletar o cluster '$CLUSTER_NAME'? Digite 'DELETE' para confirmar: " confirm
    
    if [[ "$confirm" != "DELETE" ]]; then
        info "Operação cancelada pelo usuário."
        exit 0
    fi
    
    # Deletar o cluster
    log "Deletando cluster... (isso pode levar 10-15 minutos)"
    
    if eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --wait; then
        log "Cluster '$CLUSTER_NAME' deletado com sucesso!"
    else
        error "Falha na deleção do cluster"
        return 1
    fi
}

# Função para limpeza manual de recursos órfãos
cleanup_orphaned_resources() {
    warn "Verificando recursos órfãos que podem ter ficado..."
    
    info "Verificando Load Balancers..."
    aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')]" --output table || true
    
    info "Verificando Security Groups..."
    aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=*$CLUSTER_NAME*" --query "SecurityGroups[].{GroupId:GroupId,GroupName:GroupName}" --output table || true
    
    info "Verificando NAT Gateways..."
    aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=tag:Name,Values=*$CLUSTER_NAME*" --query "NatGateways[].{NatGatewayId:NatGatewayId,State:State}" --output table || true
    
    echo ""
    warn "Se houver recursos órfãos listados acima, você pode precisar deletá-los manualmente para evitar custos."
    warn "Use o AWS Console ou AWS CLI para verificar e deletar recursos não utilizados."
}

# Função para remover configuração do kubectl
cleanup_kubectl_config() {
    log "Removendo configuração do kubectl..."
    
    # Remover contexto do kubectl
    if kubectl config get-contexts | grep -q "$CLUSTER_NAME"; then
        kubectl config delete-context "arn:aws:eks:$REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$CLUSTER_NAME" || true
        log "Contexto removido do kubectl"
    fi
    
    # Verificar contexto atual
    current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    if [[ "$current_context" != "none" ]]; then
        info "Contexto atual do kubectl: $current_context"
    else
        info "Nenhum contexto ativo no kubectl"
    fi
}

# Função principal
main() {
    log "Iniciando processo de deleção do cluster EKS..."
    
    # Verificar pré-requisitos
    if ! command -v eksctl &> /dev/null; then
        error "eksctl não encontrado"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI não encontrado"
        exit 1
    fi
    
    # Verificar credenciais
    if ! aws sts get-caller-identity &> /dev/null; then
        error "Credenciais AWS não configuradas"
        exit 1
    fi
    
    echo "Cluster: $CLUSTER_NAME"
    echo "Região: $REGION"
    echo ""
    
    # Verificar se cluster existe
    if ! check_cluster_exists; then
        exit 1
    fi
    
    # Listar recursos
    list_cluster_resources
    
    # Deletar cluster
    delete_cluster
    
    # Limpeza
    cleanup_kubectl_config
    cleanup_orphaned_resources
    
    log "Processo de deleção concluído!"
    info "Verifique o AWS Console para confirmar que todos os recursos foram removidos."
}

# Executar função principal
main "$@"
