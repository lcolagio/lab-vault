# Lab Vault

## Source documentations
- https://cloud.redhat.com/blog/how-to-use-hashicorp-vault-and-argo-cd-for-gitops-on-openshift


## Install Vault for dev
```
oc new-project vault
oc project vault

helm repo add hashicorp https://helm.releases.hashicorp.com

helm install vault hashicorp/vault \
  --set "global.openshift=true" \
  --set "server.dev.enabled=true"

watch oc get pod
```

## Configure Vault
```
oc -n vault rsh vault-0 

vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
exit
````

## Add Secret to vault
```
oc -n vault  rsh vault-0 

vault kv put secret/vplugin/supersecret \
 username="user-from-vault" \
 password="pass-from-vault" \
 app-path="app-to-bootstrap" \
 app-name1=app-ex1 \
 app-name2=app-ex2
 
vault kv get secret/vplugin/supersecret

vault policy write vplugin - <<EOF
path "secret/data/vplugin/supersecret" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/vplugin \
    bound_service_account_names=vplugin \
    bound_service_account_namespaces=openshift-gitops \
    policies=vplugin \
    ttl=2m

vault policy read vplugin
vault read auth/kubernetes/role/vplugin 

exit
```

## Install OpenShift GitOps

- https://github.com/redhat-developer/openshift-gitops-getting-started

### Add a service account for vault plugin

```
oc project openshift-gitops

cat << EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vplugin
EOF
```

### Edit CR subscription "openshift-gitops-operator"
```
oc edit subscription openshift-gitops-operator -n openshift-operators
```

```
spec:
  config:
    env:
      - name: DISABLE_DEX
        value: 'false'
```

### Edit CR argocd "openshift-gitops"

example: https://github.com/lcolagio/lab-vault-plugin/blob/master/openshift-gitops-conf/openshift-gitops.yml 

```
oc edit argocd openshift-gitops -n openshift-gitops
```

```
spec:

# Add Dex

  dex:
    openShiftOAuth: true

# Add Rbac

  rbac:
    defaultPolicy: 'role:readonly'
    policy: 'g, ADMIN, role:admin'
    scopes: '[groups]'

# Add rebuilded image with plugin vault

  repo:
    image: quay.io/pbmoses/pmo-argovault
    mountsatoken: true
    serviceaccount: vplugin
    version: v1.2

# Add Plugin vault configuration

  configManagementPlugins: |-
    - name: argocd-vault-plugin
      generate:
        command: ["argocd-vault-plugin"]
        args: ["generate", "./"]
```

## Check Instalation

### Check added plugin inside image

```
oc project openshift-gitops
oc rsh $(oc get pod -o name | grep openshift-gitops-repo-server-) ls /usr/local/bin
```

### Check Added plugin configuration to cm
```
oc project openshift-gitops
oc get cm  argocd-cm  -n openshift-gitops  -o yaml | more
```

### Check connection vault from pod openshift-gitops-repo-server-xxx to vault
```
oc project openshift-gitops
oc rsh $(oc get pod -o name | grep openshift-gitops-repo-server-)
```

#### Get token SA vplugin
```
OCP_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -k --request POST --data '{"jwt": "'"$OCP_TOKEN"'", "role": "vplugin"}' http://vault.vault.svc:8200/v1/auth/kubernetes/login
```
Example of correct output
```
{"request_id":"1fb5bdac-7c72-46b5-23c9-3045cb948b44","lease_id":"","renewable":false,"lease_duration":0,"data":null,"wrap_info":null,"warnings":null,"auth":{"client_token":"s.rNLGuD9bMaxh6gOrgQgWtcAH","accessor":"zBTGFnN4dWYlMu9xbTuktFrO","policies":["default","vplugin"],"token_policies":["default","vplugin"],"metadata":{"role":"vplugin","service_account_name":"vplugin","service_account_namespace":"openshift-gitops","service_account_secret_name":"vplugin-token-wkpzw","service_account_uid":"d5886f2a-5f80-4214-b6c1-b240b3aec5cb"},"lease_duration":3600,"renewable":true,"entity_id":"5eba6062-885b-03d4-0525-fa51899b916d","token_type":"service","orphan":true}}
```

#### Get client_token from
```
X_VAULT_TOKEN="s.rNLGuD9bMaxh6gOrgQgWtcAH"

curl -k --header "X-Vault-Token: $X_VAULT_TOKEN" http://vault.vault.svc:8200/v1/vplugin/data/example/example-auth
```

Example of correct output
```
{"request_id":"53362ea2-85a8-157e-ec86-66c59d8de4ac","lease_id":"","renewable":false,"lease_duration":0,"data":{"data":{"app-name1":"app-ex1","app-name2":"app-ex2","app-path":"app-to-bootstrap","password":"pass-from-vault","username":"user-from-vault"},"metadata":{"created_time":"2021-08-24T09:08:15.000352374Z","deletion_time":"","destroyed":false,"version":1}},"wrap_info":null,"warnings":null,"auth":null}
```


>>>>>>>>>>>>>>>>

## Test usecases


### Create vplugin-demo project with openshift-gitops-argocd-application rolebinding

```
oc new-project vplugin-demo

