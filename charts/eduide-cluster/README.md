# eduide-cluster

![Version: 3.0.0-rc.10](https://img.shields.io/badge/Version-3.0.0--rc.10-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.0.0-rc.10](https://img.shields.io/badge/AppVersion-3.0.0--rc.10-informational?style=flat-square)

Cluster-scoped half of EduIDE 3.0: the control plane CRDs, the cluster identity marker and,
optionally, the Envoy Gateway GatewayClass and EnvoyProxy and cluster alerting.
Install once per cluster, before any eduide release.

## Install and upgrade notes

Install once per cluster, before any `eduide` release:

```sh
helm install eduide-cluster oci://ghcr.io/eduide/charts/eduide-cluster \
  --version 3.0.0-rc.10 -n eduide-system --create-namespace
```

The chart carries the control plane CRDs (`eduide-control-plane-crds`), the cluster identity ConfigMap `eduide-system/eduide-cluster-identity` (set `clusterName`) and, optionally, the Envoy Gateway GatewayClass and EnvoyProxy (`gatewayClass.create`, `envoyProxy.create`; `mergeGateways` defaults to true) and cert-manager alerting.
Gateways, certificates and issuers belong to the `eduide` release of each deployment.

**Do not upgrade this chart on a cluster that still runs a 2.x (Theia Cloud) installation.**
Version 3 no longer ships the Theia CRDs, so Helm would delete them and with them every Theia Cloud session and workspace.
The chart looks up the CRD `appdefinitions.theia.cloud` and fails the install or upgrade with a clear message when it exists.
Set `allowRemovingTheiaCloud: true` only when the old installation is gone or should be destroyed.
The check needs a cluster: `helm template` has no `lookup` and never trips it.
To run 3.x next to 2.x, use a separate cluster, or install `eduide-control-plane-crds` alone and leave this chart on the 2.x release line.

*This chart was tested with Helm version v3.17.0.*
*Other versions may work as well, but if you encounter any issues, we recommend trying with the tested version to rule out version-specific problems.*

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| oci://ghcr.io/eduide/eduide-control-plane/charts | eduide-control-plane-crds | 0.2.1 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| allowRemovingTheiaCloud | bool | `false` | Set to true to let an install or upgrade proceed on a cluster that still has the Theia Cloud CRD appdefinitions.theia.cloud. Removing the Theia CRDs deletes every Theia Cloud session and workspace with them, so the chart refuses by default. |
| clusterName | string | `""` | Name of this cluster. Written to the ConfigMap eduide-system/eduide-cluster-identity that the deploy workflows compare against the cluster they think they talk to. Empty renders no ConfigMap (the bootstrap workflow can write it with kubectl instead). |
| envoyProxy.annotations | object | `{}` |  |
| envoyProxy.create | bool | `false` |  |
| envoyProxy.labels | object | `{}` |  |
| envoyProxy.name | string | `"eduide"` |  |
| envoyProxy.namespace | string | `"envoy-gateway-system"` |  |
| envoyProxy.replicas | int | `1` | Data plane replica count, rendered into the spec at `provider.kubernetes.envoyDeployment.replicas`. Envoy Gateway stops reconciling that field when the EnvoyProxy leaves it out, which makes a manual scale to zero permanent. A `spec` that names its own replicas wins over this, and `null` leaves the field out. Ignored for a spec that scales some other way (`envoyHpa`, `envoyDaemonSet`, a `Host` provider). |
| envoyProxy.spec | object | `{}` | EnvoyProxy spec (hostPort, service type, resources and so on). The chart adds `mergeGateways: true` so all EduIDE deployments share one data plane; set `mergeGateways` here to override. |
| gateway.className | string | `"envoy"` | Name of the GatewayClass rendered when `gatewayClass.create` is true. |
| gatewayClass.annotations | object | `{}` |  |
| gatewayClass.controllerName | string | `"gateway.envoyproxy.io/gatewayclass-controller"` |  |
| gatewayClass.create | bool | `false` |  |
| gatewayClass.labels | object | `{}` |  |
| gatewayClass.parametersRef | object | `{}` | Usually points at the EnvoyProxy below, e.g. {group: gateway.envoyproxy.io, kind: EnvoyProxy, name: eduide, namespace: envoy-gateway-system} |
| monitoring | object | `{"alerting":{"channels":[],"enabled":false,"groupInterval":"5m","groupWait":"30s","minSeverity":"warning","namespace":"eduide-system","repeatInterval":"4h","runbookUrl":"https://eduide.github.io/Docs/admins/operations","thresholds":{"certExpiryDays":21},"webhookSecret":{"create":false,"data":{},"name":"eduide-alert-webhooks"}},"certManager":{"enabled":false,"namespace":"cert-manager","portName":"http-metrics","selectorLabels":{"app.kubernetes.io/component":"controller","app.kubernetes.io/name":"cert-manager"}},"enabled":false,"namespace":"cattle-monitoring-system","targetNamespaces":[]}` | ------------------------------------------------------------------------ |
| monitoring.alerting.channels | list | `[]` | Where to send alerts. Each entry needs `name`, `type` (`slack` or `discord`) and `secretKey`; Slack entries may also set `channel`. An empty list with alerting enabled means alerts fire but notify nobody, so the chart fails the render instead.  A channel may set `environments: [ns, ...]` to receive only that installation's alerts. One cluster can host installations belonging to different people - Bonn and Mannheim share a cluster and each has its own Discord - and without scoping, both would see the other's incidents.  Anything no scoped channel claims goes to **every** channel. That is how cluster-scoped alerts still get out: a certificate expiring is not about any one tenant's namespace, and dropping it for failing to match a tenant route would lose exactly the alerts that matter most.    channels:     - name: mannheim       type: discord       secretKey: discord-mannheim       environments: [eduide-mannheim]     - name: platform       type: slack       secretKey: slack-platform       channel: "#eduide-alerts" |
| monitoring.alerting.enabled | bool | `false` | Create the PrometheusRule and the AlertmanagerConfig. |
| monitoring.alerting.groupInterval | string | `"5m"` | How long to wait before notifying about new alerts added to a group. |
| monitoring.alerting.groupWait | string | `"30s"` | How long to wait for more alerts in a group before the first notification. |
| monitoring.alerting.minSeverity | string | `"warning"` | Lowest severity that reaches the notification channels: `warning` or `critical`. Anything below stays in Alertmanager. This is what keeps the channels worth reading. |
| monitoring.alerting.namespace | string | `"eduide-system"` | Namespace both resources go in.  This is also the `namespace` label every EduIDE alert carries, and it is a routing artifact rather than the environment the alert is about. The Prometheus Operator defaults `alertmanagerConfigMatcherStrategy` to `OnNamespace`, which prepends `namespace = <the AlertmanagerConfig's own namespace>` to every route generated from it, so an alert must claim this namespace to reach a receiver at all.  The environment an alert is about is in `eduide_namespace`. Silence on that label, never on `namespace` - `namespace` is identical across every EduIDE alert and silencing it silences all of them. |
| monitoring.alerting.repeatInterval | string | `"4h"` | How long before an unresolved alert is sent again. |
| monitoring.alerting.runbookUrl | string | `"https://eduide.github.io/Docs/admins/operations"` | Base URL of the operations runbooks, with no trailing slash. |
| monitoring.alerting.thresholds.certExpiryDays | int | `21` | Days before certificate expiry to start warning. |
| monitoring.alerting.webhookSecret.create | bool | `false` | Create the Secret from `data` below. Off means the Secret already exists and is referenced by name only. |
| monitoring.alerting.webhookSecret.data | object | `{}` | Base64-encoded webhook URLs, keyed by the `secretKey` a channel names. Supplied by the workflow, not committed. |
| monitoring.alerting.webhookSecret.name | string | `"eduide-alert-webhooks"` | Name of the Secret channels read their URL from. |
| monitoring.certManager.enabled | bool | `false` | Create a ServiceMonitor for cert-manager's controller metrics. |
| monitoring.certManager.namespace | string | `"cert-manager"` | Namespace cert-manager runs in. |
| monitoring.certManager.portName | string | `"http-metrics"` | Name of the metrics port on that Service. |
| monitoring.certManager.selectorLabels | object | `{"app.kubernetes.io/component":"controller","app.kubernetes.io/name":"cert-manager"}` | Labels identifying cert-manager's controller Service.  A ServiceMonitor selects on Service **labels**; there is no matcher for `metadata.name`. These are the labels cert-manager's own chart sets, and they are values because a release installed under a different name keeps the labels and changes their values. Get them wrong and the ServiceMonitor is created with no targets and reports no error.  Check with:   kubectl -n cert-manager get svc cert-manager --show-labels |
| monitoring.enabled | bool | `false` | Create the monitoring resources below. Off by default: it needs the Prometheus Operator CRDs (`monitoring.coreos.com/v1`). |
| monitoring.namespace | string | `"cattle-monitoring-system"` | Namespace the ServiceMonitor goes in. Must be somewhere your Prometheus discovers. `cattle-monitoring-system` is Rancher's. |
| monitoring.targetNamespaces | list | `[]` | Namespaces whose certificates the alerts cover, besides the release and alerting namespaces. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
