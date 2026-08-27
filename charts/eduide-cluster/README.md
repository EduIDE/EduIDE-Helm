# eduide-cluster

![Version: 2.1.4](https://img.shields.io/badge/Version-2.1.4-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.2.0](https://img.shields.io/badge/AppVersion-1.2.0-informational?style=flat-square)

Cluster-scoped half of EduIDE: CRDs, the conversion webhook, ClusterRoles and
cert-manager issuers. Install once per cluster, before any eduide release.

*This chart was tested with Helm version v3.17.0.*
*Other versions may work as well, but if you encounter any issues, we recommend trying with the tested version to rule out version-specific problems.*

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| certmanager.namespace | string | `"cert-manager"` | the namespace where the cert-manager is installed |
| clusterIssuer | string | `"theia-cloud-selfsigned-issuer"` | The cluster issuer to use for the certificate |
| conversion.certMountPath | string | `"/etc/webhook/certs"` | The location of where the certificates are mounted into the container (needs to match with application.properties) |
| conversion.certReloadPeriod | int | `604800` | The certificate reload period in seconds |
| conversion.image | string | `"theiacloud/theia-cloud-conversion-webhook:1.2.0-next"` | The image of the webhook container |
| envoyProxy.annotations | object | `{}` |  |
| envoyProxy.create | bool | `false` |  |
| envoyProxy.labels | object | `{}` |  |
| envoyProxy.name | string | `"theia-shared-gateway"` |  |
| envoyProxy.namespace | string | `"envoy-gateway-system"` |  |
| envoyProxy.spec | object | `{}` |  |
| gateway | object | `{"addresses":[],"allowedRoutes":{"namespaces":{"from":"All"}},"annotations":{},"className":"envoy","create":true,"labels":{},"listeners":[],"name":"theia-shared-gateway","namespace":"eduide-system","redirects":[]}` | ------------------------------------------------------------------------ |
| gateway.create | bool | `true` | Create the shared Gateway. Set false only if you terminate and route traffic some other way; EduIDE then has no ingress of its own. |
| gateway.listeners | list | `[]` | The Gateway's listeners. **Required.** With none, no Gateway is created and nothing routes.  Every environment contributes four, named `<prefix>-landing`, `<prefix>-service`, `<prefix>-instances` and `<prefix>-webview`. Those names are load-bearing: each must match a `gateway.parentRefs[].sectionName` in that environment's values for the `eduide` chart, or its routes attach to nothing. The prefix is yours to choose and must be unique on the cluster.  A certificate that does not cover a listener's hostname is NOT detected - the Gateway reports Programmed=True and browsers reject it. See `managedCertificates` below, and note the webview listener needs a WILDCARD certificate that ACME HTTP-01 cannot issue.  For one environment at eduide.example.edu:  listeners:   - name: prod-landing     hostname: eduide.example.edu     tlsSecretName: eduide-tls   - name: prod-service     hostname: service.eduide.example.edu     tlsSecretName: eduide-tls   - name: prod-instances     hostname: instance.eduide.example.edu     tlsSecretName: eduide-tls   - name: prod-webview     hostname: "*.webview.instance.eduide.example.edu"     tlsSecretName: eduide-webview-tls  Each entry takes `name`, `hostname` and `tlsSecretName`, plus optionally `protocol` (HTTPS by default, HTTP for an ACME challenge listener), `port` and `allowedRoutes`. |
| gateway.redirects | list | `[]` | Permanent redirects from hostnames this cluster used to serve.  Each entry needs a listener of the same `name` on the Gateway - which `bootstrap-cluster.yml` emits from `spec.redirects` in the cluster manifest - and renders an HTTPRoute that 301s `from` to `to`, keeping the path and the query string.  redirects:   - name: legacy-landing     from: theia.example.edu     to: eduide.example.edu |
| gatewayAcmeIssuer.email | string | `""` |  |
| gatewayAcmeIssuer.enabled | bool | `false` |  |
| gatewayAcmeIssuer.name | string | `"letsencrypt-prod-gateway"` |  |
| gatewayAcmeIssuer.privateKeySecretName | string | `"letsencrypt-prod-gateway-priv-key"` |  |
| gatewayAcmeIssuer.server | string | `"https://acme-v02.api.letsencrypt.org/directory"` |  |
| gatewayAcmeIssuer.serviceType | string | `"ClusterIP"` |  |
| gatewayAcmeIssuer.solvers | list | `[]` | Override the ACME solvers entirely. Leave empty for the built-in HTTP-01 solver, which is enough for every hostname EXCEPT the webview wildcard.  ACME cannot issue a wildcard over HTTP-01. If you want cert-manager to issue `*.webview.instance.<host>` you need DNS-01, which means an API credential for your DNS zone. For example:  solvers:   - dns01:       cloudflare:         apiTokenSecretRef: { name: cloudflare-api-token, key: token }     selector:       dnsNames: ["*.webview.instance.eduide.example.edu"]   - http01:       gatewayHTTPRoute:         parentRefs:           - { group: gateway.networking.k8s.io, kind: Gateway, name: theia-shared-gateway, namespace: eduide-system }  If you cannot get a DNS-01 credential, obtain the wildcard some other way and supply it through `wildcardTLSSecret` below. |
| gatewayClass.annotations | object | `{}` |  |
| gatewayClass.controllerName | string | `"gateway.envoyproxy.io/gatewayclass-controller"` |  |
| gatewayClass.create | bool | `false` |  |
| gatewayClass.labels | object | `{}` |  |
| gatewayClass.parametersRef | object | `{}` |  |
| issuer.email | string | `"mmorlock@example.com"` | email used to issue let's encrypt certificates |
| issuerca.enable | bool | `true` | whether to install the CA certificate signer |
| issuerca.name | string | `"theia-cloud-ca-certificate-signer"` | name for the issuer preparing a self signed CA certificate |
| issuerprod.enable | bool | `false` | whether to install the let's encrypt production cluster issuer |
| issuerprod.name | string | `"letsencrypt-prod"` | name for the let's encrypt production cluster issuer |
| issuerprod.solvers | list | `[]` | ACME solver list for cert-manager (required when `issuerprod.enable=true`) |
| issuerstaging.name | string | `"theia-cloud-selfsigned-issuer"` | name for the self signed cluster issuer |
| managedCertificates.certificates | list | `[]` | Each entry takes either `hostname` (one name) or `dnsNames` (a list). `bootstrap-cluster.yml` fills this in from the environments on the cluster, so a new environment gets its certificate names without a second edit - which is how test3 ran for 184 days on a certificate that only covered test1, test2 and staging. |
| managedCertificates.enabled | bool | `false` |  |
| managedCertificates.issuerRef.kind | string | `"ClusterIssuer"` |  |
| managedCertificates.issuerRef.name | string | `"letsencrypt-prod"` |  |
| monitoring | object | `{"dashboardNamespace":"cattle-dashboards","enabled":false,"namespace":"cattle-monitoring-system","sessionNamespaces":[],"targetNamespaces":[]}` | ------------------------------------------------------------------------ |
| monitoring.dashboardNamespace | string | `"cattle-dashboards"` | Namespace the Grafana dashboard ConfigMaps go in. Must already exist and be watched by Grafana's sidecar. `cattle-dashboards` is Rancher's. |
| monitoring.enabled | bool | `false` | Create the PodMonitors and Grafana dashboards.  Off by default because it is not portable: it needs the Prometheus Operator CRDs (`monitoring.coreos.com/v1`) to exist, and the two namespaces below are Rancher's. Helm does not create namespaces it was not told to, so on a cluster without them the install fails outright on the dashboards.  Turn it on once you know where your Prometheus and Grafana look for these. |
| monitoring.namespace | string | `"cattle-monitoring-system"` | Namespace the PodMonitors go in. Must be somewhere your Prometheus discovers. `cattle-monitoring-system` is Rancher's; change it for any other monitoring stack. |
| operatorrole.name | string | `"operator-api-access"` | name for the operator's cluster role |
| servicerole.name | string | `"service-api-access"` | name for the services' cluster role |
| wildcardTLSSecret.certificate | string | `""` |  |
| wildcardTLSSecret.create | bool | `false` |  |
| wildcardTLSSecret.key | string | `""` |  |
| wildcardTLSSecret.name | string | `"static-theia-cert"` |  |
| wildcardTLSSecret.namespace | string | `"eduide-system"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
