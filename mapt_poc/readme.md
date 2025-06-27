# Create the AWS instance:

```bash
podman run -d --rm --name create-snc \
            -v ${PWD}:/workspace:z \
            -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
            -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
            -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
            quay.io/redhat-developer/mapt:v0.9.3 aws openshift-snc create \
                --project-name snc \
                --backed-url "file:///workspace" \
                --conn-details-output "/workspace" \
                --pull-secret-file /workspace/mapt_poc/pullsecret/crc_secret \
                --tags project=crc,environment=local,user=frherrer \
                --version 4.19.0 \
                --spot \
		        --project-name poc-mapt
# Check logs 
podman logs -f create-snc
```

Under the `/workspace` directory, you will find the connection details for the cluster. 

# Delete the cluster
    
```bash
podman run -d --name destroy-snc \
            -v ${PWD}:/workspace:z \
            -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
            -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
            -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
            quay.io/redhat-developer/mapt:v0.9.3 aws openshift-snc destroy \
                --project-name snc \
                --backed-url "file:///workspace" 
# Check logs 
podman logs -f destroy-snc
```

# Cleanup pulumi files
If you want to remove the pulumi files created by the `mapt` command, you can run the following command:

```bash
rm -rf .pulumi
```

Note: that not removing this files after a failure can cause issues when trying to create a new cluster.