cat << EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: vplugin-demo-role-binding
  namespace: vplugin-demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
EOF
```

### 1 - Test argocd deployment whitout vault plugin

Just to test argocd without vault plugin

```
oc delete application app-test-argocd -n openshift-gitops

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-test-argocd
  namespace: openshift-gitops
spec:
  destination:
    name: ''
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  source:
    path: applications/app-test-argocd
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  project: default
EOF
```

### 2 - Test secret with vault plugin

```
oc delete application app-app-secret -n openshift-gitops

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-app-secret
  namespace: openshift-gitops
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    path: applications/app-secret
    plugin:
      env:
        - name: AVP_K8S_ROLE
          value: vplugin
        - name: AVP_TYPE
          value: vault
        - name: AVP_VAULT_ADDR
          value: 'http://vault.vault.svc:8200'
        - name: AVP_AUTH_TYPE
          value: k8s
      name: argocd-vault-plugin
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy: {}
EOF
```

This argocd application deploys a secret that containts annotation to path and un field used by vault-plugin
- https://github.com/lcolagio/lab-vault-plugin/tree/master/applications/app-secret

```
kind: Secret
apiVersion: v1
metadata:
  namespace: vplugin-demo
  name: example-secret-vault
  annotations:
    avp_path: "secret/data/vplugin/supersecret"
type: Opaque
stringData:
  username: <username>
  password: <password>
``` 

### 3 - Test configmap with vault plugin

```
oc delete application app-configmap -n openshift-gitops

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-configmap
  namespace: openshift-gitops
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    path: applications/app-configmap
    plugin:
      env:
        - name: AVP_K8S_ROLE
          value: vplugin
        - name: AVP_TYPE
          value: vault
        - name: AVP_VAULT_ADDR
          value: 'http://vault.vault.svc:8200'
        - name: AVP_AUTH_TYPE
          value: k8s
      name: argocd-vault-plugin
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy: {}
EOF
```

This argocd application deploys this configmap that containts annotation to path and un field used by vault-plugin
- https://github.com/lcolagio/lab-vault-plugin/blob/master/applications/app-configmap/configmap.yml

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-configmap-vault
  namespace: vplugin-demo
  annotations:
    
    avp_path: "secret/data/vplugin/supersecret"
data:
  example.property.1: <username>
  example.property.2: <password>
```

### 4 - Test to bootstrap application argocd 

```
oc delete application app-to-bootstrap -n openshift-gitops

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-to-bootstrap-with-vaultplugin
  namespace: openshift-gitops
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    path: applications/app-to-bootstrap
    plugin:
      env:
        - name: AVP_K8S_ROLE
          value: vplugin
        - name: AVP_TYPE
          value: vault
        - name: AVP_VAULT_ADDR
          value: 'http://vault.vault.svc:8200'
        - name: AVP_AUTH_TYPE
          value: k8s
      name: argocd-vault-plugin
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy: {}
EOF
```

This argocd application app-to-bootstrap-with-vaultplugin bootstrap this applications that containts annotation to path and un field used by vault-plugin
- https://github.com/lcolagio/lab-vault-plugin/blob/master/applications/app-to-bootstrap/bootstrap-app1.yml
- https://github.com/lcolagio/lab-vault-plugin/blob/master/applications/app-to-bootstrap/bootstrap-app2.yml
- https://github.com/lcolagio/lab-vault-plugin/blob/master/applications/app-to-bootstrap/bootstrap_app_helm1.yml 
- https://github.com/lcolagio/lab-vault-plugin/blob/master/applications/app-to-bootstrap/bootstrap_app_helm2.yml 
```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: boostrap-app1
  namespace: openshift-gitops
  annotations: 
    avp_path: "secret/data/vplugin/supersecret"
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    path: applications/<app-name1>
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy:
    automated: {}
```

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: boostrap-app2
  namespace: openshift-gitops
  annotations:
    avp_path: "secret/data/vplugin/supersecret"
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    path: applications/<app-name1>
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy:
    automated: {}
```

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: boostrap-app-helm1
  namespace: openshift-gitops
  annotations:
    avp_path: "secret/data/vplugin/supersecret"
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    helm:
      parameters:
        - name: serviceAccount.name
          value: app-helm1
        - name: secret.name
          value: app-helm1
        - name: secret.username
          value: <username>
        - name: secret.password
          value: <password>
    path: applications/app-helm
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy:
    automated: {}
  ```

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: boostrap-app-helm2
  namespace: openshift-gitops
  annotations:
    avp_path: "secret/data/vplugin/supersecret"
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    helm:
      parameters:
        - name: serviceAccount.name
          value: app-helm2
        - name: secret.name
          value: app-helm2
        - name: secret.username
          value: <username>
        - name: secret.password
          value: <password>
    path: applications/app-helm
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy:
    automated: {}
  ```

### 5 - Test to bootstrap helm application 

oc delete application app-helm -n openshift-gitops

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-helm
  namespace: openshift-gitops
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    helm:
      parameters:
        - name: serviceAccount.name
          value: app-helm
        - name: secret.name
          value: app-helm
    path: applications/app-helm
    repoURL: 'https://github.com/lcolagio/lab-vault-plugin'
    targetRevision: HEAD
  syncPolicy: {}
EOF

## Some troubleshooting tips

### 1 - Acces logs from pod openshift-gitops-repo-server-xxxx
```
oc -n openshift-gitops logs $(oc get pod -o name | grep openshift-gitops-repo-server-)
```


### 2 - Test connection via Rsh to openshift-gitops-repo-server-xxxx where vault-plugin was added
```
oc -n openshift-gitops rsh $(oc get pod -o name | grep openshift-gitops-repo-server-)
```

#### Get vault cluster-IP for port 8200 for tests below

Use the right endpoint to connect to vault

```
oc get service -n vault

