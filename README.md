# Lab Vault

Deploy a peristant vault

## Source documentations
- https://cloud.redhat.com/blog/how-to-use-hashicorp-vault-and-argo-cd-for-gitops-on-openshift
- https://blog.ramon-gordillo.dev/2021/03/gitops-with-argocd-and-hashicorp-vault-on-kubernetes/
- https://wiki.net.extra.laposte.fr/confluence/pages/resumedraft.action?draftId=820811087&draftShareId=289e0ca5-e331-42a1-a8f5-a4eee9abfe77&
- https://github.com/IBM/argocd-vault-plugin/blob/main/docs/installation.md

## Build Image argocdrepo with plug-in vault

```
# Creer une image stream qui contiendra le build de l'image argocd-vault-plugin
ARGOCD_VAULT_PLUGIN_NAMESPACE=openshift-gitops

oc apply -f - <<EOF
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  labels:
    app: argocd-vault-plugin
  name: argocd-vault-plugin
  namespace: ${ARGOCD_VAULT_PLUGIN_NAMESPACE}
EOF
```

```
# Rechercher l'image ArgoCD repo utilsée par  L'opérateur OpenShift Gitops
# Ajouter manuellement le docker from dans le buidconfig
oc get ClusterServiceVersion openshift-gitops-operator.v1.3.1 -o yaml | grep ARGOCD_REPOSERVER_IMAGE  -A1

# ARGOCD_REPO_SOURCE_IMAGE=registry.redhat.io/openshift-gitops-1/argocd-rhel8@sha256:6087f905ccb8192fd640109694ba836ae87d107234a157b98723f175ce14c97d
ARGOCD_VAULT_PLUGIN_NAMESPACE=openshift-gitops
ARGOCD_REPO_SOURCE_IMAGE=registry.redhat.io/openshift-gitops-1/argocd-rhel8:v1.3.1

# Build Config
oc apply -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  labels:
    app: argocd-vault-plugin
  name: argocd-vault-plugin
  namespace: ${ARGOCD_VAULT_PLUGIN_NAMESPACE}
spec:
  output:
    to:
      kind: ImageStreamTag
      name: argocd-vault-plugin:131-150
  source:
    type: Dockerfile
    dockerfile: |
      FROM ${ARGOCD_REPO_SOURCE_IMAGE}
      USER root
      RUN curl -L -o /usr/local/bin/argocd-vault-plugin https://github.com/IBM/argocd-vault-plugin/releases/download/v1.5.0/argocd-vault-plugin_1.5.0_linux_amd64
      RUN chmod +x /usr/local/bin/argocd-vault-plugin
      USER argocd
  strategy:
    dockerStrategy:
      buildArgs:
      # - name: "NO_PROXY"
      #   value: "localhost,127.0.0.0,127.0.0.1,127.0.0.2,localaddress,.localdomain.com,.laposte.fr"
    type: Docker
EOF

oc start-build argocd-vault-plugin -n ${ARGOCD_VAULT_PLUGIN_NAMESPACE}
```

## Ajout d'une instance Vault de dev

```
# Creer une instance vault
oc new-project vault
oc project vault

helm repo add hashicorp https://helm.releases.hashicorp.com

helm install vault hashicorp/vault --set "global.openshift=true" --set "server.dev.enabled=true"

watch oc get pod
```

```
# Créer un serviceaccount qui sera utilisé par le vault pour s'assurer de la validité des tokens des services accounts

oc create serviceaccount vault-auth -n default

oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: default
EOF
```


```
# Récupérer le token du compte de service vault-auth
token_reviewer_jwt="$(oc serviceaccounts get-token vault-auth -n default)" 
echo $token_reviewer_jwt
```

