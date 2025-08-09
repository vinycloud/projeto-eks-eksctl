#!/bin/bash

# Script para verificar e instalar pré-requisitos para EKS
# Autor: Vinicius Fialho
# Data: $(date +%Y-%m-%d)

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Função para detectar o SO
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "ubuntu"
        elif command -v yum &> /dev/null; then
            echo "rhel"
        elif command -v pacman &> /dev/null; then
            echo "arch"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Função para instalar AWS CLI
install_aws_cli() {
    local os=$(detect_os)
    
    log "Instalando AWS CLI v2..."
    
    case $os in
        "ubuntu")
            sudo apt-get update
            sudo apt-get install -y curl unzip
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
            rm -rf aws awscliv2.zip
            ;;
        "rhel")
            sudo yum install -y curl unzip
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
            rm -rf aws awscliv2.zip
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install awscli
            else
                curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
                sudo installer -pkg AWSCLIV2.pkg -target /
                rm AWSCLIV2.pkg
            fi
            ;;
        *)
            error "SO não suportado para instalação automática. Instale manualmente: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
            return 1
            ;;
    esac
}

# Função para instalar eksctl
install_eksctl() {
    local os=$(detect_os)
    
    log "Instalando eksctl..."
    
    case $os in
        "ubuntu"|"rhel"|"linux")
            curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
            sudo mv /tmp/eksctl /usr/local/bin
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew tap weaveworks/tap
                brew install weaveworks/tap/eksctl
            else
                curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Darwin_amd64.tar.gz" | tar xz -C /tmp
                sudo mv /tmp/eksctl /usr/local/bin
            fi
            ;;
        *)
            error "SO não suportado para instalação automática"
            return 1
            ;;
    esac
}

# Função para instalar kubectl
install_kubectl() {
    local os=$(detect_os)
    
    log "Instalando kubectl..."
    
    case $os in
        "ubuntu"|"rhel"|"linux")
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
            rm kubectl
            ;;
        "macos")
            if command -v brew &> /dev/null; then
                brew install kubectl
            else
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
                chmod +x ./kubectl
                sudo mv ./kubectl /usr/local/bin/kubectl
            fi
            ;;
        *)
            error "SO não suportado para instalação automática"
            return 1
            ;;
    esac
}

# Função para instalar Helm
install_helm() {
    log "Instalando Helm..."
    
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

# Função para verificar se uma ferramenta está instalada
check_tool() {
    local tool=$1
    local min_version=$2
    
    if command -v "$tool" &> /dev/null; then
        local version=$($tool version --short 2>/dev/null || $tool version 2>/dev/null | head -1 || echo "unknown")
        log "$tool está instalado: $version"
        return 0
    else
        warn "$tool não está instalado"
        return 1
    fi
}

# Função principal de verificação
check_prerequisites() {
    log "Verificando pré-requisitos para EKS..."
    
    local missing_tools=()
    
    # Verificar AWS CLI
    if ! check_tool "aws" "2.0"; then
        missing_tools+=("aws")
    fi
    
    # Verificar eksctl
    if ! check_tool "eksctl" "0.100"; then
        missing_tools+=("eksctl")
    fi
    
    # Verificar kubectl
    if ! check_tool "kubectl" "1.20"; then
        missing_tools+=("kubectl")
    fi
    
    # Verificar Helm (opcional)
    if ! check_tool "helm" "3.0"; then
        info "Helm não encontrado (opcional)"
    fi
    
    # Verificar outras dependências
    local deps=("curl" "unzip" "tar")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_tools+=("$dep")
        fi
    done
    
    return ${#missing_tools[@]}
}

# Função para instalar ferramentas faltantes
install_missing_tools() {
    log "Instalando ferramentas faltantes..."
    
    local os=$(detect_os)
    
    # Instalar dependências básicas
    case $os in
        "ubuntu")
            sudo apt-get update
            sudo apt-get install -y curl unzip tar
            ;;
        "rhel")
            sudo yum install -y curl unzip tar
            ;;
        "macos")
            # Geralmente já estão instaladas no macOS
            ;;
    esac
    
    # Verificar e instalar AWS CLI
    if ! command -v aws &> /dev/null; then
        install_aws_cli
    fi
    
    # Verificar e instalar eksctl
    if ! command -v eksctl &> /dev/null; then
        install_eksctl
    fi
    
    # Verificar e instalar kubectl
    if ! command -v kubectl &> /dev/null; then
        install_kubectl
    fi
    
    # Oferecer instalação do Helm
    if ! command -v helm &> /dev/null; then
        read -p "Deseja instalar o Helm? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_helm
        fi
    fi
}

