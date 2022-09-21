# Crossplane RDS Wordpress Demo

This guide uses Crossplane do instantiate an RDS MySQL database and deploy and connect WordPress to that database.

### Next Steps and Alibis

* Publish XRDs and compositions in OCI-compliant containers instead of applying composite resource definitions and compositions directly
* Follow a GitOps workflow to deploy RDS MySQL database and WordPress
* Update RDS Instance secret creation to use [Vault](https://crossplane.io/docs/v1.9/guides/vault-as-secret-store.html) or an alternative
* Create a Zarf package to automate WordPress application delivery with an RDS MySQL database

### Software

* kubectl `^1.24`
* Crossplane CLI `^1.9.0`
* AWS CLI `^2.7.15`

### Prerequisites

* AWS credentials
* EKS cluster
    * Crossplane
    * AWS provider
    * RDS XRD and composition
* VPC ID available
* DB Subnet Group Name available

_Note: [Zero-to-Hero](ZERO_TO_HERO.md) is a more complete walkthrough that includes steps to satisfy prerequisites through WordPress_

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
        --set externalDatabase.host=$DB_ENDPOINT
        --set externalDatabase.port=3306
        --set externalDatabase.user=mysqladmin
        --set externalDatabase.database=wordpressdb
        --set externalDatabase.existingSecret=mysql-rds
    ```

## Cleanup

1. Uninstall WordPress
    ```bash
    helm uninstall wp
    ```

1. Remove the [RDS instance](claim/rds.yaml)
    ```bash
    kubectl delete -f ./claim/rds.yaml
    ```