```
# Ajouter manuellement le token dans token_reviewer_jwt=

vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="eyJhbGciOiJSUzI1NiIsImtpZCI6ImlyaUNPQ21CeEVzSDE0U2xZRDYtSE5hdTV3cGM3R09EMVlwR3EwNHVqbmcifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJkZWZhdWx0Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZWNyZXQubmFtZSI6InZhdWx0LWF1dGgtdG9rZW4taHp4dG0iLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoidmF1bHQtYXV0aCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjVjMWI1ZDM4LWI1MjktNDY4OC05ZWYwLWZmZThlMTlmYjcwOSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDpkZWZhdWx0OnZhdWx0LWF1dGgifQ.mxfaTTOuFTKSBcSRaxACMdsyzl4_0N86XVafJTz2yO3GTTTHdC6dsgRhL5dO7I2pcU-pmq-zHJKgQV7hj3WAdpvh0qCkIsIghksRyvr7CqWBEjtQp5f9ehtP2JAdatKL1zLMktWKGFFP6OQivAPR9ZfPYwjZdwtJaQA5-9OabH7rFA2jXXbCBLmuomDdR5sehs1bSjhsLf1Ly8TH2-mjfgEuKbPMcQxqf_BnWro1dR2JsURYegNBsPNScI_GA6i91h4qb23ymdpddHRnZ2DT9pU5LrmLJHxAYA87N__kn0F5IkI6iD7D94b7dLTpDMLcLKtQO8Tep1DcxU3Avnsf5LeqDOAAeRoogTbrK4nu5we0aNYF9mSZ743MWqVq1ljmE3K07kfYFRQnOB0N8jgEV6NNdydPDBojYbHDMEbX_te62pbeaoWrf8xKTBCnE3rTxzVai004VyDtUy0e2UOYXXF0GCAxGEixKfqkyHzpNIP_GYvLIZs5Tcr3aJsc0NC2_iu24WeIAt1lm8GXPbDFeLSDm9OKYMjbmwGqzXwLqANyW66JbzLUIkDSbqCeh8gFsRHLY4if4eXvn8fjVRTUhCzBeuH94yFiK8J-QXWZwpzu2-qbzC99Lh-etcOQQXGJm6ZVar5A5aY_y6y3mZcvicFbyOF0b_yKmp9-g6-mRdc" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

exit
```

```
# exemple de configuration si plusieurs instance kubernetes dans le même vault (si le vault est externe)
vault auth enable --path="kube-openshift-1207" kubernetes

vault write auth/kube-openshift-1207/config \
    token_reviewer_jwt="eyJhbGciOiJSUzI1NiIsImtpZCI6ImlyaUNPQ21CeEVzSDE0U2xZRDYtSE5hdTV3cGM3R09EMVlwR3EwNHVqbmcifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJkZWZhdWx0Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZWNyZXQubmFtZSI6InZhdWx0LWF1dGgtdG9rZW4taHp4dG0iLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoidmF1bHQtYXV0aCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjVjMWI1ZDM4LWI1MjktNDY4OC05ZWYwLWZmZThlMTlmYjcwOSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDpkZWZhdWx0OnZhdWx0LWF1dGgifQ.mxfaTTOuFTKSBcSRaxACMdsyzl4_0N86XVafJTz2yO3GTTTHdC6dsgRhL5dO7I2pcU-pmq-zHJKgQV7hj3WAdpvh0qCkIsIghksRyvr7CqWBEjtQp5f9ehtP2JAdatKL1zLMktWKGFFP6OQivAPR9ZfPYwjZdwtJaQA5-9OabH7rFA2jXXbCBLmuomDdR5sehs1bSjhsLf1Ly8TH2-mjfgEuKbPMcQxqf_BnWro1dR2JsURYegNBsPNScI_GA6i91h4qb23ymdpddHRnZ2DT9pU5LrmLJHxAYA87N__kn0F5IkI6iD7D94b7dLTpDMLcLKtQO8Tep1DcxU3Avnsf5LeqDOAAeRoogTbrK4nu5we0aNYF9mSZ743MWqVq1ljmE3K07kfYFRQnOB0N8jgEV6NNdydPDBojYbHDMEbX_te62pbeaoWrf8xKTBCnE3rTxzVai004VyDtUy0e2UOYXXF0GCAxGEixKfqkyHzpNIP_GYvLIZs5Tcr3aJsc0NC2_iu24WeIAt1lm8GXPbDFeLSDm9OKYMjbmwGqzXwLqANyW66JbzLUIkDSbqCeh8gFsRHLY4if4eXvn8fjVRTUhCzBeuH94yFiK8J-QXWZwpzu2-qbzC99Lh-etcOQQXGJm6ZVar5A5aY_y6y3mZcvicFbyOF0b_yKmp9-g6-mRdc" \
    kubernetes_host="https://api-paas-03.test.net.intra.laposte.fr:6443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
exit
```


