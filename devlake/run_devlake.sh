#!/bin/bash

set -euo pipefail

# This script is going to run devlake in a kind cluster.

# 1. Create kind cluster
kind create cluster --name devlake

# 2. Creating secret
export ENCRYPTION_SECRET=$(openssl rand -base64 2000 | tr -dc 'A-Z' | fold -w 128 | head -n 1)

# 3. Install devlake
helm repo add devlake https://apache.github.io/incubator-devlake-helm-chart
helm repo update
helm install devlake devlake/devlake --version=1.0-beta1 --set lake.encryptionSecret.secret=$ENCRYPTION_SECRET

# 4. Wait for devlake to be ready
kubectl wait --for=condition=available --timeout=600s deployment/devlake-lake -n default

# 5. Port forward to access devlake
echo "DevLake is now running. You can access it at http://localhost:4000"
kubectl port-forward --namespace default service/devlake-ui 4000:4000

