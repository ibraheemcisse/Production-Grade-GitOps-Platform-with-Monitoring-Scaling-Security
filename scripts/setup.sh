#!/bin/bash
# scripts/setup.sh - Main setup script for GitOps Platform

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="gitops-platform"
ENVIRONMENT="dev"
AWS_REGION="us-west-2"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-cluster"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local deps=("terraform" "kubectl" "helm" "aws" "argocd" "docker")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Please install the missing dependencies and run the script again."
        exit 1
    fi
    
    log_success "All dependencies are installed"
}

setup_terraform_backend() {
    log_info "Setting up Terraform backend..."
    
    # Create S3 bucket for Terraform state
    BUCKET_NAME="${PROJECT_NAME}-terraform-state-${RANDOM}"
    aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}" || {
        log_error "Failed to create S3 bucket for Terraform state"
        exit 1
    }
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Create DynamoDB table for state locking
    aws dynamodb create-table \
        --table-name "${PROJECT_NAME}-terraform-locks" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region "${AWS_REGION}" || {
        log_warning "DynamoDB table might already exist"
    }
    
    # Update backend configuration
    sed -i.bak "s/your-terraform-state-bucket/${BUCKET_NAME}/g" infrastructure/terraform/environments/dev/main.tf
    
    log_success "Terraform backend configured with bucket: ${BUCKET_NAME}"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd infrastructure/terraform/environments/dev
    
    # Initialize Terraform
    terraform init
    
    # Plan the deployment
    terraform plan -out=tfplan
    
    # Apply the plan
    terraform apply tfplan
    
    cd ../../../../
    
    log_success "Infrastructure deployed successfully"
}

configure_kubectl() {
    log_info "Configuring kubectl..."
    
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
    
    # Verify connection
    kubectl cluster-info
    
    log_success "kubectl configured successfully"
}

install_cluster_addons() {
    log_info "Installing cluster addons..."
    
    # Install AWS Load Balancer Controller
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
    
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="${CLUSTER_NAME}" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller
    
    # Install Cluster Autoscaler
    helm repo add autoscaler https://kubernetes.github.io/autoscaler
    helm install cluster-autoscaler autoscaler/cluster-autoscaler \
        -n kube-system \
        --set autoDiscovery.clusterName="${CLUSTER_NAME}" \
        --set awsRegion="${AWS_REGION}"
    
    # Install NGINX Ingress Controller
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        -n ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer
    
    log_success "Cluster addons installed successfully"
}

install_argocd() {
    log_info "Installing ArgoCD..."
    
    # Create ArgoCD namespace
    kubectl create namespace argocd || log_warning "ArgoCD namespace already exists"
    
    # Install ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
    
    # Patch ArgoCD server to use LoadBalancer
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
    
    # Get ArgoCD admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    log_success "ArgoCD installed successfully"
    log_info "ArgoCD admin password: ${ARGOCD_PASSWORD}"
}

deploy_gitops_applications() {
    log_info "Deploying GitOps applications..."
    
    # Apply ArgoCD project and applications
    kubectl apply -f k8s-manifests/argocd/
    
    # Wait for applications to sync
    sleep 30
    
    log_success "GitOps applications deployed successfully"
}

setup_monitoring() {
    log_info "Setting up monitoring stack..."
    
    # Apply monitoring manifests
    kubectl apply -f k8s-manifests/monitoring/
    
    # Wait for Prometheus to be ready
    kubectl wait --for=condition=available --timeout=600s deployment/prometheus-stack-kube-prom-operator -n monitoring
    
    log_success "Monitoring stack deployed successfully"
}

setup_security() {
    log_info "Setting up security stack..."
    
    # Apply security manifests
    kubectl apply -f k8s-manifests/security/
    
    # Wait for Gatekeeper to be ready
    kubectl wait --for=condition=available --timeout=600s deployment/gatekeeper-controller-manager -n gatekeeper-system
    
    log_success "Security stack deployed successfully"
}

run_initial_tests() {
    log_info "Running initial tests..."
    
    # Test cluster connectivity
    kubectl get nodes
    
    # Test ArgoCD
    ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -n "$ARGOCD_SERVER" ]; then
        log_success "ArgoCD accessible at: https://${ARGOCD_SERVER}"
    fi
    
    # Test Grafana
    GRAFANA_SERVER=$(kubectl get svc prometheus-stack-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -n "$GRAFANA_SERVER" ]; then
        log_success "Grafana accessible at: https://${GRAFANA_SERVER}"
    fi
    
    log_success "Initial tests completed"
}

print_summary() {
    log_info "============================================"
    log_info "         GitOps Platform Deployment"
    log_info "============================================"
    log_success "✅ Infrastructure: Deployed"
    log_success "✅ Kubernetes Cluster: Ready"
    log_success "✅ ArgoCD: Installed"
    log_success "✅ Monitoring: Configured"
    log_success "✅ Security: Enabled"
    log_info "============================================"
    log_info "Next steps:"
    log_info "1. Access ArgoCD UI and sync applications"
    log_info "2. Configure your application repositories"
    log_info "3. Set up CI/CD pipelines"
    log_info "4. Configure alerts and notifications"
    log_info "============================================"
}

# Main execution
main() {
    log_info "Starting GitOps Platform setup..."
    
    check_dependencies
    setup_terraform_backend
    deploy_infrastructure
    configure_kubectl
    install_cluster_addons
    install_argocd
    deploy_gitops_applications
    setup_monitoring
    setup_security
    run_initial_tests
    print_summary
    
    log_success "GitOps Platform setup completed successfully!"
}

# Script options
case "${1:-setup}" in
    "setup")
        main
        ;;
    "destroy")
        log_warning "Destroying GitOps Platform..."
        cd infrastructure/terraform/environments/dev
        terraform destroy -auto-approve
        cd ../../../../
        log_success "GitOps Platform destroyed"
        ;;
    "update")
        log_info "Updating GitOps Platform..."
        deploy_infrastructure
        kubectl apply -f k8s-manifests/argocd/
        kubectl apply -f k8s-manifests/monitoring/
        kubectl apply -f k8s-manifests/security/
        log_success "GitOps Platform updated"
        ;;
    "status")
        log_info "GitOps Platform Status:"
        kubectl get nodes
        kubectl get pods --all-namespaces
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Usage: $0 [setup|destroy|update|status]"
        exit 1
        ;;
esac