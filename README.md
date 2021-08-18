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
oc rsh vault-0 

vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
exit
````

## Add Secret
```
oc rsh vault-0 

vault kv put secret/data/vplugin/supersecret username="user-from-vault" password="password-from-vault"
vault kv get secret/data/vplugin/supersecret

vault policy write vplugin - <<EOF
path "secret/data/vplugin/supersecret" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/vplugin \
    bound_service_account_names=vplugin \
    bound_service_account_namespaces=vplugindemo \
    policies=vplugin \
    ttl=1h
exit
```


# Install OpenShift GitOps

- https://github.com/redhat-developer/openshift-gitops-getting-started

## Configure ArgoCD

```
oc project openshift-gitops

cat << EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vplugin
EOF
```

## Edit CR subscription "openshift-gitops-operator"
```
oc edit subscription openshift-gitops-operator -n openshift-operators
````
### 
```
spec:
  config:
    env:
      - name: DISABLE_DEX
        value: 'false'
```

## Edit CR argocd "openshift-gitops"
```
oc edit argocd openshift-gitops -n openshift-gitops
```

```
spec:

### Add Dex

  dex:
    openShiftOAuth: true

### Add Rbac

  rbac:
    defaultPolicy: 'role:readonly'
    policy: 'g, ADMIN, role:admin'
    scopes: '[groups]'

### Add rebuilded image with plugin vault

  repo:
    image: quay.io/pbmoses/pmo-argovault
    mountsatoken: true
    serviceaccount: vplugin
    version: v1.2

### Add Plugin vault configuration

  configManagementPlugins: |-
    - name: argocd-vault-plugin
      generate:
        command: ["argocd-vault-plugin"]
        args: ["generate", "./"]
```

## check Added plugin configuration to cm
```
oc get cm  argocd-cm  -n openshift-gitops  -o yaml | more
```

## check plugin
```
oc rsh $(oc get pod -o name | grep openshift-gitops-repo-server-) ls /usr/local/bin
```
