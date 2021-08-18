# Lab Vault

## Source documentations
- https://cloud.redhat.com/blog/how-to-use-hashicorp-vault-and-argo-cd-for-gitops-on-openshift


## Install Vault for dev
```
oc new-project vault
oc project vault

helm repo add hashicorp https://helm.releases.hashicorp.com

oc adm policy add-scc-to-user privileged -z vault -n vault
oc adm policy add-scc-to-user privileged -z vault-agent-injector -n vault
helm install vault hashicorp/vault --set \ "global.openshift=true" --set "server.dev.enabled=true"

watch oc get pod
```

## configure Vault
```
oc -n vault rsh vault-0 

vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
exit
````

## Add Secret
```
oc -n vault  rsh vault-0 

vault kv put secret/vplugin/supersecret username="user-from-vault" password="pass-from-vault"
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
    ttl=1h

vault policy read vplugin
vault read auth/kubernetes/role/vplugin 

exit
```

## Install OpenShift GitOps

- https://github.com/redhat-developer/openshift-gitops-getting-started

### Configure ArgoCD

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

example: https://github.com/lcolagio/lab-vault/blob/master/openshift-gitops-conf/openshift-gitops.yml 

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

### check Added plugin configuration to cm
```
oc get cm  argocd-cm  -n openshift-gitops  -o yaml | more
```

### check plugin
```
oc rsh $(oc get pod -o name | grep openshift-gitops-repo-server-) ls /usr/local/bin
```




## Test usecases

### create new application project with argocd right

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

### Test usecase without-vault

```
oc delete application app-without-vault -n openshift-gitops

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-without-vault
  namespace: openshift-gitops
spec:
  destination:
    name: ''
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  source:
    path: applications/app-without-vault
    repoURL: 'https://github.com/lcolagio/lab-vault'
    targetRevision: HEAD
  project: default
EOF
```

### Test usecase application with vault plugin

```
oc delete application app-with-vault -n openshift-gitops

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-with-vault
  namespace: openshift-gitops
spec:
  destination:
    namespace: vplugin-demo
    server: 'https://kubernetes.default.svc'
  project: default
  source:
    path: applications/app-with-vault
    plugin:
      env:
        - name: AVP_K8S_ROLE
          value: vplugin
        - name: AVP_TYPE
          value: vault
        - name: AVP_VAULT_ADDR
          value: 'http://172.30.231.227:8200'
        - name: AVP_AUTH_TYPE
          value: k8s
      name: argocd-vault-plugin
    repoURL: 'https://github.com/lcolagio/lab-vault'
    targetRevision: HEAD
  syncPolicy: {}
EOF
```

```
# Application from git:
 - https://github.com/lcolagio/lab-vault -> applications/app-with-vault
kind: Secret
apiVersion: v1
metadata:
  namespace: vplugin-demo
  name: example-secret-vault
  annotations:
    ## avp_path: "secret/vplugin/supersecret"
    avp_path: "secret/data/vplugin/supersecret"
type: Opaque
stringData:
  username: <username>
  password: <password>
``` 

