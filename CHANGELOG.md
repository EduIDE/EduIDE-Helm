# Changelog

## [Unreleased]

## [eduide 2.10.0] - 2026-11-14

- [eduide] Add `operator.metricsPort`. When set, the operator serves Prometheus metrics on a `metrics` port, starting with `theiacloud_sessions_ended_total{reason, app_definition}`: the sessions it stopped for inactivity or for reaching the lifetime limit. Default 0, which renders exactly as before
- [eduide-cluster] Add a PodMonitor for the operator's `metrics` port and a "Sessions ended per hour, by reason" panel to the sessions dashboard. Without `operator.metricsPort` the PodMonitor finds no target and the panel stays empty

Upgrade notes:

- Set `operator.metricsPort` only with an EduIDE-Cloud release that has `--metricsPort` (the first EduIDE-Cloud release that contains EduIDE/EduIDE-Cloud#167). An older operator rejects the option and does not start

## [eduide 2.9.0] - 2026-11-14

- [eduide] Redirect a request for an ended session to the landing page's `/session-ended` page instead of answering 5xx ([#39](https://github.com/EduIDE/EduIDE-Helm/pull/39)). The redirect is the instances route's catch-all rule, so a live session's longer path still wins. Only 302 is accepted, because eager sessions reuse instance paths. Turn it off with `gateway.routes.sessionEndedRedirect.enabled: false`
- [eduide-cluster] Version bump only, to keep both charts on the same version

Upgrade notes:

- Pair this with a landing page image that serves `/session-ended`. An older image falls back to its start page, which is still better than the 5xx it replaces

## [eduide 2.8.1] - 2026-11-13

- [eduide] Show the "Are you still here?" dialog after 50 minutes without input instead of 55, so students get ten minutes of warning before the 60-minute inactivity timeout. Both values are now explicit in `appDefinitions.defaults.monitor.activityTracker` (`timeoutAfter: 60`, `notifyAfter: 50`)
- [eduide-cluster] No changes; bumped with eduide, since both charts release at one version

## [eduide 2.8.0] - 2026-11-11

- [eduide] [eduide-cluster] Add `global.nodeSelector`, which pins every EduIDE workload to the nodes carrying those labels: the operator, the REST service, the landing page, image preloading and the conversion webhook. The operator gets it as `--sessionNodeSelector key=value,...` for the session pods it creates. Default empty, which renders exactly as before ([#73](https://github.com/EduIDE/EduIDE-Helm/issues/73))
- [eduide] `preloading.nodeSelector` falls back to `global.nodeSelector` when empty. Set, it still wins

- [eduide] Pin EduIDE-Cloud 1.3.0, the first release with `--sessionNodeSelector`, which also rejects selector entries that are not valid Kubernetes labels at startup
- [eduide] Update the workspace garbage collector to chart 0.2.0, which reads `global.nodeSelector`

Upgrade notes:

- `global.nodeSelector` pins sessions only with an operator that supports `--sessionNodeSelector`. An installation that overrides `versions.cloud` with a release before 1.3.0 must leave it unset: such an operator rejects the option and does not start
- Prewarmed instances created before the upgrade keep running where they are until they are replaced. Delete them once after setting the value
- The shared cache does not read `global.nodeSelector`; it is off in every installation
- Set the same `global.nodeSelector` on `eduide-cluster` to pin the conversion webhook

## [eduide 2.7.3] - 2026-11-09

- [eduide] Update the workspace garbage collector to chart 0.1.1 and image `5896ca3`, with the security dependency fixes and the Go 1.26 build

## [eduide 2.7.2] - 2026-11-06

- [eduide] Fix image preloading on 2.7.1: the oauth2-proxy image is distroless, so the default `/bin/sh -c echo` init container could not start (`StartError`, CrashLoopBackOff on every node). It now runs `/bin/oauth2-proxy --version`, which exits 0

## [eduide 2.7.1] - 2026-11-06

- [eduide] Preload the oauth2-proxy image (`quay.io/oauth2-proxy/oauth2-proxy:<operator.oAuth2ProxyVersion>`) when Keycloak is on. Every session pod runs it as a sidecar, so a node without it pulled it on the first session

## [eduide 2.7.0] - 2026-11-06

- [eduide] Split the app list into `appDefinitions.catalog` (the IDE images EduIDE officially releases), `appDefinitions.apps` (an installation's own apps and overrides, merged over the catalog entry of the same name) and `appDefinitions.enabled` (the names an installation offers; empty offers every definition)
- [eduide] Rename every app to its plain image name: `java-17-latest` becomes `java-17`, `c-templates-latest` becomes `c-templates`, and so on. `landingPage.appDefinition` defaults to `java-17-templates`
- [eduide] Add Java 25 (`java-25`, `java-25-templates` with Maven and Gradle) to the catalog
- [eduide] Remove `rust-latest` and `ocaml-latest`. EduIDE no longer builds these images, so the next EduIDE release publishes no tag for them
- [eduide] A name in `appDefinitions.enabled` with no definition is skipped, and `helm install`/`helm upgrade` print a warning naming it
- [eduide] Pin EduIDE 1.5.0 (`appVersion`): IDE images with data bridge v0.0.17, scorpio 2.1.1, theia-cloud-monitor v1.2.2 and without SCANOSS; no rust, haskell or ocaml images

Upgrade notes:

- Installations on chart defaults lose Rust and OCaml, keep the other six apps and gain Java 25 and Java 25 templates. Release this chart before any installation moves `versions.ide` to an EduIDE release without rust and ocaml images: on an older chart, the defaults point at tags that do not exist
- **The rename replaces every AppDefinition.** Helm deletes the `-latest` ones, which also deletes the session ingresses, prewarmed pods and sidecars they own, so running sessions end. Anything that refers to an app by name has to move to the new name: Artemis exercises (`theiaImage`), saved workspaces, `landingPage.appDefinition` and `apps` overrides in values files
- `apps.<name>: null` still removes an app. To migrate a null list, replace it with `enabled: [...]` naming what the installation offers
- With a non-empty `enabled`, an `apps` entry renders only if `enabled` names it. Add an installation's own app to `enabled` as well

## [eduide 2.6.2] - 2026-11-06

- [eduide] Pin EduIDE-Cloud 1.2.2, the release after the remaining dependency security fixes. The operator, service and webhook code is unchanged from 1.2.1

## [eduide 2.6.1] - 2026-11-06

- [eduide] Pin EduIDE-Landing-Page 1.3.1, which carries the remaining dependency security fixes

## [eduide 2.6.0] - 2026-11-06

- [eduide] Add `preloading.nodeSelector`, so the preloading DaemonSet can run on selected nodes only. Default empty, which renders exactly as before
- [eduide-cluster] [eduide] Stop serving AppDefinition versions the conversion webhook cannot map ([#52](https://github.com/EduIDE/EduIDE-Helm/pull/52)). This merged after 2.5.1 was published without a version bump, so 2.6.0 is the first chart that carries it

## [eduide 2.5.1] - 2026-11-06

- [eduide] Add `landingPage.sentry.dsn`. The landing page no longer has a built-in Sentry endpoint, so an installation with `landingPage.sentry.enable: true` must set it, or Sentry stays off
- [eduide] Remove the `SENTRY_ENABLE` env var from the landing page deployment. The landing page reads its config from `config.js`, so nothing used it
- [eduide] Run the landing page without root: port 8080 in the container (the Service stays on 80), `runAsNonRoot`, a read-only root filesystem, no capabilities, the `RuntimeDefault` seccomp profile, and an `emptyDir` on `/tmp`
- [eduide] Add `landingPage.trustedArtemisHosts`. A link with `artemisToken` starts a session on its own only when the host in both `gitUri` and `artemisUrl` is on this list. Otherwise the student has to click Launch
- [eduide] Pin EduIDE-Cloud 1.2.1 and EduIDE-Landing-Page 1.3.0, the releases this chart's operator flags and landing page settings need
- [eduide] The landing page footer shows the tag of the running landing page image (`v1.2.2`, or `pr-53` for a test image) instead of a hand-set string. `landingPage.footerLinks.attribution.version` still overrides it, so drop that value from an environment to get the real version

Upgrade notes:

- This chart needs a landing page image that listens on 8080: the release containing the non-root change. An older image runs as root, so its pods do not start under `runAsNonRoot`. If you override `versions.landingPage` or `landingPage.image`, move them to that release
- Installations relying on Artemis auto-start must set `landingPage.trustedArtemisHosts`. The default is empty, so every such link waits for a click

Security hardening (secure-by-default; environments already override the sensitive values):

- [eduide] Wire the operator session env-injection allowlist (`operator.allowedEnvFromSecrets`, `operator.allowedEnvFromConfigMaps`, `operator.allowCustomEnvFromMap`), passed as `--allowedEnvFromSecrets` / `--allowedEnvFromConfigMaps` / `--allowCustomEnvFromMap`. Empty = deny, matching EduIDE-Cloud [#144](https://github.com/EduIDE/EduIDE-Cloud/pull/144)
- [eduide] Add NetworkPolicies isolating session pods (`networkPolicies.enabled`, default on): default-deny ingress/egress, DNS egress always allowed, general outbound egress allowed by default (`networkPolicies.allowExternalEgress`, set `false` for DNS only), ingress to session ports from the gateway namespace, and an explicit block of the cloud metadata IP `169.254.169.254/32`
- [eduide] Allow the operator to reach session pods on the data bridge and monitor ports (`networkPolicies.dataBridgePort`, `networkPolicies.monitorPort`), so the default-deny does not drop environment injection into eager sessions or stall the activity tracker. Eager pods are only selected from EduIDE-Cloud #146 on.
- [eduide] Exclude private ranges from session egress (`networkPolicies.privateEgressCidrs`) so sessions cannot reach the cluster's pods and services, and allow language server sidecars explicitly (`session-allow-sidecars`). Clusters whose pod or service CIDRs are outside the private ranges must add them.
- [eduide] Default `appDefinitions.defaults.monitor.port` and `networkPolicies.monitorPort` to 8081, the monitor extension's own server
- [eduide] Namespace-scope the operator RBAC: bind the broad namespaced verbs through a RoleBinding by default (`operator.clusterWideRbac`, default false) instead of a cluster-wide ClusterRoleBinding. The genuinely cluster-scoped resources the operator cannot avoid (read-only `customresourcedefinitions`, listed at startup, and read-only `persistentvolumes`, with write access only for the `MINIKUBE` provider that creates them) are granted separately via a dedicated minimal per-namespace ClusterRole + ClusterRoleBinding that is always rendered, so the default binding no longer leaves the operator unable to list CRDs and crashlooping
- [eduide] Move `SERVICE_AUTH_TOKEN` and `KEYCLOAK_CLIENTSECRET` out of the `service-config` ConfigMap into the `service-config-secret` Secret, and source the operator's `--serviceAuthToken` from that Secret instead of a plaintext arg
- [eduide] Require a unique per-environment `keycloak.cookieSecret` (removed the committed default; the template now fails if it is unset), and set oauth2-proxy `cookie_secure="true"`

## [eduide 2.4.0] - 2026-09-28

- [eduide] Serve a static maintenance page instead of Envoy's raw `no healthy upstream` when the landing page is down (`maintenancePage.enabled`, default on)
- [eduide] Add a readiness probe to the REST service, and a `preStop` drain and `maxUnavailable: 0` to the landing page and REST service, so deploys keep a ready pod
- [eduide] Add `landingPage.replicas` and `service.replicas`, with a PodDisruptionBudget (`podDisruptionBudget.enabled`) and node spreading when above 1

## [1.2.0] - estimated between 2025-11 and 2026-05

## [1.1.2] - 2025-09-26

- [theia-cloud] Use ingress path type ImplementationSpecific instead of Prefix [#99](https://github.com/eclipse-theia/theia-cloud-helm/pull/99)

## [1.1.1] - 2025-08-01

- [theia-cloud-base] Extend operator and service K8S permissions for eager start handling [#86](https://github.com/eclipse-theia/theia-cloud-helm/pull/86)
- [theia-cloud] Add admin group configuration for the service deployment [#87](https://github.com/eclipse-theia/theia-cloud-helm/pull/87)
- [theia-cloud] Make LandingPage optional [#88](https://github.com/eclipse-theia/theia-cloud-helm/pull/88)
- [theia-cloud] Make OAuth2 Proxy's allowed redirect domains configurable [#89](https://github.com/eclipse-theia/theia-cloud-helm/pull/89)
- [theia-cloud-crds] Allow to set cert reload period in conversion webhook [#91](https://github.com/eclipse-theia/theia-cloud-helm/pull/91)
- [theia-cloud-base] Extend service K8S permissions for config store [#94](https://github.com/eclipse-theia/theia-cloud-helm/pull/94)

## [1.0.1] - 2025-03-24

- No Helm Chart related changes. See the [Theia Cloud changelog](https://github.com/eclipse-theia/theia-cloud/blob/1.0.1/CHANGELOG.md#101---2025-03-24).

## [1.0.0] - 2024-11-29

- No Helm Chart related changes. See the [Theia Cloud changelog](https://github.com/eclipse-theia/theia-cloud/blob/main/CHANGELOG.md#100---2024-11-29).

## [0.12.0] - 2024-10-30

- [.github/workflows] Update actions [#77](https://github.com/eclipse-theia/theia-cloud-helm/pull/77)
- [theia-cloud] Add `ingress.instances.configurationSnippets` to values which allows to set nginx configurations via the `nginx.ingress.kubernetes.io/configuration-snippet` annotation [#76](https://github.com/eclipsesource/theia-cloud-helm/pull/76)
- [theia-cloud] Add custom secretNames to wildcard instances [#73](https://github.com/eclipse-theia/theia-cloud-helm/pull/73)
- [theia-cloud] Fix theia-cloud helm chart not being updateable [#69](https://github.com/eclipse-theia/theia-cloud-helm/pull/69)
- [documentation] Add links to cluster prerequisites [#68](https://github.com/eclipse-theia/theia-cloud-helm/pull/68)

### Breaking Changes in 0.12.0

- [theia-cloud] Move `ingress.instanceName` to `ingress.instances.name` [#76](https://github.com/eclipsesource/theia-cloud-helm/pull/76)
- [theia-cloud] Move `ingress.proxyBodySize` to `ingress.instances.proxyBodySize` [#76](https://github.com/eclipsesource/theia-cloud-helm/pull/76)
- [theia-cloud] Move `ingress.allWildcardSecretNames` to `ingress.instances.allWildcardSecretNames` [#76](https://github.com/eclipsesource/theia-cloud-helm/pull/76)
- [theia-cloud] Remove webview wildcard from default values [#72](https://github.com/eclipse-theia/theia-cloud-helm/pull/72/files)

## [0.11.0] - 2024-07-23

- [theia-cloud-crds] Add option field to CRDs and increase version to `Session.v1beta8`, `Workspace.v1beta5` and `AppDefinition.v1beta10` [#55](https://github.com/eclipsesource/theia-cloud-helm/pull/55) | [#293](https://github.com/eclipsesource/theia-cloud/pull/293)
- [theia-cloud] Add configurable image preloading [#56](https://github.com/eclipsesource/theia-cloud-helm/pull/56)
- [theia-cloud] Add landing page configuration options for logo file extension, loading text, user info title & text [#58](https://github.com/eclipsesource/theia-cloud-helm/pull/58) - contributed on behalf of STMicroelectronics
- [theia-cloud-base] Self signed certificates are now signed by a Theia Cloud certificate authority. The certificate of the authority may be exported and imported in your Browser for easier local testing [#57](https://github.com/eclipsesource/theia-cloud-helm/pull/57)
- [theia-cloud-crds] Add `ingressHostnamePrefixes` list to `AppDefinition.v1beta10` [#57](https://github.com/eclipsesource/theia-cloud-helm/pull/57) | [#298](https://github.com/eclipsesource/theia-cloud/pull/298)
- [theia-cloud] Add `allWildcardInstances` to values and create TLS entries for them in the instances-ingress [#57](https://github.com/eclipsesource/theia-cloud-helm/pull/57)
- [theia-cloud] Add `hosts.paths.tlsSecretName` to values which allows to optionally set the tls secretName on the ingress tls section when using paths [#57](https://github.com/eclipsesource/theia-cloud-helm/pull/57)
- [theia-cloud] Add `ingress.certManagerAnnotations` to values which allows to configure whether cert manager annotations will be added to the ingresses [#57](https://github.com/eclipsesource/theia-cloud-helm/pull/57)

### Breaking Changes in 0.11.0

In preparation for a first major release we will introduce some breaking changes in order to make the helm chart configuration easier to understand.

- [theia-cloud] move `hosts.tls` to `ingress.tls` [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] move `hosts.paths.tlsSecretName` to `ingress.addTLSSecretName` (default is set to `true` which is a change for path based installs) [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] move `hosts.paths` to `hosts.configuration` [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] remove `hosts.useServicePortInHostname` (no replacement) [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] move `hosts.servicePort` to `service.port` [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] move `hosts.serviceProtocol` to `service.protocol` [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] removed `hosts.service` (now `hosts.configuration.service` + `hosts.configuration.baseHost`) [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] removed `hosts.landing` (now `hosts.configuration.landing` + `hosts.configuration.baseHost`) [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] removed `hosts.instance` (now `hosts.configuration.instance` + `hosts.configuration.baseHost`) [#59](https://github.com/eclipsesource/theia-cloud-helm/pull/59)
- [theia-cloud] move `app.logo`, `app.logoData`, and `app.logoFileExtension` to `landingPage.logo`, `landingPage.logoData`, and `landingPage.logoFileExtension` [#63](https://github.com/eclipsesource/theia-cloud-helm/pull/63)

## [0.10.0] - 2024-04-02

- [theia-cloud-crds] Provide conversion webhook for newer versions of CRDs [#49](https://github.com/eclipsesource/theia-cloud-helm/pull/49) | [#283](https://github.com/eclipsesource/theia-cloud/pull/283) - contributed on behalf of STMicroelectronics
  - This webhook is called, whenever a resource is requested in a specific version
  - This is enabled from these versions: `AppDefintion.v1beta8`, `Session.v1beta6` and `Workspace.v1beta3`
  - Older versions are deprecated and no longer in the definition
- [theia-cloud-crds] Move status like fields to status [#](https://github.com/eclipsesource/theia-cloud-helm/pull/49) | [#283](https://github.com/eclipsesource/theia-cloud/pull/283) - contributed on behalf of STMicroelectronics
  - `Session.v1beta7`: Move `url`, `lastActivity` and `error` fields from the spec to the status.
  - `Workspace.v1beta4`: Move the `error` field from the spec to the status. Also add the `error` field to `Workspace.v1beta3` as it was missing
- [theia-cloud-crds] Remove `timeout.strategy` from AppDefinition [#](https://github.com/eclipsesource/theia-cloud-helm/pull/49) | [#283](https://github.com/eclipsesource/theia-cloud/pull/283) - contributed on behalf of STMicroelectronics
  - `AppDefinition.v1beta9`: Removed `timeout.strategy` and `timeout.limit` is now just `timeout`. This was done, as there is only one Strategy left.
- [theia-cloud-crds] Provide shortnames for AppDefinition (appdef, ad) and Workspaces (ws) [#52](https://github.com/eclipsesource/theia-cloud-helm/pull/52) | [#289](https://github.com/eclipsesource/theia-cloud/pull/289) - contributed on behalf of STMicroelectronics
- [theia-cloud] Make demo application optional (`demoApplication.install`) and group relevant fields together [#52](https://github.com/eclipsesource/theia-cloud-helm/pull/52) | [#289](https://github.com/eclipsesource/theia-cloud/pull/289) - contributed on behalf of STMicroelectronics
  - `image` -> `demoApplication`
  - `monitor.port` -> `demoApplication.monitor.port`
  - `monitor.activityTracker.timeoutAfter` -> `demoApplication.monitor.activityTracker.timeoutAfter`
  - `monitor.activityTracker.notifyAfter` -> `demoApplication.monitor.activityTracker.notifyAfter`

## [0.9.0] - 2024-01-23

- [All charts] Align [versioning](https://github.com/eclipsesource/theia-cloud-helm#versioning) between all components and introduce changelog [#45](https://github.com/eclipsesource/theia-cloud-helm/pull/45) | [#258](https://github.com/eclipsesource/theia-cloud/pull/258) - contributed on behalf of STMicroelectronics
- [All charts] Change CRD versions from `vXbeta` to `v1betaX` and only keep latest two versions [#46](https://github.com/eclipsesource/theia-cloud-helm/pull/46) | [#266](https://github.com/eclipsesource/theia-cloud/pull/266) - contributed on behalf of STMicroelectronics

## [0.8.1] - 2023-10-01

- Last Milestone based version. No changelog available due to alpha-phase.
