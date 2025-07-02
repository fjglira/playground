#!/bin/bash

set -euo pipefail

# This script is going to be used to run the MAPT POC
# POC modes:
# -c: Create the cluster only
# -t: Run tests (don't create and delete cluster)
# -d: Delete the cluster only
# -a: Create the cluster, run the tests, and delete the cluster (default)

# Default mode (all operations)
CREATE_CLUSTER=true
RUN_TESTS=true
DELETE_CLUSTER=true

# Setup comprehensive logging
SCRIPT_START_TIME=$(date '+%Y%m%d_%H%M%S')
MAIN_LOG_FILE="mapt_poc_${SCRIPT_START_TIME}.log"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MAIN_LOG_FILE"
}

# Function to log without timestamp (for continuing messages)
log_continue() {
    echo "$*" | tee -a "$MAIN_LOG_FILE"
}

# Redirect all output to both console and log file
exec > >(tee -a "$MAIN_LOG_FILE")
exec 2> >(tee -a "$MAIN_LOG_FILE" >&2)

# Function to show usage
usage() {
    log_with_timestamp "Usage: $0 [OPTIONS]"
    log_continue ""
    log_continue "MAPT POC - OpenShift Cluster Creation and Sail Operator E2E Testing"
    log_continue ""
    log_continue "Options:"
    log_continue "  -c    Create the cluster only (don't run tests or delete)"
    log_continue "  -t    Run tests (don't create and delete cluster)"
    log_continue "  -d    Delete the cluster only (don't create or test)"
    log_continue "  -a    Create cluster, run tests, and delete cluster (default)"
    log_continue "  -h    Show this help message"
    log_continue ""
    log_continue "Examples:"
    log_continue "  $0        # Default: create, test, and delete"
    log_continue "  $0 -c     # Only create cluster"
    log_continue "  $0 -t     # Only run tests on existing cluster"
    log_continue "  $0 -d     # Only delete existing cluster"
    log_continue ""
    log_continue "Required environment variables:"
    log_continue "  AWS_ACCESS_KEY_ID"
    log_continue "  AWS_SECRET_ACCESS_KEY"
    log_continue "  AWS_DEFAULT_REGION"
    log_continue ""
    log_continue "Logs will be saved to: $MAIN_LOG_FILE"
    log_continue ""
}

# Parse command line arguments
while getopts "ctdah" opt; do
    case $opt in
        c)
            CREATE_CLUSTER=true
            RUN_TESTS=false
            DELETE_CLUSTER=false
            log_with_timestamp "Mode: Create cluster only"
            ;;
        t)
            CREATE_CLUSTER=false
            RUN_TESTS=true
            DELETE_CLUSTER=false
            log_with_timestamp "Mode: Only run the tests"
            ;;
        d)
            CREATE_CLUSTER=false
            RUN_TESTS=false
            DELETE_CLUSTER=true
            log_with_timestamp "Mode: Delete cluster only"
            ;;
        a)
            CREATE_CLUSTER=true
            RUN_TESTS=true
            DELETE_CLUSTER=true
            log_with_timestamp "Mode: Create, test, and delete cluster"
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            log_with_timestamp "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
    esac
done

log_with_timestamp "=== MAPT POC EXECUTION STARTED ==="
log_with_timestamp "Main log file: $MAIN_LOG_FILE"
log_with_timestamp "Script start time: $(date)"
log_with_timestamp "Selected modes - Create: $CREATE_CLUSTER, Test: $RUN_TESTS, Delete: $DELETE_CLUSTER"

# Record the start time
start_time=$(date +%s)

# Flag to track if cluster creation was successful
cluster_created=false

# Flag to track if cleanup has already been run
cleanup_done=false

# Initialize SAIL_DIR for global trap
SAIL_DIR=""

