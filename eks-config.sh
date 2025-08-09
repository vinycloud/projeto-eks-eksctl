#!/bin/bash

# Este arquivo permite customizar as configurações do cluster EKS
# Autor: Vinicius Fialho
# Data: $(date +%Y-%m-%d)
# Descrição: Configurações básicas para criar um cluster EKS na AWS

# =============================================================================
# CONFIGURAÇÕES DO CLUSTER
# =============================================================================

# Nome do cluster (deve ser único na sua conta AWS)
export CLUSTER_NAME="cluster-devops"

# Região AWS onde o cluster será criado
export REGION="us-east-1"

# Versão do Kubernetes (recomenda-se usar versões estáveis)
export KUBERNETES_VERSION="1.33"

# =============================================================================
# CONFIGURAÇÕES DO NODE GROUP
# =============================================================================

# Nome do node group
export NODE_GROUP_NAME="workers"

# Tipo de instância EC2 para os worker nodes
# Opções comuns: t3.small, t3.medium, t3.large, m5.large, etc.
export NODE_TYPE="t3a.medium"

# Número mínimo de nós
export MIN_NODES="1"

# Número máximo de nós
export MAX_NODES="3"

# Número desejado de nós
export DESIRED_NODES="2"

# =============================================================================
# CONFIGURAÇÕES AVANÇADAS (OPCIONAL)
# =============================================================================

# Par de chaves SSH (descomente se quiser acesso SSH aos nós)
# export SSH_KEY_NAME="my-key-pair"

# CIDR da VPC (se quiser customizar)
# export VPC_CIDR="10.0.0.0/16"

# Tags adicionais (formato: key1=value1,key2=value2)
# export ADDITIONAL_TAGS="Project=DevOpsPro,Environment=Production"

# =============================================================================
# FUNÇÕES DE UTILIDADE
# =============================================================================

# Função para validar configurações
validate_config() {
    echo "Validando configurações..."
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        echo "ERRO: CLUSTER_NAME não pode estar vazio"
        exit 1
    fi
    
    if [[ -z "$REGION" ]]; then
        echo "ERRO: REGION não pode estar vazio"
        exit 1
    fi
    
    if [[ $MIN_NODES -gt $MAX_NODES ]]; then
        echo "ERRO: MIN_NODES não pode ser maior que MAX_NODES"
        exit 1
    fi
    
    if [[ $DESIRED_NODES -lt $MIN_NODES || $DESIRED_NODES -gt $MAX_NODES ]]; then
        echo "ERRO: DESIRED_NODES deve estar entre MIN_NODES e MAX_NODES"
        exit 1
    fi
    
    echo "Configurações validadas com sucesso!"
}

# Função para exibir todas as configurações
show_all_config() {
    echo "==================================="
    echo "CONFIGURAÇÕES DO CLUSTER EKS"
    echo "==================================="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Region: $REGION"
    echo "Kubernetes Version: $KUBERNETES_VERSION"
    echo ""
    echo "Node Group Name: $NODE_GROUP_NAME"
    echo "Instance Type: $NODE_TYPE"
    echo "Min Nodes: $MIN_NODES"
    echo "Max Nodes: $MAX_NODES"
    echo "Desired Nodes: $DESIRED_NODES"
    echo "==================================="
}

# Função para estimar custos
estimate_costs() {
    echo "==================================="
    echo "ESTIMATIVA DE CUSTOS (us-east-1)"
    echo "==================================="
    
    # Custos aproximados para us-east-1 (valores podem variar)
    case $NODE_TYPE in
        "t3.small")
            cost_per_hour=0.0208
            ;;
        "t3.medium")
            cost_per_hour=0.0416
            ;;
        "t3.large")
            cost_per_hour=0.0832
            ;;
        "m5.large")
            cost_per_hour=0.096
            ;;
        *)
            cost_per_hour=0.05  # Estimativa genérica
            ;;
    esac
    
    # Custo do control plane EKS
    eks_control_plane_cost=0.10  # $0.10 por hora
    
    # Cálculo mensal
    hours_per_month=730
    monthly_node_cost=$(echo "$cost_per_hour * $DESIRED_NODES * $hours_per_month" | bc -l)
    monthly_control_plane_cost=$(echo "$eks_control_plane_cost * $hours_per_month" | bc -l)
    total_monthly_cost=$(echo "$monthly_node_cost + $monthly_control_plane_cost" | bc -l)
    
    printf "Control Plane EKS: \$%.2f/mês\n" $monthly_control_plane_cost
    printf "Worker Nodes (%d x %s): \$%.2f/mês\n" $DESIRED_NODES $NODE_TYPE $monthly_node_cost
    printf "TOTAL ESTIMADO: \$%.2f/mês\n" $total_monthly_cost
    echo ""
    echo "NOTA: Valores aproximados, não incluem:"
    echo "- Tráfego de dados"
    echo "- Armazenamento EBS adicional"
    echo "- Load Balancers"
    echo "- Outros serviços AWS"
    echo "==================================="
}

# Se o script for executado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_config
    show_all_config
    
    if command -v bc &> /dev/null; then
        echo ""
        estimate_costs
    fi
fi
