# Devlake POC
Devlake is a tool for building data pipelines to extract, transform, and load data from various sources into a data warehouse. This POC aims to demonstrate the capabilities of Devlake in a simple local setup.

# Prerequisites
- Docker or Podman.
- Kind.
- kubectl.
- Github token with the privileges to get data from the sources.

# Setup

1. Create a kind cluster:
   ```bash
   kind create cluster --name devlake
   ```

2. Install devlake using helm:

Information: https://devlake.apache.org/docs/GettingStarted/HelmSetup/

* Creating secrect:

```bash
export ENCRYPTION_SECRET=$(openssl rand -base64 2000 | tr -dc 'A-Z' | fold -w 128 | head -n 1)
```

* Install devlake:

```bash
helm repo add devlake https://apache.github.io/incubator-devlake-helm-chart
helm repo update
helm install devlake devlake/devlake --version=1.0-beta1 --set lake.encryptionSecret.secret=$ENCRYPTION_SECRET
```

Your will see an output like this:
```console
Welcome to use devlake.
Now please get the URL by running these commands:
  export NODE_PORT=$(kubectl get --namespace default -o jsonpath="{.spec.ports[0].nodePort}" services devlake-ui)
  export NODE_IP=$(kubectl get nodes --namespace default -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://$NODE_IP:$NODE_PORT
```

We can't follow exactly this output, because we are using kind, so we need to expose service to the host machine to be able to access, but first let's check that the pods are running:

```bash
kuecbtl get pods --namespace default
```
You should see running pods:
```console
k get pods
NAME                               READY   STATUS    RESTARTS   AGE
devlake-grafana-667cc94fbb-2j864   1/1     Running   0          48s
devlake-lake-64f9975db4-z2knc      1/1     Running   0          48s
devlake-mysql-0                    1/1     Running   0          48s
devlake-ui-646d8997b-llg2m         1/1     Running   0          48s
```

We need to check the services:
```bash
kubectl get services --namespace default
```

You should see the service `devlake-ui` with a port assigned, something like this:
```console
k get services
NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
devlake-grafana   ClusterIP   10.96.122.15    <none>        80/TCP           89s
devlake-lake      ClusterIP   10.96.107.53    <none>        8080/TCP         89s
devlake-mysql     ClusterIP   10.96.189.203   <none>        3306/TCP         89s
devlake-ui        NodePort    10.96.80.84     <none>        4000:32001/TCP   89s
kubernetes        ClusterIP   10.96.0.1       <none>        443/TCP          11m
```

Now we need to forward the port of the `devlake-ui` service to our host machine so we can access it:

```bash
kubectl port-forward --namespace default service/devlake-ui 4000:4000
```

Now we will be able to access the Devlake UI at [`http://localhost:4000`](http://localhost:4000).

# Usage
1. Open the Devlake UI in your browser at [`http://localhost:4000`](http://localhost:4000) and create a new connection to github. Follow the instructions from the documentation [here](https://devlake.apache.org/docs/Configuration/GitHub).

2. Add a Data Scope, for this POC we are only going to add as a data scope the upstream repository `istio-ecosystem/sail-operator`.

3. Create new project
   - Go to the Projects tab and create a new project.
   - Select the data scope you created in the previous step.
   - Name your project and save it.
   - Start collecting data

4. After the data collection is finished, you can explore the data in the Devlake UI. Open the Dashboards tab to see the available dashboards and explore the data collected from the GitHub repository.

Note that the password of the admin user is located in the secret `devlake-ui-admin-password` in the `default` namespace. You can retrieve it with the following command:

```bash
kubectl get secret devlake-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

Now you can navigate over the Devlake UI and explore the data collected from the GitHub repository.

# Cleanup
To clean up the resources created by this POC, you can delete the kind cluster:
```bash
kind delete cluster --name devlake
```