# Cleanup function to ensure destroy is always called when appropriate
cleanup() {
    # Disable ERR trap to prevent infinite loops during cleanup
    # We still want EXIT, INT, TERM traps to work.
    trap - ERR
    
    # Prevent cleanup from running multiple times
    if [ "$cleanup_done" = true ]; then
        log_with_timestamp "Cleanup already completed, skipping..."
        return 0
    fi
    
    log_with_timestamp "Cleanup function called..."
    cleanup_done=true
    
    # Only destroy cluster if:
    # 1. DELETE_CLUSTER is true (explicit delete mode or all mode)
    # 2. OR if there was an error and cluster was created (cleanup on failure)
    should_destroy=false
    
    if [ "$DELETE_CLUSTER" = true ]; then
        log_with_timestamp "Delete mode enabled, will destroy cluster if it exists."
        should_destroy=true
    elif [ "$cluster_created" = true ] && [ "$?" -ne 0 ]; then
        log_with_timestamp "Error detected and cluster was created, will destroy for cleanup."
        should_destroy=true
    fi
    
    # Check if a cluster exists (either explicitly created OR if a create-snc container still exists)
    cluster_exists=false
    if [ "$cluster_created" = true ] || podman ps -a --format "{{.Names}}" | grep -q "create-snc"; then
        cluster_exists=true
    fi
    
    if [ "$should_destroy" = true ] && [ "$cluster_exists" = true ]; then
        log_with_timestamp "Running cluster destruction as cleanup..."
        
        # Step: Delete the cluster
        log_with_timestamp "Destroying the cluster..."
        # Running in detached mode so that cleanup function can proceed and wait for it
        # Make sure to include all necessary env vars and volume mounts
        podman run -d --name destroy-snc-cleanup \
                    -v "${PWD}:/workspace:z" \
                    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
                    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
                    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
                    quay.io/redhat-developer/mapt:v0.9.3 aws openshift-snc destroy \
                        --project-name poc-mapt \
                        --backed-url "file:///workspace"    

        # Wait for destroy container to complete and save logs
        log_with_timestamp "Waiting for cluster destruction to complete (timeout: 20 minutes)..."
        # Temporarily disable -e for podman commands in cleanup to avoid infinite loops if podman fails
        set +e
        destroy_container_id=$(podman ps -q --filter "name=destroy-snc-cleanup")
        set -e # Re-enable -e

        if [ -n "$destroy_container_id" ]; then
            if timeout 1200 podman wait "$destroy_container_id"; then
                set +e # Temporarily disable -e for log/inspect to prevent cleanup from aborting itself
                destroy_exit_code=$(podman inspect "$destroy_container_id" --format '{{.State.ExitCode}}')
                log_with_timestamp "Destroy container exited with code $destroy_exit_code"
                
                # Save logs from destroy-snc container
                log_with_timestamp "Saving destroy-snc container logs to destroy-snc.log..."
                podman logs "$destroy_container_id" > destroy-snc.log 2>&1 || log_with_timestamp "Failed to capture destroy logs"
                set -e # Re-enable -e
                
                if [ "$destroy_exit_code" -ne 0 ]; then
                    log_with_timestamp "Warning: Cluster destruction may have failed, exit code: $destroy_exit_code"
                    log_with_timestamp "Check destroy-snc.log for detailed information"
                else
                    log_with_timestamp "Cluster destroyed successfully."
                fi
            else
                log_with_timestamp "Timeout waiting for cluster destruction to complete"
                # Save logs even on timeout
                set +e
                log_with_timestamp "Saving destroy-snc container logs to destroy-snc.log..."
                podman logs "$destroy_container_id" > destroy-snc.log 2>&1 || log_with_timestamp "Failed to capture destroy logs on timeout"
                set -e
                log_with_timestamp "Warning: Cluster destruction may not have completed"
            fi
        else
            log_with_timestamp "Warning: Could not find destroy container (it may have failed to start or already exited). Manual cleanup may be required for project: poc-mapt"
        fi
        
        # Clean up containers
        # Use set +e around rm to ensure cleanup doesn't fail if containers don't exist
        set +e
        podman rm -f create-snc destroy-snc-cleanup 2>/dev/null
        set -e
        
        log_with_timestamp "Cleanup completed. Logs saved:"
        log_with_timestamp "  - create-snc.log: Contains logs from cluster creation"
        log_with_timestamp "  - destroy-snc.log: Contains logs from cluster destruction"
    elif [ "$should_destroy" = true ] && [ "$cluster_exists" = false ]; then
        log_with_timestamp "Delete mode enabled but no cluster found to destroy."
    else
        log_with_timestamp "Cluster preservation mode - not destroying cluster."
        if [ "$cluster_created" = true ]; then
            log_with_timestamp "Cluster remains available for future use."
            log_with_timestamp "To delete it later, run: $0 -d"
        fi
    fi

    # Clean up the sail-operator directory if it was created
    if [ -n "$SAIL_DIR" ] && [ -d "$SAIL_DIR" ]; then
        log_with_timestamp "Removing temporary sail-operator directory: $SAIL_DIR"
        rm -rf "$SAIL_DIR"
    fi
    
    log_with_timestamp "=== CLEANUP COMPLETED ==="
}

