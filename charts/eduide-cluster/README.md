# eduide-cluster

![Version: 2.2.0](https://img.shields.io/badge/Version-2.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.2.0](https://img.shields.io/badge/AppVersion-1.2.0-informational?style=flat-square)

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
| monitoring | object | `{"alerting":{"channels":[],"enabled":false,"grafanaUrl":"","groupInterval":"5m","groupWait":"30s","minSeverity":"warning","namespace":"eduide-system","repeatInterval":"4h","runbookUrl":"https://eduide.github.io/Docs/admins/operations","thresholds":{"certExpiryDays":21,"componentRestarts":3,"sessionCrashPerHour":5,"sessionOOMPerHour":3,"startupSeconds":90,"volumePercent":85},"webhookSecret":{"create":false,"data":{},"name":"eduide-alert-webhooks"}},"certManager":{"enabled":false,"namespace":"cert-manager","portName":"http-metrics","serviceName":"cert-manager"},"dashboardNamespace":"cattle-dashboards","enabled":false,"namespace":"cattle-monitoring-system","targetNamespaces":[]}` | ------------------------------------------------------------------------ |
| monitoring.alerting.channels | list | `[]` | Where to send alerts. Each entry needs `name`, `type` (`slack` or `discord`) and `secretKey`; Slack entries may also set `channel`. An empty list with alerting enabled means alerts fire but notify nobody, so the chart fails the render instead. |
| monitoring.alerting.enabled | bool | `false` | Create the PrometheusRule and the AlertmanagerConfig. |
| monitoring.alerting.grafanaUrl | string | `""` | Base URL of the Grafana that serves the EduIDE dashboards, with no trailing slash. Used to deep-link a notification straight to the affected session. Left empty, notifications carry no dashboard link. |
| monitoring.alerting.groupInterval | string | `"5m"` | How long to wait before notifying about new alerts added to a group. |
| monitoring.alerting.groupWait | string | `"30s"` | How long to wait for more alerts in a group before the first notification. |
| monitoring.alerting.minSeverity | string | `"warning"` | Lowest severity that reaches the notification channels: `warning` or `critical`. Anything below stays in Alertmanager and on the dashboards. This is what keeps the channels worth reading. |
| monitoring.alerting.namespace | string | `"eduide-system"` | Namespace both resources go in.  This is also the `namespace` label every EduIDE alert carries, and it is a routing artifact rather than the environment the alert is about. The Prometheus Operator defaults `alertmanagerConfigMatcherStrategy` to `OnNamespace`, which prepends `namespace = <the AlertmanagerConfig's own namespace>` to every route generated from it, so an alert must claim this namespace to reach a receiver at all.  The environment an alert is about is in `eduide_namespace`. Silence on that label, never on `namespace` - `namespace` is identical across every EduIDE alert and silencing it silences all of them. |
| monitoring.alerting.repeatInterval | string | `"4h"` | How long before an unresolved alert is sent again. |
| monitoring.alerting.runbookUrl | string | `"https://eduide.github.io/Docs/admins/operations"` | Base URL of the operations runbooks, with no trailing slash. |
| monitoring.alerting.thresholds.certExpiryDays | int | `21` | Days before certificate expiry to start warning. |
| monitoring.alerting.thresholds.componentRestarts | int | `3` | Restarts of a platform container within 15m before it counts as crash looping. |
| monitoring.alerting.thresholds.sessionCrashPerHour | int | `5` | Session crashes per hour in one environment before alerting. |
| monitoring.alerting.thresholds.sessionOOMPerHour | int | `3` | Session OOM kills per hour in one environment before alerting. |
| monitoring.alerting.thresholds.startupSeconds | int | `90` | p95 session startup, in seconds, that counts as too slow. |
| monitoring.alerting.thresholds.volumePercent | int | `85` | Workspace volume fill percentage that counts as nearly full. |
| monitoring.alerting.webhookSecret.create | bool | `false` | Create the Secret from `data` below. Off means the Secret already exists and is referenced by name only. |
| monitoring.alerting.webhookSecret.data | object | `{}` | Base64-encoded webhook URLs, keyed by the `secretKey` a channel names. Supplied by the workflow, not committed. |
| monitoring.alerting.webhookSecret.name | string | `"eduide-alert-webhooks"` | Name of the Secret channels read their URL from. |
| monitoring.certManager.enabled | bool | `false` | Create a ServiceMonitor for cert-manager's controller metrics. |
| monitoring.certManager.namespace | string | `"cert-manager"` | Namespace cert-manager runs in. |
| monitoring.certManager.portName | string | `"http-metrics"` | Name of the metrics port on that Service. |
| monitoring.certManager.serviceName | string | `"cert-manager"` | Name of cert-manager's metrics Service. |
| monitoring.dashboardNamespace | string | `"cattle-dashboards"` | Namespace the Grafana dashboard ConfigMaps go in. Must already exist and be watched by Grafana's sidecar. `cattle-dashboards` is Rancher's. |
| monitoring.enabled | bool | `false` | Create the PodMonitors and Grafana dashboards.  Off by default because it is not portable: it needs the Prometheus Operator CRDs (`monitoring.coreos.com/v1`) to exist, and the two namespaces below are Rancher's. Helm does not create namespaces it was not told to, so on a cluster without them the install fails outright on the dashboards.  Turn it on once you know where your Prometheus and Grafana look for these. |
| monitoring.namespace | string | `"cattle-monitoring-system"` | Namespace the PodMonitors go in. Must be somewhere your Prometheus discovers. `cattle-monitoring-system` is Rancher's; change it for any other monitoring stack. |
| monitoring.targetNamespaces | list | `[]` | Namespaces to watch. Bootstrap derives this from the environments on the cluster; it is also the namespace list every dashboard's picker offers. |
| operatorrole.name | string | `"operator-api-access"` | name for the operator's cluster role |
| servicerole.name | string | `"service-api-access"` | name for the services' cluster role |
| wildcardTLSSecret.certificate | string | `""` |  |
| wildcardTLSSecret.create | bool | `false` |  |
| wildcardTLSSecret.key | string | `""` |  |
| wildcardTLSSecret.name | string | `"static-theia-cert"` |  |
| wildcardTLSSecret.namespace | string | `"eduide-system"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
