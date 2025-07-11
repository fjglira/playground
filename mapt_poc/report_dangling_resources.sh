#!/bin/bash

# The main goal of this script is to:
# 1. Identify dangling resources in all the AWS zones.
# 2. Report them in a structured format.
# 3. Provide a summary of the dangling resources.
# 4. Optionally, delete the dangling resources.

# Usage: 
# ./report_dangling_resources.sh [--flag]
# Options:
# --delete: If provided, the script will delete the dangling resources.
# --check: If provided, the script will only check for dangling resources without deleting them.
# --help: Display this help message.

function usage() {
    echo "Usage: $0 [--delete] [--check] [--help]"
    echo "Options:"
    echo "  --delete: Delete dangling resources."
    echo "  --check: Check for dangling resources without deleting them."
    echo "  --help: Display this help message."
}

function delete_dangling_resources() {
    echo "Deleting dangling resources..."
    # Add your deletion logic here
}

function check_dangling_resources() {
    echo "Checking for dangling resources..."
    
    # getting the list of all AWS zones
    zones=$(aws ec2 describe-availability-zones --query "AvailabilityZones[*].ZoneName" --output text)
    if [[ -z "$zones" ]]; then
        echo "No availability zones found."
        return
    fi

    # Loop through each zone and check for dangling resources
    for zone in $zones; do
        echo "Checking zone: $zone"
        
       # Check for dangling EBS volumes
        dangling_volumes=$(aws ec2 describe-volumes --filters "Name=status,Values=available" --query "Volumes[*].{ID:VolumeId,Size:Size}" --output table)
        
        if [[ -n "$dangling_volumes" ]]; then
            echo "Dangling EBS Volumes in $zone:"
            echo "$dangling_volumes"
        else
            echo "No dangling EBS volumes found in $zone."
        fi
        
        # Check dangling VPC
        dangling_vpcs=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=false" --query "Vpcs[*].{ID:VpcId,State:State}" --output table)
        if [[ -n "$dangling_vpcs" ]]; then
            echo "Dangling VPCs in $zone:"
            echo "$dangling_vpcs"
        else
            echo "No dangling VPCs found in $zone."
        fi

        # Check dangling security groups
        dangling_sgs=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=default" --query "SecurityGroups[*].{ID:GroupId,Name:GroupName}" --output table)
        if [[ -n "$dangling_sgs" ]]; then
            echo "Dangling Security Groups in $zone:"
            echo "$dangling_sgs"
        else
            echo "No dangling security groups found in $zone."
        fi

        # Check dangling Elastic IPs
        dangling_eips=$(aws ec2 describe-addresses --filters "Name=domain,Values=vpc" --query "Addresses[*].{PublicIP:PublicIp,AllocationId:AllocationId}" --output table)
        if [[ -n "$dangling_eips" ]]; then
            echo "Dangling Elastic IPs in $zone:"
            echo "$dangling_eips"
        else
            echo "No dangling Elastic IPs found in $zone."
        fi

        # Check dangling load balancers
        dangling_elbs=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?State.Code=='active'].{Name:LoadBalancerName,ARN:LoadBalancerArn}" --output table)
        if [[ -n "$dangling_elbs" ]]; then
            echo "Dangling Load Balancers in $zone:"
            echo "$dangling_elbs"
        else
            echo "No dangling load balancers found in $zone."
        fi

        # Check dangling IAM roles
        dangling_roles=$(aws iam list-roles --query "Roles[?RoleName!='AWSServiceRoleForOrganizations'].{Name:RoleName,ARN:Arn}" --output table)
        if [[ -n "$dangling_roles" ]]; then
            echo "Dangling IAM Roles in $zone:"
            echo "$dangling_roles"
        else
            echo "No dangling IAM roles found in $zone."
        fi

        # Check dangling S3 buckets
        dangling_buckets=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'dangling-')].{Name:Name,CreationDate:CreationDate}" --output table)
        if [[ -n "$dangling_buckets" ]]; then
            echo "Dangling S3 Buckets in $zone:"
            echo "$dangling_buckets"
        else
            echo "No dangling S3 buckets found in $zone."
        fi
    done
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --delete) delete=true ;;
        --check) check=true ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# Main script logic
if [[ "$delete" == true ]]; then
    delete_dangling_resources
elif [[ "$check" == true ]]; then
    check_dangling_resources
else
    echo "No action specified. Use --delete to delete dangling resources or --check to check for them."
    usage
    exit 1
fi

# Summary of dangling resources
echo "Summary of dangling resources:"
# Add your summary logic here

echo "Script completed."