# Set traps to ensure cleanup on script exit, error, or termination
# ERR trap should print a message indicating an error occurred.
trap 'log_with_timestamp "ERROR: Script aborted due to an error. Cleaning up..."; cleanup' ERR
# INT and TERM traps for user interruption or external termination.
trap 'log_with_timestamp "WARNING: Script interrupted by user (Ctrl+C). Cleaning up..."; cleanup' INT
trap 'log_with_timestamp "WARNING: Script terminated externally. Cleaning up..."; cleanup' TERM
# EXIT trap will always run, whether the script succeeds or fails (after other traps).
trap 'cleanup' EXIT

# Check that env var AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_DEFAULT_REGION are set
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${AWS_DEFAULT_REGION:-}" ]]; then
    log_with_timestamp "Please set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_DEFAULT_REGION environment variables."
    usage
    exit 1
fi

# Main execution logic based on selected mode
log_with_timestamp "Starting MAPT POC with selected operations..."
log_with_timestamp "Create cluster: $CREATE_CLUSTER"
log_with_timestamp "Run tests: $RUN_TESTS"
log_with_timestamp "Delete cluster: $DELETE_CLUSTER"
log_with_timestamp ""

# Step 1: Create cluster (if enabled)
if [ "$CREATE_CLUSTER" = true ]; then
    log_with_timestamp "Creating a new AWS SNC cluster with 4.19 OCP version..."
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
    log_with_timestamp "Waiting for the cluster to be created..."
    container_id=$(podman ps -q --filter "name=create-snc")

    if [ -z "$container_id" ]; then
        log_with_timestamp "Error: create-snc container did not start. Manual debug might be needed."
        exit 1 # Trigger cleanup via ERR trap
    fi

    if timeout 2400 podman wait "$container_id"; then
        exit_code=$(podman inspect "$container_id" --format '{{.State.ExitCode}}')
        log_with_timestamp "Container exited with code $exit_code"
        
        # Save logs from create-snc container
        log_with_timestamp "Saving create-snc container logs to create-snc.log..."
        podman logs "$container_id" > create-snc.log 2>&1
        
        if [ "$exit_code" -ne 0 ]; then
            log_with_timestamp "Error creating the cluster, exit code: $exit_code"
            log_with_timestamp "Check create-snc.log for detailed error information"
            # Since set -e is active, this exit 1 will trigger the ERR trap and then EXIT trap
            exit 1
        else
            cluster_created=true
            log_with_timestamp "Cluster created successfully."
            log_with_timestamp "Duration: $(($(date +%s) - start_time)) seconds"
        fi
    else
        log_with_timestamp "Timeout waiting for container to stop"
        # Save logs even on timeout
        log_with_timestamp "Saving create-snc container logs to create-snc.log..."
        podman logs "$container_id" > create-snc.log 2>&1
        # Since set -e is active, this exit 1 will trigger the ERR trap and then EXIT trap
        exit 1
    fi
else
    log_with_timestamp "Skipping cluster creation (not requested)."
    # For delete-only mode, we assume a cluster exists
    if [ "$DELETE_CLUSTER" = true ]; then
        cluster_created=true  # Assume cluster exists for delete mode
    fi
fi

