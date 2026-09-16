#!/bin/bash
set -e

echo "🚀 Starting Kratix + Backstage + Crossplane + KubeVirt Setup..."

# ===== 1. متطلبات النظام الأساسية =====
apt-get update && apt-get install -y \
    curl wget git unzip jq \
    build-essential python3-pip \
    qemu-kvm libvirt-daemon-system virt-manager \
    docker.io

# ===== 2. تفعيل Docker =====
systemctl start docker || true
usermod -aG docker $USER || true

# ===== 3. K3s التثبيت (أخف من Kubernetes الكامل) =====
echo "📦 Installing K3s..."
curl -sfL https://get.k3s.io | \
    K3S_KUBECONFIG_MODE="644" \
    K3S_KUBECONFIG_OUTPUT=/root/.kube/config \
    sh -

# استخدام k3s kubectl
alias kubectl="k3s kubectl"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# الانتظار لتشغيل الخادم
sleep 10
kubectl cluster-info

# ===== 4. تثبيت Helm =====
echo "📊 Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ===== 5. تثبيت Crossplane =====
echo "🎯 Installing Crossplane..."
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane --namespace crossplane-system \
    --create-namespace \
    crossplane-stable/crossplane \
    --wait --timeout=5m

# ===== 6. تثبيت KubeVirt (النسخة المخففة) =====
echo "🖥️  Installing KubeVirt..."
KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | \
    grep tag_name | head -1 | awk -F'"' '{print $4}')

kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"

# الانتظار لـ KubeVirt
kubectl wait --for=condition=Ready virt --all --timeout=5m -n kubevirt || true

# ===== 7. تثبيت Kratix =====
echo "🎪 Installing Kratix..."
kubectl apply -f https://raw.githubusercontent.com/syntasso/kratix/main/distribution/kratix.yaml

sleep 10
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kratix -n kratix-system --timeout=5m

# ===== 8. تثبيت Backstage =====
echo "🎭 Installing Backstage..."

# إنشاء Backstage App من القالب السريع
npm install -g @backstage/create-app@latest

# أو تثبيت Helm Chart الموجود مسبقاً
helm repo add backstage https://backstage.io
helm repo update
helm install backstage --namespace backstage --create-namespace \
    backstage/backstage \
    --set backend.image.tag="latest" \
    --wait --timeout=5m

# ===== 9. تثبيت Flux (لـ GitOps) =====
echo "📡 Installing Flux..."
curl -s https://fluxcd.io/install.sh | bash

flux install --namespace=flux-system --components-extra=image-reflector-controller,image-automation-controller

# ===== 10. تثبيت ArgoCD (لـ Continuous Deployment) =====
echo "🚀 Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}' || true

# ===== 11. اختبار التثبيت =====
echo "✅ Verifying Installation..."
kubectl get nodes
kubectl get namespaces
kubectl get crds | grep -E "crossplane|kubevirt|kratix"

# ===== 12. عرض معلومات الوصول =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ SETUP COMPLETE! ACCESS INFORMATION:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  Backstage:"
echo "   kubectl port-forward -n backstage svc/backstage 7007:7007"
echo "   → http://localhost:7007"
echo ""
echo "2️⃣  ArgoCD:"
echo "   kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "   → https://localhost:8080 (Username: admin)"
echo "   → Get password: kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "3️⃣  Kubernetes Dashboard:"
echo "   kubectl proxy"
echo "   → http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy"
echo ""
echo "4️⃣  Crossplane Status:"
echo "   kubectl get crds | grep crossplane"
echo "   kubectl describe provider.pkg.crossplane.io"
echo ""
echo "5️⃣  KubeVirt Status:"
echo "   kubectl get vms -A"
echo "   kubectl top nodes"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "✅ Installation successful! Your IDP is ready."