NAME                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
vault                      ClusterIP   172.30.231.227   <none>        8200/TCP,8201/TCP   38h
```

#### Get token SA vplugin
```
OCP_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -k --request POST --data '{"jwt": "'"$OCP_TOKEN"'", "role": "vplugin"}' http://vault.vault.svc:8200/v1/auth/kubernetes/login
```
Example of correct output
```
{"request_id":"ada5c976-2ed7-ccf0-2b51-782201c8287e","lease_id":"","renewable":false,"lease_duration":0,"data":null,"wrap_info":null,"warnings":null,"auth":{"client_token":"s.gVCbCRG0BcoZsp51plp4zikJ","accessor":"VYFdohSWZdmEBchyVslYPcx5","policies":["default","vplugin"],"token_policies":["default","vplugin"],"metadata":{"role":"vplugin","service_account_name":"vplugin","service_account_namespace":"openshift-gitops","service_account_secret_name":"vplugin-token-gvwln","service_account_uid":"e3de3959-1707-4474-83a1-1ba81fc0ae19"},"lease_duration":120,"renewable":true,"entity_id":"ba9ca5a9-fb99-4f40-99b5-6cfcc2bbfe00","token_type":"service","orphan":true}}
```

#### Get client_token from
```
X_VAULT_TOKEN="s.gVCbCRG0BcoZsp51plp4zikJ"

curl -k --header "X-Vault-Token: $X_VAULT_TOKEN" http://vault.vault.svc:8200/v1/secret/data/vplugin/supersecret
```

Example of correct output
```
{"request_id":"a5be8dd9-9e1d-78c0-4c6c-4d9dba2586b6","lease_id":"","renewable":false,"lease_duration":0,"data":{"data":{"password":"pass-from-vault-v4","username":"user-from-vault-v4"},"metadata":{"created_time":"2021-08-18T16:21:46.703847125Z","deletion_time":"","destroyed":false,"version":4}},"wrap_info":null,"warnings":null,"auth":null}
```

### Error examples

#### error 400 : No vault server available
```
rpc error: code = Unknown desc = Manifest generation error (cached): `argocd-vault-plugin generate ./` failed exit status 1: Error: Error making API request. URL: PUT http://172.30.231.227:8200/v1/auth/kubernetes/login Code: 400. Errors: * missing client token Usage: argocd-vault-plugin generate <path> [flags] Flags: -c, --config-path string path to a file containing Vault configuration (YAML, JSON, envfile) to use -h, --help help for generate -s, --secret-name string name of a Kubernetes Secret containing Vault configuration data in the argocd namespace of your ArgoCD host (Only available when used in ArgoCD) Error making API request. URL: PUT http://172.30.231.227:8200/v1/auth/kubernetes/login Code: 400. Errors: * missing client token
```

#### No vault plugin service account in openshift-gitops namesapce 
```
Unable to create application: application spec is invalid: InvalidSpecError: Unable to generate manifests in app-test2: rpc error: code = Unknown desc = `argocd-vault-plugin generate ./` failed exit status 1: Error: open /var/run/secrets/kubernetes.io/serviceaccount/token: no such file or directory Usage: argocd-vault-plugin generate <path> [flags] Flags: -c, --config-path string path to a file containing Vault configuration (YAML, JSON, envfile) to use -h, --help help for generate -s, --secret-name string name of a Kubernetes Secret containing Vault configuration data in the argocd namespace of your ArgoCD host (Only available when used in ArgoCD) open /var/run/secrets/kubernetes.io/serviceaccount/token: no such file or directory
```

#### Error 500 : Namespace not authorized
```
rpc error: code = Unknown desc = `argocd-vault-plugin generate ./` failed exit status 1: Error: Error making API request. URL: PUT http://172.30.231.227:8200/v1/auth/kubernetes/login Code: 500. Errors: * namespace not authorized Usage: argocd-vault-plugin generate <path> [flags] Flags: -c, --config-path string path to a file containing Vault configuration (YAML, JSON, envfile) to use -h, --help help for generate -s, --secret-name string name of a Kubernetes Secret containing Vault configuration data in the argocd namespace of your ArgoCD host (Only available when used in ArgoCD) Error making API request. URL: PUT http://172.30.231.227:8200/v1/auth/kubernetes/login Code: 500. Errors: * namespace not authorized
```

