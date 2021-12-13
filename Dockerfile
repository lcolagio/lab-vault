      FROM ${ARGOCD_REPO_SOURCE_IMAGE}
      USER root
      RUN curl -L -o /usr/local/bin/argocd-vault-plugin https://github.com/IBM/argocd-vault-plugin/releases/download/v1.5.0/argocd-vault-plugin_1.5.0_linux_amd64
      RUN chmod +x /usr/local/bin/argocd-vault-plugin
      USER argocd
