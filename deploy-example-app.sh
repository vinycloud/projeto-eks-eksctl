#!/bin/bash

# Script de exemplo para deploy de aplicação no EKS
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

# Configurações
NAMESPACE="${NAMESPACE:-default}"
APP_NAME="${APP_NAME:-nginx-demo}"
IMAGE="${IMAGE:-nginx:latest}"
REPLICAS="${REPLICAS:-20}"

# Função para verificar se o cluster está acessível
check_cluster() {
    log "Verificando conectividade com o cluster..."
    
    if ! kubectl cluster-info &> /dev/null; then
        error "Não foi possível conectar ao cluster Kubernetes"
        info "Execute: aws eks update-kubeconfig --region <region> --name <cluster-name>"
        exit 1
    fi
    
    local cluster_name=$(kubectl config current-context | cut -d'/' -f2)
    log "Conectado ao cluster: $cluster_name"
}

# Função para criar namespace se não existir
create_namespace() {
    if [[ "$NAMESPACE" != "default" ]]; then
        log "Criando namespace '$NAMESPACE'..."
        
        if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
            kubectl create namespace "$NAMESPACE"
            log "Namespace '$NAMESPACE' criado"
        else
            info "Namespace '$NAMESPACE' já existe"
        fi
    fi
}

# Função para criar deployment
create_deployment() {
    log "Criando deployment '$APP_NAME'..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
    app: $APP_NAME
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: $APP_NAME
        image: $IMAGE
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
EOF

    log "Deployment criado com sucesso!"
}

# Função para criar service
create_service() {
    log "Criando service '$APP_NAME-service'..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME-service
  namespace: $NAMESPACE
  labels:
    app: $APP_NAME
spec:
  selector:
    app: $APP_NAME
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
EOF

    log "Service criado com sucesso!"
}

# Função para criar ingress (opcional)
create_ingress() {
    log "Criando ingress '$APP_NAME-ingress'..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_NAME-ingress
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingressClassName: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $APP_NAME-service
            port:
              number: 80
EOF

    log "Ingress criado com sucesso!"
}

# Função para verificar status do deployment
check_deployment_status() {
    log "Verificando status do deployment..."
    
    # Aguardar deployment estar pronto
    kubectl wait --for=condition=available --timeout=300s deployment/$APP_NAME -n $NAMESPACE
    
    if [ $? -eq 0 ]; then
        log "Deployment está pronto!"
        
        # Mostrar informações
        echo ""
        info "Informações do deployment:"
        kubectl get deployment $APP_NAME -n $NAMESPACE
        
        echo ""
        info "Pods em execução:"
        kubectl get pods -l app=$APP_NAME -n $NAMESPACE
        
        echo ""
        info "Service criado:"
        kubectl get service $APP_NAME-service -n $NAMESPACE
        
        # Verificar se ingress foi criado
        if kubectl get ingress $APP_NAME-ingress -n $NAMESPACE &> /dev/null; then
            echo ""
            info "Ingress criado:"
            kubectl get ingress $APP_NAME-ingress -n $NAMESPACE
            
            # Aguardar ALB ser provisionado
            warn "Aguardando ALB ser provisionado (pode levar alguns minutos)..."
            sleep 30
            
            local alb_address=$(kubectl get ingress $APP_NAME-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
            if [[ -n "$alb_address" ]]; then
                log "Aplicação acessível em: http://$alb_address"
            else
                info "ALB ainda sendo provisionado. Verifique novamente em alguns minutos."
            fi
        fi
    else
        error "Falha no deployment"
        return 1
    fi
}

# Função para testar a aplicação
test_application() {
    log "Testando aplicação..."
    
    # Teste local via port-forward
    info "Testando via port-forward..."
    
    # Iniciar port-forward em background
    kubectl port-forward service/$APP_NAME-service 8080:80 -n $NAMESPACE &
    local port_forward_pid=$!
    
    # Aguardar port-forward estar pronto
    sleep 5
    
    # Testar conexão
    if curl -s http://localhost:8080 > /dev/null; then
        log "✅ Aplicação respondendo corretamente!"
    else
        warn "❌ Aplicação não está respondendo"
    fi
    
    # Parar port-forward
    kill $port_forward_pid 2>/dev/null || true
}

# Função para mostrar comandos úteis
show_useful_commands() {
    echo ""
    log "Comandos úteis para gerenciar a aplicação:"
    echo ""
    echo "# Verificar status:"
    echo "kubectl get all -l app=$APP_NAME -n $NAMESPACE"
    echo ""
    echo "# Ver logs:"
    echo "kubectl logs -l app=$APP_NAME -n $NAMESPACE --tail=50"
    echo ""
    echo "# Escalar aplicação:"
    echo "kubectl scale deployment $APP_NAME --replicas=3 -n $NAMESPACE"
    echo ""
    echo "# Port-forward para teste local:"
    echo "kubectl port-forward service/$APP_NAME-service 8080:80 -n $NAMESPACE"
    echo ""
    echo "# Deletar aplicação:"
    echo "kubectl delete deployment,service,ingress -l app=$APP_NAME -n $NAMESPACE"
    echo ""
}

# Função principal
main() {
    log "Iniciando deployment da aplicação demo..."
    
    echo "Configurações:"
    echo "  Namespace: $NAMESPACE"
    echo "  App Name: $APP_NAME"
    echo "  Image: $IMAGE"
    echo "  Replicas: $REPLICAS"
    echo ""
    
    # Confirmar deployment
    read -p "Deseja continuar com o deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelado"
        exit 0
    fi
    
    check_cluster
    create_namespace
    create_deployment
    create_service
    
    # Perguntar se quer criar ingress
    read -p "Deseja criar um ALB Ingress para acesso externo? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_ingress
    fi
    
    check_deployment_status
    test_application
    show_useful_commands
    
    log "Deployment concluído com sucesso!"
}

# Verificar argumentos
if [[ $# -gt 0 ]]; then
    case $1 in
        --help|-h)
            echo "Uso: $0 [opções]"
            echo ""
            echo "Variáveis de ambiente:"
            echo "  NAMESPACE    - Namespace Kubernetes (padrão: default)"
            echo "  APP_NAME     - Nome da aplicação (padrão: nginx-demo)"
            echo "  IMAGE        - Imagem Docker (padrão: nginx:latest)"
            echo "  REPLICAS     - Número de réplicas (padrão: 2)"
            echo ""
            echo "Exemplo:"
            echo "  NAMESPACE=demo APP_NAME=minha-app IMAGE=httpd:latest ./deploy-example-app.sh"
            exit 0
            ;;
        *)
            error "Argumento inválido: $1"
            exit 1
            ;;
    esac
fi

# Executar função principal
main "$@"
