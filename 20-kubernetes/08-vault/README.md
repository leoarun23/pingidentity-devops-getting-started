## Overview of Vault Deployment

This repo will contain a vault deployment that you can use to demostrate integration with PingFederate and PingAccess to manage their corresponding MasterKeys (pf.pwk and pa.pwk). In addition, you can utilize Hashicorp Vault to manage license files, devops keys, product secrets, etc.

To help demostrate integration with Hashicorp Vault, you can clone Hashicrop's Vault helm chart to deploy a near-production environment to validate and manage Ping Identity product's master keys, license files, devops keys, and various secrets. 

Below are the specific configuration items we are using for our demostration deployment. In addition, we will be deploying Vault into Amazon Elastic Kubernetes Service (EKS) and using some of AWS's specific services (AWS KMS and AWS DynamoDB) to help simplify the deployment architecture. 

### Prerequisites

- [Helm](https://helm.sh/docs/intro/install/) - Hashicorp Vault uses Helm 3.
- Kubernetes 1.7
- OpenSSL or your favorite PKI tool. 

### Enable TLS

Before you deploy Vault using helm, add the tls keypair (public and private keys) and ca chain file as a kubernetes secret. The public certificate and private key should be seperate files. You can use openssl to quickly create a self-signed certificate or one issued/signed by your Certificate Authority. 

Note: If using a self-signed certificate, the public certificate is also the CA certificate.

```sh
kubectl create secret generic vault-certstore \
--from-file=vault.key=<local_path_to_tls_key>/tls.key \
--from-file=vault.crt=<local_path_to_tls_cert>/tls.crt \
--from-file=vault.ca=<local_path_to_ca_cert>/vault.ca    
```

To secure the Vault's endpoints update the following parameters in the values.yaml file:

##### global

Enable tls globally.

``` yaml
# TLS for end-to-end encrypted transport
tlsDisable: false
```

##### extraEnvironmentVars

The environment variable that will contain the path to the CA Certificate used for TLS.

```yaml
  # extraEnvironmentVars is a list of extra enviroment variables to set with the stateful set. These could be
  # used to include variables required for auto-unseal.
  extraEnvironmentVars:
    VAULT_CACERT: /vault/userconfig/vault-certstore/vault.ca
```

##### extraVolumes

The volume mount for the certificate store secret. This mount will contain the tls public certificate, private key and CA certificate.

```yaml
# extraVolumes is a list of extra volumes to mount. These will be exposed
# to Vault in the path `/vault/userconfig/<name>/`. The value below is
# an array of objects, examples are shown below.
extraVolumes:
- type: secret
  name: vault-certstore
```
##### ha

To enable TLS, navigate to the `ha` deployment section and add the following parameters to the `listener "tcp"` element:


```yaml
  # Run Vault in "HA" mode. There are no storage requirements unless audit log
  # persistence is required.  In HA mode Vault will configure itself to use Consul
  # for its storage backend.  The default configuration provided will work the Consul
  # Helm project by default.  It is possible to manually configure Vault to use a
  # different HA backend.
  ha:
    enabled: true
    replicas: 3

    # config is a raw string of default configuration when using a Stateful
    # deployment. Default is to use a Consul for its HA storage backend.
    # This should be HCL.
    config: |
      ui = true
      log_level = "Debug"

      listener "tcp" {
        tls_disable = 0
        address = "[::]:8200"
        cluster_address = "[::]:8201"
        tls_cert_file = "/vault/userconfig/vault-certstore/vault.crt"
        tls_key_file  = "/vault/userconfig/vault-certstore/vault.key"
        tls_client_ca_file = "/vault/userconfig/vault-certstore/vault.ca"          
      }
```

### Storage Backend

Since we are using AWS for our deployment, we can take advantage of various AWS service to simply our deployment architecture. The Hashicrop Vault helm chart has examples for using file and/or an existing Hashicorp Consul deployment. For this example we will be updating the high availability deployment to use AWS DynamoDB. 

##### AWS DynamoDB

---> Diagram

Create an AWS access key and secret with permissions to manage the dynamodb. 

Note: If the table does not exist in dynamodb, Vault will create the table for you. 

Permissions the Vault IAM user needs to manage dynamodb can be found [here](https://www.vaultproject.io/docs/configuration/storage/dynamodb/#required-aws-permissions).

Note: If you setup permissions specified at the link above, Vault will create the table if it does not already exist.

Check out [DynamoDB Storage Backend](https://www.vaultproject.io/docs/configuration/storage/dynamodb/) for additional parameters to use dynamodb as a storage mechanism.

Add your aws access and secret key as a kubernetes secret

```bash
create secret generic dynamodb_access_secret_keys \
--from-literal=AWS_ACCESS_KEY_ID=<YOUR_AWS_ACCCESS_KEY> \
--from-literal=AWS_SECRET_ACCESS_KEY=<YOUR_AWS_ACCCESS_KEY_SECRET>
```

Kubernetes can provide the secrets as environment variables which Vault can use so you do not accidently expose your the secret outside of kubernetes. 

```yaml
  # extraSecretEnvironmentVars is a list of extra enviroment variables to set with the stateful set.
  # These variables take value from existing Secret objects.
  extraSecretEnvironmentVars:
  - envName: AWS_SECRET_ACCESS_KEY
    secretName: dynamodb_access_secret_keys
    secretKey: AWS_SECRET_ACCESS_KEY
  - envName: AWS_ACCESS_KEY_ID
    secretName: dynamodb_access_secret_keys
    secretKey: AWS_ACCESS_KEY_ID
```

Update the dynamodb storage element with your corresponding AWS region and dynamodb table name.

```yaml
      storage "dynamodb" {
        ha_enabled = "true"
        region = "<aws_region>"
        table = "<dynamodb_table_name>"      
      }
```

### Auto Unseal

Since we like to keep things simple, we are using Vault's Auto Unseal AWS support.

##### AWS KMS

You will need to setup an AWS access key id and secret with the correct permissions. If you are using dynamodb for your backend storage, then just add the permissions to your AWS access key.

See the Hashicorp's Vault aws ksm [documentation]([documentation](https://www.vaultproject.io/docs/configuration/seal/awskms/#authentication)).

Vault can retrieve the AWS KMS Key ID via environment varaiable so it is not accidently exposed outside of the kubernetes environment.

Add the KMS Key as a kubernetes secret.

```bash
create secret generic aws_kms_key_id \
--from-literal=KMS_KEY_ID=<Your_KMS_KEY_ID> \
```
Reference the kubernetes secret in the values.yaml

```yaml
  # extraSecretEnvironmentVars is a list of extra enviroment variables to set with the stateful set.
  # These variables take value from existing Secret objects.
  extraSecretEnvironmentVars:
  - envName: VAULT_AWSKMS_SEAL_KEY_ID
    secretName: aws_kms_key_id
    secretKey: KMS_KEY_ID
```

Add a seal element to the config map of your Vault deployment (standalone | ha). Update the region parameter with your AWS region value.

```yaml
      seal "awskms" {
        region      = "<aws_region>"
      }
```

---> Diagram 

### Install Vault Helm Chart

1. Open your favorite terminal.
2. Navigate to the location where you cloned this repo.
3. Execute `helm install vault /.`
 ```bash
 NAME: vault
LAST DEPLOYED: Thu Mar 12 17:27:19 2020
NAMESPACE: ping-cloud-devops-eks-cleggett
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://www.vaultproject.io/docs/


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get vault
 ```

### Pod Authentication

In order for Ping Identity products and applications to take advantage of Vault, they must have a Vault client token to successully authenticate to Vault. For applications deployed in a kubernetes environment, we can use Vault's kubernetes auth method.

#### Kubernetes Auth Method

With this auth method enabled, Vault can use a pod's Kubernetes Service Account Token to authenticate and exchange for a Vault client token which is tied to a particular role in order to perform certain Vault operations. 

##### Get K8s Cluster Data

First, lets attach to our namespace where the Hashicorp vault will be deployed.

```bash
kubens ping-cloud-devops-eks-vault
```

Add a service account that will be deployed to all pods. Note, you can use the default service account, but for best practices sake, lets create a new one called `vault-auth`.

```bash
kubectl create serviceaccount vault-auth 
```

Lets retrieve the service account secret name and set an environment variable: `SA_SECRET_NAME`. 

```bash
export SA_SECRET_NAME=export SA_SECRET_NAME=$(kubectl get serviceaccounts vault-auth -o jsonpath="{.secrets[].name}")
```

Save the service account CA certificate, kubernetes cluster API hostname, and the service account token to environment variables. These variable values will be used in the kerberos auth method configuration.

```bash
export SA_CA_CRT=$(kubectl get secret $SA_SECRET_NAME -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)
```

```bash
export K8S_API_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
```

```bash
export SA_TOKEN=$(kubectl get secret $SA_SECRET_NAME -o jsonpath="{.data['token']}" | base64 --decode; echo)
```

---> Diagram

##### Add Vault Policies

TODO: Add the steps

##### Configure Kubernetes Auth

The below commands can be performed by the Vault operator or configuration management tool. 

Enable kubernetes auth. It is important to note that Vault does not need to be deployed in a kubernetes environment to support kubernetes auth. In addition, you can support multiple kubernetes clusters. 

```bash
kubectl exec vault-0 -- vault auth enable kubernetes
```

Configure the kubernetes auth mechanism.

```bash
kubectl exec vault-0 -- vault write auth/kubernetes/config \
token_reviewer_jwt=$SA_TOKEN \
kubernetes_host=$K8S_API_HOST \
kubernetes_ca_cert=$SA_CA_CRT
```

Register a role for each application/product. To give you more control over the permissions that each application/product has, we are using the following naming convention for roles:

`<k8s-namespace>-<environment>-<product_name>`

```
Example: 
  k8s-namespace = ping-cloud-devops-eks-apps
  environment = dev
  product_name = pingfederate

  ping-cloud-devops-eks-apps-dev-pingfederate
```

Update the below command with your role name, application namespace, and policy name before executing.

```bash
kubectl exec vault-0 -- vault write auth/kubernetes/role/<namespace>-<environment>-<product_name> \
        bound_service_account_names=vault-auth \
        bound_service_account_namespaces=<application_namespace> \
        policies=<policy> 
```

### Vault Secret Engines

##### Transit

##### CubbyHole
