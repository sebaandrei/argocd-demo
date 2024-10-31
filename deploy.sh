#!/bin/bash

# Define the version for the Argo CD installation
ARGO_CD_VERSION="v2.12.6"

# Define the URL for the Argo CD installation manifest
ARGO_CD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_CD_VERSION}/manifests/ha/install.yaml"

# Create a namespace for Argo CD
kubectl create namespace argocd

# Apply the Argo CD installation manifest
kubectl apply -n argocd -f $ARGO_CD_MANIFEST_URL

# Wait for Argo CD components to be up and running
echo "Waiting for Argo CD components to be up and running..."
kubectl rollout status deployment/argocd-server -n argocd

# Patch the Argo CD ConfigMap to add server.insecure=true
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'

# Restart the Argo CD server pod to apply the ConfigMap changes
kubectl rollout restart deployment/argocd-server -n argocd

# # Create an ingress resource for Argo CD
# cat <<EOF | kubectl apply -f -
# apiVersion: networking.k8s.io/v1
# kind: Ingress
# metadata:
#   name: argocd-server-ingress
#   namespace: argocd
#   annotations:
#     cert-manager.io/cluster-issuer: letsencrypt-prod
#     nginx.ingress.kubernetes.io/ssl-redirect: "true"
#     nginx.ingress.kubernetes.io/proxy-body-size: "0"
#     nginx.ingress.kubernetes.io/whitelist-source-range: 130.255.154.223/32,45.149.209.158/32
# spec:
#   tls:
#   - hosts:
#     - argo.poc.y00n.org
#     secretName: argocd-server-tls
#   ingressClassName: nginx
#   rules:
#   - host: argo.poc.y00n.org
#     http:
#       paths:
#       - path: /
#         pathType: Prefix
#         backend:
#           service:
#             name: argocd-server
#             port:
#               number: 80
# EOF

# Print a message indicating the installation is complete
echo "Argo CD installation and ingress setup initiated. Please wait for the pods to be up and running."

# Create the ConfigMap for the kustomized-helm plugin
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: plugin-config
  namespace: argocd
data:
  plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: kustomized-helm
    spec:
      version: v1.0
      init:
        command: [sh, -c, 'helm dependency build']
      generate:
        command: [sh, -c, 'helm template --release-name release-name . > all.yaml && kustomize build']
EOF

# # Patch the Argo CD deployment to add the sidecar container
# kubectl patch deployment argocd-server -n argocd --type='json' -p='[
#   {
#     "op": "add",
#     "path": "/spec/template/spec/containers/-",
#     "value": {
#       "name": "my-plugin",
#       "command": ["/var/run/argocd/argocd-cmp-server"],
#       "image": "ubuntu",
#       "securityContext": {
#         "runAsNonRoot": true,
#         "runAsUser": 999
#       },
#       "volumeMounts": [
#         {
#           "mountPath": "/var/run/argocd",
#           "name": "var-files"
#         },
#         {
#           "mountPath": "/home/argocd/cmp-server/plugins",
#           "name": "plugins"
#         },
#         {
#           "mountPath": "/home/argocd/cmp-server/config/plugin.yaml",
#           "subPath": "plugin.yaml",
#           "name": "plugin-config"
#         },
#         {
#           "mountPath": "/tmp",
#           "name": "cmp-tmp"
#         }
#       ]
#     }
#   },
#   {
#     "op": "add",
#     "path": "/spec/template/spec/volumes/-",
#     "value": {
#       "name": "var-files",
#       "emptyDir": {}
#     }
#   },
#   {
#     "op": "add",
#     "path": "/spec/template/spec/volumes/-",
#     "value": {
#       "name": "plugins",
#       "emptyDir": {}
#     }
#   },
#   {
#     "op": "add",
#     "path": "/spec/template/spec/volumes/-",
#     "value": {
#       "configMap": {
#         "name": "plugin-config"
#       },
#       "name": "plugin-config"
#     }
#   },
#   {
#     "op": "add",
#     "path": "/spec/template/spec/volumes/-",
#     "value": {
#       "emptyDir": {},
#       "name": "cmp-tmp"
#     }
#   }
# ]'


# Retrieve and decode the admin password from the secret
ARGOCD_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)

# Print the admin password to the output
echo "Argo CD admin password: ${ARGOCD_ADMIN_PASSWORD}"