# Função para configurar AWS
configure_aws() {
    log "Configurando AWS CLI..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        warn "AWS CLI não está configurado"
        
        read -p "Deseja configurar agora? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            aws configure
            
            # Testar configuração
            if aws sts get-caller-identity &> /dev/null; then
                log "AWS CLI configurado com sucesso!"
            else
                error "Falha na configuração do AWS CLI"
                return 1
            fi
        else
            warn "Execute 'aws configure' manualmente antes de criar o cluster"
        fi
    else
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local user_arn=$(aws sts get-caller-identity --query Arn --output text)
        log "AWS CLI já configurado:"
        echo "  Account ID: $account_id"
        echo "  User/Role: $user_arn"
    fi
}

# Função para verificar permissões AWS
check_aws_permissions() {
    log "Verificando permissões AWS..."
    
    local required_services=("eks" "ec2" "iam" "cloudformation")
    local missing_permissions=()
    
    for service in "${required_services[@]}"; do
        case $service in
            "eks")
                if ! aws eks list-clusters --region us-east-1 &> /dev/null; then
                    missing_permissions+=("EKS")
                fi
                ;;
            "ec2")
                if ! aws ec2 describe-regions &> /dev/null; then
                    missing_permissions+=("EC2")
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    missing_permissions+=("IAM")
                fi
                ;;
            "cloudformation")
                if ! aws cloudformation list-stacks --max-items 1 &> /dev/null; then
                    missing_permissions+=("CloudFormation")
                fi
                ;;
        esac
    done
    
    if [ ${#missing_permissions[@]} -eq 0 ]; then
        log "Permissões AWS verificadas com sucesso!"
    else
        error "Permissões faltantes: ${missing_permissions[*]}"
        warn "Você precisará das seguintes políticas IAM:"
        echo "  - AmazonEKSClusterPolicy"
        echo "  - AmazonEKSWorkerNodePolicy"
        echo "  - AmazonEC2FullAccess"
        echo "  - IAMFullAccess"
        echo "  - CloudFormationFullAccess"
        return 1
    fi
}

# Função para exibir resumo
show_summary() {
    log "Resumo da verificação:"
    echo ""
    
    info "Ferramentas instaladas:"
    check_tool "aws" "2.0" || echo "  ❌ AWS CLI"
    check_tool "eksctl" "0.100" || echo "  ❌ eksctl"
    check_tool "kubectl" "1.20" || echo "  ❌ kubectl"
    check_tool "helm" "3.0" || echo "  ⚠️  Helm (opcional)"
    
    echo ""
    info "Próximos passos:"
    echo "  1. Edite eks-config.sh com suas configurações"
    echo "  2. Execute ./create-eks-cluster.sh"
    echo "  3. Aguarde a criação do cluster (15-20 minutos)"
    echo ""
}

# Função principal
main() {
    log "Iniciando verificação de pré-requisitos para EKS..."
    
    local os=$(detect_os)
    info "Sistema operacional detectado: $os"
    
    # Verificar se precisa de sudo
    if [[ $EUID -eq 0 ]]; then
        warn "Executando como root. Isso pode causar problemas."
    fi
    
    # Verificar pré-requisitos
    if check_prerequisites; then
        log "Todos os pré-requisitos estão instalados!"
    else
        warn "Algumas ferramentas estão faltando"
        
        read -p "Deseja instalar automaticamente? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_missing_tools
        else
            info "Instale manualmente as ferramentas faltantes"
            exit 1
        fi
    fi
    
    # Configurar AWS
    configure_aws
    
    # Verificar permissões
    check_aws_permissions
    
    # Exibir resumo
    show_summary
    
    log "Verificação concluída com sucesso!"
}

# Executar função principal
main "$@"
