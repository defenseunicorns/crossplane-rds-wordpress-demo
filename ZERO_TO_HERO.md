# Zero to Hero: Crossplane, EKS, RDS, and WordPress

This guide uses Crossplane in two powerful ways: first, to stand up an enclave in AWS with a VPC, subnets, and other typical network components and configurations to show how an infrastructure team can automate provisioning resources; second, to instantiate an RDS database in the VPC to show how development teams can be empowered to deploy their own resources.

_See the [README](README.md) for a focused walkthrough on Crossplane, RDS, and WordPress_

### Software

* k3d `^5.4.0`
* kubectl `^1.24`
* Crossplane CLI `^1.9.0`
* AWS CLI `^2.7.15`

### Prerequisites

* AWS credentials

# Infrastructure Team Use Case

## Stand up a local k3d cluster

```bash
k3d cluster create \
  local \
  --servers 1 \
  --api-port 6443
```

## Install and configure Crossplane in the k3d cluster

1. Create namespace
    ```bash
    kubectl create namespace crossplane-system
    ```

1. Install Crossplane
    ```bash
    helm upgrade -i crossplane --namespace crossplane-system crossplane-stable/crossplane
    ```

1. Install the Crossplane AWS Provider
    ```bash
    kubectl crossplane install provider crossplane/provider-aws:master
    ```

1. Add AWS credentials for the AWS Provider
    ```bash
    AWS_PROFILE=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $AWS_PROFILE)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $AWS_PROFILE)" > creds.conf
    
    kubectl create secret generic aws-creds -n crossplane-system --from-file=creds=creds.conf
    
    rm creds.conf
    ```

1. Configure the AWS Provider
    ```bash
    kubectl apply -f ./crossplane/provider-aws/providerconfig.yaml
    ```

## Install Composite Resource Definitions and Compositions for the enclave and EKS 

1. Install the enclave, EKS, and EKS nodegroup claim definitions
    ```bash
    kubectl apply -R -f ./crossplane/claim-definitions/enclave/

    kubectl apply -R -f ./crossplane/claim-definitions/eks-cluster/

    kubectl apply -R -f ./crossplane/claim-definitions/eks-managed-nodegroup/
    ```

1. Verify the Kubernetes API includes the enclave, EKS and EKS nodegroup definitions
    ```bash
    kubectl api-resources
    ```

## Create the enclave and EKS cluster

1. Apply the [Enclave and EKS claim](claim/eks-clsuter.yaml)
    ```bash
    kubectl apply -f claim/eks-cluster.yaml
    ```

1. Verify EKS is ready

    _Note: this can take more than 10 minutes to complete_
    ```bash
    kubectl get managed
    ```

1. Capture the VPC id for later
    ```bash
    export VPC_ID=$(kubectl get vpc.ec2.aws.crossplane.io -o jsonpath="{.items[0].status.atProvider.vpcId}")
    ```

1. Capture the DB Subnet Group Name for later
    ```bash
    export DB_SUBNET_GROUP=$(kubectl get dbsubnetgroup.database.aws.crossplane.io -o jsonpath="{.items[0].metadata.name}")
    ```

## Install and configure Crossplane in the EKS cluster

1. Grab the Kubernetes config file for the EKS cluster

    _Note: You will need to periodically refresh the EKS admin.conf_

    ```bash
    ./scripts/secret.sh
    ```

1. Create namespace
    ```bash
    kubectl create namespace crossplane-system
    ```

1. Install Crossplane
    ```bash
    helm upgrade -i crossplane --namespace crossplane-system crossplane-stable/crossplane
    ```

1. Install the Crossplane AWS Provider
    ```bash
    kubectl crossplane install provider crossplane/provider-aws:master
    ```

1. Add AWS credentials for the AWS Provider
    ```bash
    AWS_PROFILE=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $AWS_PROFILE)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $AWS_PROFILE)" > creds.conf
    
    kubectl create secret generic aws-creds -n crossplane-system --from-file=creds=creds.conf
    
    rm creds.conf
    ```

1. Configure the AWS Provider
    ```bash
    kubectl apply -f ./crossplane/provider-aws/providerconfig.yaml
    ```

## Install Composite Resource Definition and Composition for RDS 

1. Install the RDS composite resource and composition
    ```bash
    kubectl apply -R -f ./crossplane/claim-definitions/mysql-rds/
    ```

# Development Team Use Case

## Provision the RDS MySQL Database

1. Create an RDS claim
    Populate the VPC ID and DB Subnet Group Name and save this file as [`rds.yaml`](claim/rds.yaml)
    ```yaml
    ---
    apiVersion: databases.bigbang.dev/v1alpha1
    kind: MySQLChildInstance
    metadata:
      name: wordpress-mysql-rds
      namespace: default
    spec:
      parameters:
        storageGB: 10
        region: us-east-1
        availabilityZone: us-east-1a
        dbName: wordpressdb
        dbInstanceClass: db.t3.medium
        dbSubnetGroupName: REPLACE_ME
        vpcId: REPLACE_ME
      compositionSelector:
        matchLabels:
          provider: aws
      writeConnectionSecretToRef:
        name: mysql-rds
    ```

1. Apply the [RDS claim](claim/rds.yaml)
    ```bash
    kubectl apply -f ./claim/rds.yaml
    ```

1. Wait for the RDS instance to be ready

    _Note: this can take more than 10 minutes to complete_

    ```bash
    kubectl get managed
    ```

## Install WordPress

1. Get the RDS MySQL database's endpoint
    ```bash
    export DB_ENDPOINT=$(kubectl get secret mysql-rds -o jsonpath="{.data.endpoint}" | base64 -d)
    ```

1. Install wordpress/
    ```bash
    helm upgrade -i wp ./wordpress/ \
        --set mariadb.enabled=false \
        --set externalDatabase.host=$DB_ENDPOINT \
        --set externalDatabase.port=3306 \
        --set externalDatabase.user=mysqladmin \
        --set externalDatabase.database=wordpressdb \
        --set externalDatabase.existingSecret=mysql-rds
    ```

# Cleanup

## Remove WordPress and the RDS MySQL database

1. Grab the Kubernetes config file for the EKS cluster

    ```bash
    ./scripts/secret.sh
    ```

1. Uninstall WordPress
    ```bash
    helm uninstall wp
    ```

1. Remove the [RDS instance](claim/rds.yaml)
    ```bash
    kubectl delete -f ./claim/rds.yaml
    ```

1. Verify all resources are released
    ```
    kubectl get managed
    ```

## Remove the Enclave and EKS cluster

1. Ensure your kubeconfig points to the k3d cluster
    ```
    unset KUBECONFIG
    kubectl cluster-info
    ```

1. Remove the [Enclave and EKS cluster](claim/eks-clsuter.yaml)
    ```bash
    kubectl delete -f claim/eks-cluster.yaml
    ```

1. Verify all resources are released
    ```bash
    kubectl get managed
    ```

## Delete the k3d cluster

```bash
k3d cluster delete local
```