# Step 2: Run tests (if enabled and cluster is available)
if [ "$RUN_TESTS" = true ]; then
    # Check if we have a kubeconfig (either from creation or existing)
    export KUBECONFIG="$(pwd)/kubeconfig"

    if [ ! -f "$KUBECONFIG" ]; then
        log_with_timestamp "Kubeconfig file not found at $KUBECONFIG"
        if [ "$CREATE_CLUSTER" = false ]; then
            log_with_timestamp "Error: Cannot run tests without kubeconfig. Did you create a cluster first?"
            exit 1
        else
            log_with_timestamp "Skipping tests due to missing kubeconfig."
            exit 1 
        fi
    else
        log_with_timestamp "Verifying cluster connectivity via kubeconfig..."
        # Temporarily disable -e for this check as 'oc' might fail initially,
        # but we handle it with the if/else
        set +e
        if ! oc get nodes &> /dev/null; then
            log_with_timestamp "Failed to connect to the cluster via 'oc'. Please check your kubeconfig and cluster status."
            log_with_timestamp "Skipping tests due to cluster connectivity issues."
            set -e # Re-enable -e before exiting
            exit 1 
        fi
        set -e # Re-enable -e
        log_with_timestamp "Cluster connectivity established."

        # Step 3: Clone the sail-operator repository to a temp folder
        log_with_timestamp "Cloning the sail-operator repository..."
        SAIL_DIR=$(mktemp -d /tmp/sail-operator-XXXX) # SAIL_DIR is now globally initialized and set here

        if git clone https://github.com/istio-ecosystem/sail-operator "$SAIL_DIR"; then
            # Step 4: Run the e2e test from sail repository
            test_start_time=$(date +%s)
            log_with_timestamp "Running the e2e test from sail repository..."
            
            # Store original directory to ensure we can return
            ORIGINAL_DIR="$(pwd)"
            
            if ! cd "$SAIL_DIR"; then # Use ! cd to handle failure with set -e
                log_with_timestamp "Failed to change directory to $SAIL_DIR. Skipping tests."
                exit 1 # Trigger cleanup
            fi
            log_with_timestamp "Changed to directory: $SAIL_DIR"
           
            log_with_timestamp "Running E2E tests..."
            set +e  # Temporarily disable exit on error to catch make failures
            # Run the e2e test with specific flags
            # SKIP_BUILD is set to true to avoid rebuilding the operator, using nigtlhy image for this POC

            SKIP_BUILD=true KEEP_ON_FAILURE=true make test.e2e.ocp
            test_exit_code=$?
            set -e  # Re-enable exit on error
            
            if [ $test_exit_code -eq 0 ]; then
                test_end_time=$(date +%s)
                test_elapsed=$(( test_end_time - test_start_time ))
                log_with_timestamp "E2E test completed successfully."
                log_with_timestamp "E2E test duration: $(printf "%02d:%02d:%02d\n" $((test_elapsed / 3600)) $(((test_elapsed % 3600) / 60)) $((test_elapsed % 60)))"
            else
                log_with_timestamp "E2E test failed with exit code: $test_exit_code"
                # Exit here to trigger cleanup for failed test scenario
                exit 1
            fi
            
            # Return to original directory
            log_with_timestamp "Returning to original directory: $ORIGINAL_DIR"
            cd "$ORIGINAL_DIR"
        else
            log_with_timestamp "Failed to clone the sail-operator repository."
            exit 1 # Trigger cleanup
        fi
    fi
else
    log_with_timestamp "Skipping tests (not requested)."
fi

# Step 3: Show elapsed time summary (if any operations were performed)
if [ "$CREATE_CLUSTER" = true ] || [ "$RUN_TESTS" = true ] || [ "$DELETE_CLUSTER" = true ]; then
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    
    hours=$((elapsed / 3600))
    minutes=$(((elapsed % 3600) / 60))
    seconds=$((elapsed % 60))
    
    log_with_timestamp ""
    log_with_timestamp "=== EXECUTION SUMMARY ==="
    if [ "$CREATE_CLUSTER" = true ] && [ "$cluster_created" = true ]; then
        log_with_timestamp "✓ Cluster created successfully"
    elif [ "$CREATE_CLUSTER" = true ]; then
        log_with_timestamp "✗ Cluster creation failed or incomplete"
    fi
    
    if [ "$RUN_TESTS" = true ]; then
        log_with_timestamp "✓ E2E tests executed"
    fi
    
    if [ "$DELETE_CLUSTER" = true ]; then
        log_with_timestamp "✓ Cluster deletion scheduled for cleanup"
    elif [ "$cluster_created" = true ]; then
        log_with_timestamp "ℹ Cluster preserved (use '$0 -d' to delete later)"
    fi
    
    log_with_timestamp "Total execution time: $(printf "%02d:%02d:%02d\n" $hours $minutes $seconds)"
    log_with_timestamp "========================="
else
    log_with_timestamp "No operations were performed."
fi

log_with_timestamp "Script execution completed. Cleanup will run on exit."