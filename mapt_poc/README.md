# MAPT POC - OpenShift Cluster Creation and Sail Operator E2E Testing

This Proof of Concept (POC) demonstrates an automated end-to-end workflow that can:

1. **Create** an AWS OpenShift Single Node Cluster (SNC) using MAPT
2. **Test** the Istio Sail Operator functionality via E2E tests
3. **Delete** the cluster and clean up AWS resources
4. **Measure** execution time and provide detailed reporting

The script supports flexible operation modes through command-line flags, allowing you to run only specific parts of the workflow as needed.

## 🎯 **Purpose**

The POC validates different aspects of the workflow:
- Provisioning OpenShift infrastructure on AWS using spot instances
- Running comprehensive E2E tests for the Istio Sail Operator
- Measuring performance metrics for individual operations to compare with existing CI
- Enabling iterative development and testing workflows

## 🚀 **Usage**

### Command Line Options

The script supports the following operation modes:

```bash
./mapt_poc.sh [OPTIONS]

Options:
  -c    Create the cluster only (don't run tests or delete)
  -t    Run tests only (don't create or delete cluster)
  -d    Delete the cluster only (don't create or test)
  -a    Create cluster, run tests, and delete cluster (default)
  -h    Show help message
```

### Usage Examples

```bash
# Make the script executable
chmod +x mapt_poc.sh

# Default behavior: create, test, and delete (equivalent to -a)
./mapt_poc.sh

# Create cluster only (for development/debugging)
./mapt_poc.sh -c

# Run tests on existing cluster (cluster must already exist)
./mapt_poc.sh -t

# Delete an existing cluster
./mapt_poc.sh -d

# Explicit full workflow
./mapt_poc.sh -a
```

### Common Workflows

#### **Development Workflow**
```bash
# 1. Create cluster for development
./mapt_poc.sh -c

# 2. Run tests multiple times during development
./mapt_poc.sh -t  # Run tests on existing cluster (fast iterations)

# 3. Clean up when done
./mapt_poc.sh -d
```

#### **Full Workflow**
```bash
# Full automated pipeline (default)
./mapt_poc.sh
# or explicitly
./mapt_poc.sh -a
```

#### **Debugging Failed Tests**
```bash
# Create cluster first
./mapt_poc.sh -c

# Run tests on the cluster (if they fail, cluster is preserved)
./mapt_poc.sh -t

# ... investigate cluster state ...

# Clean up when done
./mapt_poc.sh -d
```

## 📋 **Prerequisites**

### Required Tools
- **Podman** - For running MAPT containers
- **OpenShift CLI (oc)** - For cluster interaction
- **Git** - For cloning repositories

### Required Files
- **Pull Secret**: Place your OpenShift pull secret at `mapt_poc/pullsecret/crc_secret`
  - Get your pull secret from: https://console.redhat.com/openshift/install/pull-secret

### AWS Credentials
Set the following environment variables:
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="your-preferred-region"  # e.g., us-east-1
```

### Generated Files
- **`mapt_poc_YYYYMMDD_HHMMSS.log`**: Complete execution log with timestamps (all modes)
- **`create-snc.log`**: Cluster creation container logs (modes: `-c`, `-a`)
- **`destroy-snc.log`**: Cluster destruction container logs (modes: `-d`, `-a`, error cleanup)
- **`kubeconfig`**: OpenShift cluster access credentials (modes: `-c`, `-a`)

## 🔧 **Configuration**

### Cluster Settings
The script creates a cluster with these specifications:
- **Version**: OpenShift 4.19.0
- **Type**: Single Node Cluster (SNC)
- **Instance**: AWS Spot Instance
- **Project Name**: `poc-mapt`
- **Tags**: `project=crc,environment=local,user=frherrer`

### Timeouts
- **Cluster Creation**: 40 minutes (2400 seconds)
- **Cluster Destruction**: 20 minutes (1200 seconds)


## 🔗 **Related Resources**

- [MAPT Documentation](https://github.com/redhat-developer/mapt)
- [Sail Operator Repository](https://github.com/istio-ecosystem/sail-operator)
- [OpenShift SNC Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_sno/install-sno-installing-sno.html)
- [OpenShift Pull Secret](https://console.redhat.com/openshift/install/pull-secret)

## 📝 **Notes**

- **Cost Awareness**: This POC creates real AWS resources that incur costs
- **Region Selection**: Choose AWS regions with good spot instance availability
- **Security**: Pull secrets and kubeconfig files contain sensitive data
- **Cleanup Verification**: Always verify AWS resources are properly cleaned up after execution 