## Ajout d'un jeux de test

```
# Ajout de secrets dans vault 

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
  bound_service_account_names=argocd-vault-plugin \
  bound_service_account_namespaces=openshift-gitops \
  policies=vplugin \
  ttl=1h

vault policy read vplugin
vault read auth/kubernetes/role/vplugin
```



## Configurer ArgoCD avec le plugin vault

```
# Ajouter un compte de service associer au plugin vault 
ARGOCD_VAULT_PLUGIN_NAMESPACE=openshift-gitops
oc create serviceaccount argocd-vault-plugin -n ${ARGOCD_VAULT_PLUGIN_NAMESPACE}
```

```
spec:
# Add rebuilded image with plugin vault
  repo:
    image: image-registry.openshift-image-registry.svc:5000/openshift-gitops/argocd-vault-plugin
    mountsatoken: true
    serviceaccount: argocd-vault-plugin
    version: 131-150
# Add Plugin vault configuration
  configManagementPlugins: |-
    - name: argocd-vault-plugin
      generate:
        command: ["argocd-vault-plugin"]
        args: ["generate", "./"]
```


```
# Vérifier la présence du plugin
oc project ${ARGOCD_VAULT_PLUGIN_NAMESPACE} 
oc rsh $(oc get pod -o name | grep openshift-gitops-repo-server-) ls /usr/local/bin/argocd-vault-plugin

# Vérification de la configuration du plugin ajouté dans la configmap
oc get cm argocd-cm -o yaml | grep configManagementPlugins -A4
```



## Test de login er trequêty au vault depuis argocd pod 

```
# se connecter en rsh au pod openshift-gitops-repo-server
ARGOCD_VAULT_PLUGIN_NAMESPACE=openshift-gitops
oc -n ${ARGOCD_VAULT_PLUGIN_NAMESPACE} rsh $(oc get pod -o name | grep repo-server)

OCP_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -k --request POST --data '{"jwt": "'"$OCP_TOKEN"'", "role": "vplugin"}' http://vault.vault.svc:8200/v1/auth/kubernetes/login

{"request_id":"ada5c976-2ed7-ccf0-2b51-782201c8287e","lease_id":"","renewable":false,"lease_duration":0,"data":null,"wrap_info":null,"warnings":null,"auth":{"client_token":"s.gVCbCRG0BcoZsp51plp4zikJ","accessor":"VYFdohSWZdmEBchyVslYPcx5","policies":["default","vplugin"],"token_policies":["default","vplugin"],"metadata":{"role":"vplugin","service_account_name":"vplugin","service_account_namespace":"openshift-gitops","service_account_secret_name":"vplugin-token-gvwln","service_account_uid":"e3de3959-1707-4474-83a1-1ba81fc0ae19"},"lease_duration":120,"renewable":true,"entity_id":"ba9ca5a9-fb99-4f40-99b5-6cfcc2bbfe00","token_type":"service","orphan":true}}
```

```
X_VAULT_TOKEN="s.gVCbCRG0BcoZsp51plp4zikJ"
curl -k --header "X-Vault-Token: $X_VAULT_TOKEN" http://vault.vault.svc:8200/v1/secret/data/vplugin/supersecret
{"request_id":"40c7e00b-78bf-5f21-bf7f-9681c9860519","lease_id":"","renewable":false,"lease_duration":0,"data":{"data":{"app-name1":"app-ex1","app-name2":"app-ex2","app-path":"app-to-bootstrap","password":"pass-from-vault","username":"user-from-vault"},"metadata":{"created_time":"2021-11-30T15:48:32.948978911Z","custom_metadata":null,"deletion_time":"","destroyed":false,"version":1}},"wrap_info":null,"warnings":null,"auth":null}
```


## Annexes

```
oc delete ImageStream argocd-vault-plugin -n ${ARGOCD_VAULT_PLUGIN_NAMESPACE}
oc delete BuildConfig argocd-vault-plugin -n ${ARGOCD_VAULT_PLUGIN_NAMESPACE}

```

