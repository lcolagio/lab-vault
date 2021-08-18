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

vault kv put secret/data/vplugin/supersecret username="user-from-vault" password="password-from-vault"
vault kv get secret/data/vplugin/supersecret


vault policy write vplugin0 - <<EOF
path "secret/data/vplugin/supersecret" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/vplugin0 \
    bound_service_account_names=vplugin0 \
    bound_service_account_namespaces=vplugindemo \
    policies=vplugin \
    ttl=1h
```
