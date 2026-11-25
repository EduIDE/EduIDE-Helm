# eduide

![Version: 3.0.3](https://img.shields.io/badge/Version-3.0.3-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.0.1](https://img.shields.io/badge/AppVersion-3.0.1-informational?style=flat-square)

EduIDE on the Go control plane for one deployment: control plane, landing page, Gateway,
optional ACME Issuer and the IDETemplates and IDEPools. The CRDs are a per-cluster install
(eduide-cluster, or eduide-control-plane-crds) and must be installed first.

## Install

Install the CRDs first (chart `eduide-cluster`, or `eduide-control-plane-crds` alone), then one release per deployment in its own namespace:

```sh
helm install my-deployment oci://ghcr.io/eduide/charts/eduide \
  --version 3.0.3 -n my-deployment --create-namespace -f values.yaml
```

The IDE images default to the chart appVersion, so a chart release pins the IDE images it was tested with.
`deployments/test3/` in the repository is a worked example.

*This chart was tested with Helm version v3.17.0.*
*Other versions may work as well, but if you encounter any issues, we recommend trying with the tested version to rule out version-specific problems.*

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| oci://ghcr.io/eduide/eduide-control-plane/charts | eduide-control-plane | 0.2.5 |
| oci://ghcr.io/eduide/eduide-control-plane/charts | eduide-landing-page | 0.2.5 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| catalog.c-standalone.buildSystems[0] | string | `"make"` |  |
| catalog.c-standalone.buildSystems[1] | string | `"bazel"` |  |
| catalog.c-standalone.displayName | string | `"C"` |  |
| catalog.c-standalone.image | string | `"eduide/c-standalone"` |  |
| catalog.c.buildSystems[0] | string | `"make"` |  |
| catalog.c.buildSystems[1] | string | `"bazel"` |  |
| catalog.c.displayName | string | `"C"` |  |
| catalog.c.image | string | `"eduide/c-artemis"` |  |
| catalog.c.listed | bool | `false` |  |
| catalog.go-standalone.buildSystems[0] | string | `"go"` |  |
| catalog.go-standalone.displayName | string | `"Go"` |  |
| catalog.go-standalone.image | string | `"eduide/go-standalone"` |  |
| catalog.go.buildSystems[0] | string | `"go"` |  |
| catalog.go.displayName | string | `"Go"` |  |
| catalog.go.image | string | `"eduide/go-artemis"` |  |
| catalog.go.listed | bool | `false` |  |
| catalog.java-17-standalone.buildSystems[0] | string | `"maven"` |  |
| catalog.java-17-standalone.buildSystems[1] | string | `"gradle"` |  |
| catalog.java-17-standalone.displayName | string | `"Java 17"` |  |
| catalog.java-17-standalone.image | string | `"eduide/java-17-standalone"` |  |
| catalog.java-17-standalone.resources.limits.memory | string | `"3000M"` |  |
| catalog.java-17-standalone.resources.requests.cpu | string | `"500m"` |  |
| catalog.java-17.buildSystems[0] | string | `"maven"` |  |
| catalog.java-17.buildSystems[1] | string | `"gradle"` |  |
| catalog.java-17.displayName | string | `"Java 17"` |  |
| catalog.java-17.image | string | `"eduide/java-17-artemis"` |  |
| catalog.java-17.listed | bool | `false` |  |
| catalog.java-17.resources.limits.memory | string | `"3000M"` |  |
| catalog.java-17.resources.requests.cpu | string | `"500m"` |  |
| catalog.java-25-standalone.buildSystems[0] | string | `"maven"` |  |
| catalog.java-25-standalone.buildSystems[1] | string | `"gradle"` |  |
| catalog.java-25-standalone.displayName | string | `"Java 25"` |  |
| catalog.java-25-standalone.image | string | `"eduide/java-25-standalone"` |  |
| catalog.java-25-standalone.resources.limits.memory | string | `"3000M"` |  |
| catalog.java-25-standalone.resources.requests.cpu | string | `"500m"` |  |
| catalog.java-25.buildSystems[0] | string | `"maven"` |  |
| catalog.java-25.buildSystems[1] | string | `"gradle"` |  |
| catalog.java-25.displayName | string | `"Java 25"` |  |
| catalog.java-25.image | string | `"eduide/java-25-artemis"` |  |
| catalog.java-25.listed | bool | `false` |  |
| catalog.java-25.resources.limits.memory | string | `"3000M"` |  |
| catalog.java-25.resources.requests.cpu | string | `"500m"` |  |
| catalog.javascript-standalone.buildSystems[0] | string | `"node"` |  |
| catalog.javascript-standalone.buildSystems[1] | string | `"web"` |  |
| catalog.javascript-standalone.displayName | string | `"JavaScript"` |  |
| catalog.javascript-standalone.image | string | `"eduide/javascript-standalone"` |  |
| catalog.javascript.buildSystems[0] | string | `"node"` |  |
| catalog.javascript.buildSystems[1] | string | `"web"` |  |
| catalog.javascript.displayName | string | `"JavaScript"` |  |
| catalog.javascript.image | string | `"eduide/javascript-artemis"` |  |
| catalog.javascript.listed | bool | `false` |  |
| catalog.python-standalone.buildSystems[0] | string | `"python"` |  |
| catalog.python-standalone.displayName | string | `"Python"` |  |
| catalog.python-standalone.image | string | `"eduide/python-standalone"` |  |
| catalog.python.buildSystems[0] | string | `"python"` |  |
| catalog.python.displayName | string | `"Python"` |  |
| catalog.python.image | string | `"eduide/python-artemis"` |  |
| catalog.python.listed | bool | `false` |  |
| catalog.rust-standalone.buildSystems[0] | string | `"cargo"` |  |
| catalog.rust-standalone.displayName | string | `"Rust"` |  |
| catalog.rust-standalone.image | string | `"eduide/rust-standalone"` |  |
| catalog.rust-standalone.resources.limits.memory | string | `"3000M"` |  |
| catalog.rust.buildSystems[0] | string | `"cargo"` |  |
| catalog.rust.displayName | string | `"Rust"` |  |
| catalog.rust.image | string | `"eduide/rust-artemis"` |  |
| catalog.rust.listed | bool | `false` |  |
| catalog.rust.resources.limits.memory | string | `"3000M"` |  |
| certManager.issuerRef.kind | string | `"ClusterIssuer"` |  |
| certManager.issuerRef.name | string | `""` |  |
| eduide-control-plane.config.deployment | string | `""` |  |
| eduide-control-plane.config.gateway.name | string | `""` |  |
| eduide-control-plane.config.gateway.namespace | string | `""` |  |
| eduide-control-plane.config.gateway.sectionName | string | `""` |  |
| eduide-control-plane.config.hosts.instance | string | `""` |  |
| eduide-control-plane.config.hosts.service | string | `""` |  |
| eduide-control-plane.config.hosts.webview | string | `""` |  |
| eduide-control-plane.config.oidc.clientIDs | list | `[]` |  |
| eduide-control-plane.config.oidc.gatewayClientID | string | `""` |  |
| eduide-control-plane.config.oidc.issuerURL | string | `""` |  |
| eduide-control-plane.oidc.clientSecretName | string | `""` |  |
| eduide-landing-page.config.keycloak.clientId | string | `"eduide-landing"` |  |
| eduide-landing-page.config.keycloak.realm | string | `"eduide"` |  |
| eduide-landing-page.config.keycloak.url | string | `"https://auth.example.org"` |  |
| eduide-landing-page.config.title | string | `"EduIDE"` |  |
| eduide-landing-page.gateway.name | string | `""` |  |
| eduide-landing-page.gateway.namespace | string | `""` |  |
| eduide-landing-page.gateway.sectionName | string | `""` |  |
| eduide-landing-page.host | string | `""` |  |
| gateway.annotations | object | `{}` |  |
| gateway.className | string | `""` |  |
| gateway.create | bool | `true` |  |
| images.registry | string | `"ghcr.io/eduide"` |  |
| images.tag | string | `""` |  |
| issuer.acme.email | string | `""` |  |
| issuer.acme.server | string | `"https://acme-v02.api.letsencrypt.org/directory"` |  |
| issuer.create | bool | `false` |  |
| issuer.name | string | `"acme"` |  |
| oidcBridge.enabled | bool | `false` |  |
| oidcBridge.image | string | `"nginxinc/nginx-unprivileged:1.29-alpine"` |  |
| oidcBridge.replicas | int | `2` |  |
| templateDefaults.env[0].name | string | `"THEIA"` |  |
| templateDefaults.env[0].value | string | `"1"` |  |
| templateDefaults.env[1].name | string | `"SCORPIO_THEIA_ENV_STRATEGY"` |  |
| templateDefaults.env[1].value | string | `"data-bridge"` |  |
| templateDefaults.gitUriAllowCredentials | bool | `false` |  |
| templateDefaults.persistence.allowed[0] | string | `"none"` |  |
| templateDefaults.persistence.allowed[1] | string | `"volume"` |  |
| templateDefaults.persistence.default | string | `"none"` |  |
| templateDefaults.port | int | `3000` |  |
| templateDefaults.resources.limits.cpu | string | `"2"` |  |
| templateDefaults.resources.limits.memory | string | `"2400M"` |  |
| templateDefaults.resources.requests.cpu | string | `"200m"` |  |
| templateDefaults.resources.requests.memory | string | `"500M"` |  |
| templateDefaults.runAsUser | int | `101` |  |
| templateDefaults.timeouts.idle | string | `"60m"` |  |
| templateDefaults.timeouts.max | string | `"24h"` |  |
| templateDefaults.timeouts.warning | string | `"50m"` |  |
| templates | object | `{}` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
