#!/bin/bash

set -euo pipefail

# This script is going to be used to run the MAPT POC
# POC steps:
# 1. Create a new AWS SNC cluster with 4.19 OCP version
# 2. Get the kube files to be able to connect to the cluster
# 3. Clone the sail-operator repository
# 4. Run the e2e test from sail repository
# 5. Show the time result since the creation of the cluster until the complete execution of the test
# 6. Delete the cluster running the mapt destroy command

# Record the start time
start_time=$(date +%s)

# Check that env var AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_DEFAULT_REGION are set
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${AWS_DEFAULT_REGION:-}" ]]; then
    echo "Please set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_DEFAULT_REGION environment variables."
    exit 1
fi

# Step 1: Create a new AWS SNC cluster with 4.19 OCP version
echo "Creating a new AWS SNC cluster with 4.19 OCP version..."
podman run -d --name create-snc \
    -v "${PWD}:/workspace:z" \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
    quay.io/redhat-developer/mapt:v0.9.3 aws openshift-snc create \
        --backed-url "file:///workspace" \
        --conn-details-output "/workspace" \
        --pull-secret-file /workspace/mapt_poc/pullsecret/crc_secret \
        --tags project=crc,environment=local,user=frherrer \
        --version 4.19.0 \
        --spot \
        --project-name poc-mapt

# Step 1.5: Wait until the cluster is created
echo "Waiting for the cluster to be created..."
container_id=$(podman ps -q --filter "name=create-snc")

if timeout 2400 podman wait "$container_id"; then
    exit_code=$(podman inspect "$container_id" --format '{{.State.ExitCode}}')
    echo "Container exited with code $exit_code"
    if [ "$exit_code" -ne 0 ]; then
        echo "Error creating the cluster, exit code: $exit_code"
        podman logs "$container_id"
        exit 1
    fi
else
    echo "Timeout waiting for container to stop"
    exit 1
fi

echo "Cluster created successfully."
echo "Duration: $(($(date +%s) - start_time)) seconds"

# Step 2: Get the kube files to be able to connect to the cluster
export KUBECONFIG="$(pwd)/kubeconfig"

# Check if the kubeconfig file exists
if [ ! -f "$KUBECONFIG" ]; then
    echo "Kubeconfig file not found at $KUBECONFIG"
    exit 1
fi

# Check that cluster can be reached
if ! oc get nodes &> /dev/null; then
    echo "Failed to connect to the cluster. Please check your kubeconfig."
    exit 1
fi

# Step 3: Clone the sail-operator repository to a temp folder
echo "Cloning the sail-operator repository..."
SAIL_DIR=$(mktemp -d /tmp/sail-operator-XXXX)
trap 'rm -rf "$SAIL_DIR"' EXIT

git clone https://github.com/istio-ecosystem/sail-operator "$SAIL_DIR" || {
    echo "Failed to clone the sail-operator repository"
    exit 1
}

# Step 4: Run the e2e test from sail repository
test_start_time=$(date +%s)
echo "Running the e2e test from sail repository..."
cd "$SAIL_DIR" || {
    echo "Failed to change directory to $SAIL_DIR"
    exit 1
}

# Workaround, set insecure registry and write it in the docker daemon.json file
export DOCKER_INSECURE_REGISTRIES="default-route-openshift-image-registry.$(oc get routes -A -o jsonpath='{.items[0].spec.host}' | awk -F. '{print substr($0, index($0,$2))}')"
echo "Insecure registry set to $DOCKER_INSECURE_REGISTRIES"
echo "Writing insecure registry to /etc/docker/daemon.json"
echo "{\"insecure-registries\": [\"$DOCKER_INSECURE_REGISTRIES\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
sudo systemctl restart docker || {
    echo "Failed to restart Docker service"
    exit 1
}

TARGET_ARCH=amd64 GINGO_FLAGS="-v" make test.e2e.ocp || {
    echo "E2E test failed"
    exit 1
}

test_end_time=$(date +%s)
test_elapsed=$(( test_end_time - test_start_time ))
echo "E2E test completed successfully."
echo "E2E test duration: $(printf "%02d:%02d:%02d\n" $((test_elapsed / 3600)) $(((test_elapsed % 3600) / 60)) $((test_elapsed % 60)))"

# Step 5: Show elapsed time
end_time=$(date +%s)
elapsed=$(( end_time - start_time ))

hours=$((elapsed / 3600))
minutes=$(((elapsed % 3600) / 60))
seconds=$((elapsed % 60))

echo "Total elapsed time: $(printf "%02d:%02d:%02d\n" $hours $minutes $seconds)"

# Step 6: Delete the cluster
echo "Destroying the cluster..."
podman run -d --name destroy-snc \
            -v ${PWD}:/workspace:z \
            -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
            -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
            -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
            quay.io/redhat-developer/mapt:v0.9.3 aws openshift-snc destroy \
                --project-name poc-mapt \
                --backed-url "file:///workspace" 
