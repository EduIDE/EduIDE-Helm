# eduide

![Version: 2.9.0](https://img.shields.io/badge/Version-2.9.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.5.0](https://img.shields.io/badge/AppVersion-1.5.0-informational?style=flat-square)

EduIDE tenant release: operator, REST service, landing page and routes for one
environment. Requires eduide-cluster to be installed on the cluster first.

*This chart was tested with Helm version v3.17.0.*
*Other versions may work as well, but if you encounter any issues, we recommend trying with the tested version to rule out version-specific problems.*

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| oci://ghcr.io/eduide/charts | eduide-shared-cache | 0.5.3 |
| oci://ghcr.io/eduide/charts | theia-workspace-garbage-collector | 0.2.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| app | object | (see details below) | General information about the deployed app |
| app.id | Deprecated | `"asdfghjkl"` | The app id which is used in the communication between website and REST-API as a spam migitation. This id is public. Please choose an random generated string. Use service.authToken instead. |
| app.name | string | `"Theia Blueprint"` | The name of the application that may be displayed e.g. on the landing pages |
| appDefinitions | object | (see details below) | The IDE applications this installation offers.  One merged list is the single source of truth for three things that used to be configured separately and drifted apart: the AppDefinition custom resources, the app list the landing page shows, and the set of images preloaded onto every node. Offering a language is one entry here, not three edits in two repositories.  The definitions are `catalog` plus `apps`; `enabled` picks which of them this installation offers, and empty means all of them. Each app is `defaults`, then its `catalog` entry, then its `apps` entry, the later one winning field by field.  Each key is the AppDefinition name. `image` is a repository without a tag - the tag comes from versions.ide (or the chart's appVersion), so a release moves every IDE image at once. A full reference with a tag or digest is used as given, which is how an installation runs an image from its own registry. An entry with a `landingPage` key is offered in the landing page drop-down; one without is deployable but hidden. |
| appDefinitions.apps | object | `{}` | This installation's own apps, and overrides of catalog entries. A key matching a catalog entry is merged over it, so `java-17: {minInstances: 10}` changes one field. `<name>: null` removes an app. Like catalog entries, these render only if `enabled` names them or `enabled` is empty.  An app the catalog does not have, from your own registry:      apps:       haskell:         image: registry.example.edu/ide/haskell:2.1.0         limitsMemory: 4000M         landingPage:           label: Haskell           # A file name from the landing page's public/assets/logos/, or           # a path starting with "/". Unset, the page derives one from           # the label (haskell-logo.png), which it does not ship.           image: theia-logo.png |
| appDefinitions.catalog | object | (see values.yaml) | The IDE images EduIDE officially releases. An image only one installation uses (TH Mannheim's thm-java-25) belongs in that installation's `apps`, not here. Owned by the chart: change an entry for one installation through `apps`. An installation that lists `enabled` gets a new catalog entry only once it names it there. |
| appDefinitions.defaults | object | `{"downlinkLimit":30000,"imagePullPolicy":"IfNotPresent","limitsCpu":"2","limitsMemory":"2400M","maxInstances":1000,"minInstances":0,"monitor":{"port":8081},"mountPath":"/home/project","options":{"dataBridgeEnabled":"true","dataBridgePort":"16281"},"port":3000,"requestsCpu":"200m","requestsMemory":"500M","timeout":1440,"uid":101,"uplinkLimit":30000}` | Applied to every app that does not state its own. Only the four scaling and sizing values genuinely differ between languages. |
| appDefinitions.enabled | list | `[]` | The apps this installation offers, by name from `catalog` or `apps`. Empty offers every definition. A name with neither is skipped, and `helm install`/`helm upgrade` print a warning naming it. |
| demoApplication | object | (see details below) | Information about the demo application to be installed |
| demoApplication.imagePullPolicy | string | `nil` | Optional: Override the imagePullPolicy for the main application's docker image. If this is omitted or empty, the root at .Values.imagePullPolicy is used. |
| demoApplication.install | bool | `true` | Should the demo application be installed |
| demoApplication.monitor | object | (see details below) | Values that are used by the monitor |
| demoApplication.monitor.activityTracker | object | (see details below) | Values that are used by the activityTracker module |
| demoApplication.monitor.activityTracker.notifyAfter | int | `25` | Minutes of inactivity that lead to a warning displayed to the user Make greater than timeoutAfter to disable |
| demoApplication.monitor.activityTracker.timeoutAfter | int | `30` | Minutes of inactivity that lead to pod shutdown |
| demoApplication.monitor.port | int | `3000` | At which port the monitor extension is available For the Theia extension take the same as the application port For the VSCode extension take 8081 (default) or the port specified via the THEIACLOUD_MONITOR_PORT env variable |
| demoApplication.name | string | `"theiacloud/theia-cloud-demo:1.2.0-next"` | The name of docker image to be used |
| demoApplication.pullSecret | string | `""` | the image pull secret. Leave empty if registry is public |
| demoApplication.timeout | string | `"30"` | Limit in minutes |
| eduide-shared-cache | object | `{"enabled":false}` | The Gradle build cache and Maven proxy. Optional: nothing reaches it unless operator.enableBuildCaching or operator.enableDependencyCaching is also turned on, so enabling this alone deploys a cache with no clients. |
| gateway | object | `{"className":"envoy","create":false,"enabled":true,"httpEnabled":false,"httpPort":80,"httpsPort":443,"instancesRouteName":"theia-cloud-demo-ws-route","instancesWildcardSecretNames":{},"name":"theia-cloud-gateway","parentRefs":[],"routes":{"enabled":true},"serviceRouteRequestTimeout":"60s","tls":true}` | Gateway API configuration (Envoy Gateway by default) |
| gateway.className | string | `"envoy"` | GatewayClassName to use (Envoy Gateway default is typically "envoy") |
| gateway.create | bool | `false` | Create a Gateway in this namespace.  Leave this false. The supported model is one shared Gateway per cluster, installed by the eduide-cluster chart, which every environment attaches to through `gateway.parentRefs` below. That is what every real installation uses and the only path that is tested.  Setting this true renders a Gateway whose HTTPS listeners reference the Secrets `ws-cert-secret`, `service-cert-secret` and `landing-page-cert-secret` - which NEITHER CHART CREATES. You would have to create all three yourself. The listeners sit at Programmed=False until you do, and nothing in `helm status` explains why. |
| gateway.enabled | bool | `true` | Master switch for Gateway API resources. |
| gateway.httpEnabled | bool | `false` | Whether to create an HTTP listener on port 80 (useful for plain HTTP or external redirects) |
| gateway.httpsPort | int | `443` | HTTPS listener port |
| gateway.instancesRouteName | string | `"theia-cloud-demo-ws-route"` | Name of the HTTPRoute that is updated to publish new Theia application instances |
| gateway.instancesWildcardSecretNames | object | `{}` | Additional wildcard hostnames and optional dedicated TLS secret names Only accepts wildcard hostnames that are configured in `hosts.allWildcardInstances`. |
| gateway.name | string | `"theia-cloud-gateway"` | Name of the Gateway resource |
| gateway.parentRefs | list | `[]` | Optional explicit parentRefs for HTTPRoutes. If empty, routes attach to `gateway.name` in the same namespace.  Example for a centralized shared gateway: parentRefs:   - name: theia-shared-gateway     namespace: eduide-system |
| gateway.routes.enabled | bool | `true` | Whether to render HTTPRoute resources. |
| gateway.serviceRouteRequestTimeout | string | `"60s"` | HTTPRoute request timeout for service-route (Envoy default can be 15s) |
| gateway.tls | bool | `true` | Does Theia Cloud expect TLS connections (true) or is TLS terminated outside of Theia Cloud (false) |
| global.nodeSelector | object | `{}` | Node labels every EduIDE pod must match, e.g. `aet.cit.tum.de/pool: pve`. Sessions, the operator, the REST service, the landing page, image preloading and (from its next chart version) the workspace garbage collector land on matching nodes only. A plain node selector, so the nodes need no taint. Empty schedules anywhere, as before. Sessions follow only with an operator that accepts `--sessionNodeSelector`. The conversion webhook is in the separate eduide-cluster release, which needs the same value passed to it. |
| hosts | object | (see details below) | You may adjust the hostname below. |
| hosts.allWildcardInstances | list | `["*.webview."]` | Hostname prefixes that session webviews are served from, relative to the instance host. Sessions render previews, notebooks and embedded docs on these, so with an empty list webviews 404 - the session itself still starts, so this is discovered by a user rather than by the installer.  Every AppDefinition already defaults to the matching `ingressHostnamePrefixes: ["*.webview."]`, so this default makes the two agree. It has two consequences you must plan for:    DNS   `*.webview.instance.<host>` must resolve.   TLS   you need a WILDCARD certificate for it. ACME cannot issue a wildcard         over HTTP-01, so either configure a DNS-01 solver         (`gatewayAcmeIssuer.solvers` in the eduide-cluster chart) or obtain         the certificate separately and supply it as a Secret.  Set to [] only if you genuinely do not want webviews. |
| hosts.configuration | object | (see details below) | Configuration for the hostnames. Contains the baseHost and afixes for all services |
| hosts.configuration.baseHost | string | `"192.168.39.173.nip.io"` | baseHost configures the host for all services. Service names are prepended as subdomains, e.g. service.<landing>.<baseHost> |
| hosts.configuration.instance | string | `"instances"` | afix for deployed instances |
| hosts.configuration.landing | string | `"trynow"` | afix of the landing page |
| hosts.configuration.service | string | `"servicex"` | afix of the REST service |
| imagePullPolicy | string | `"Always"` | The default imagePullPolicy for containers of theia cloud. Can be overridden for individual components by specifying the imagePullPolicy variable there. Possible values: - Always - IfNotPresent - Never |
| imageRegistry | string | `"ghcr.io/eduide"` | The container registry every EduIDE image is pulled from. |
| keycloak | object | (see details below) | Values related to Keycloak |
| keycloak.adminGroup | string | `"theia-cloud/admin"` | The name of the Keycloak group identifying admin users who are allowed to access the service's admin endpoints. |
| keycloak.allowUnauthenticated | bool | `false` | Install even though the Keycloak values below are still the chart's placeholders. The oauth2-proxy ConfigMaps render regardless of `enable` (the operator mounts them into every session by literal name), so leaving the placeholders means a proxy pointed at a host that does not exist and sessions that fail rather than run unauthenticated. Only set this for an installation that is deliberately not exposed yet. |
| keycloak.authUrl | string | `"https://keycloak.url/auth/"` | Key cloak auth URL. Only has to be specified when enable: true |
| keycloak.clientId | string | `"theia-cloud"` | The client-id. Only has to be specified when enable: true |
| keycloak.clientSecret | string | `"publicbutoauth2proxywantsasecret"` | The oaid client secret. In case you configure your keycloak client as confidential, then you may specifiy the secret here. If you stick with our default public client, you may leave below value. For public clients keycloak does not generate a client-secret, but in order to make oath2-proxy happy, we will pass a value |
| keycloak.cookieSecret | string | `""` | The cookie secret. This must be unique per environment and must not be public. The chart ships no default on purpose: like `service.adminApiToken`, every environment supplies its own and the template fails to render if this is left empty. Generate one with `openssl rand -base64 32 \| tr -- '+/' '-_'`. See https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/overview/#generating-a-cookie-secret for details. |
| keycloak.enable | bool | `false` | Whether keycloak authentication shall be used |
| keycloak.realm | string | `"TheiaCloud"` | The Keycloak Realm. Only has to be specified when enable: true |
| landingPage | object | (see details below) | Values related to the landing page |
| landingPage.additionalApps | string | `nil` | The page may show these additional apps in a drop down. This is a map. The key maps to the app definition name The value contains the label shown in the UI and may optionally contain an image override that is forwarded to the landing page config.  Example: different-app-definition:   label: "Different App Definition"   image: "different-app-definition"   visible: false further-app-definition:   label: "Further App Definition" |
| landingPage.appDefinition | string | `"java-17-templates"` | the app id to launch |
| landingPage.disableInfo | bool | `false` | Should showing info title and text below the launch button be disabled true hides the info title and text false shows the info title and text |
| landingPage.enabled | bool | `true` | Whether the landing page shall be enabled |
| landingPage.ephemeralStorage | bool | `true` | If set to true no persisted storage is used when creating sessions on the landing page. Set to false if you want to use persisted storage. |
| landingPage.footerLinks | string | (see details below) | Optional: Customize footer links on the landing page All footer link configurations are optional. If not provided, default values will be used. |
| landingPage.image | string | `"{{ .Values.imageRegistry }}/eduide-landing-page:{{ .Values.versions.landingPage }}"` | the landing page image to use. Templated, so the tag follows versions.landingPage unless the whole string is overridden. |
| landingPage.imagePullPolicy | string | `nil` | Optional: Override the imagePullPolicy for the landing page's docker image. If this is omitted or empty, the root at .Values.imagePullPolicy is used. |
| landingPage.imagePullSecret | string | `nil` | Optional: the image pull secret |
| landingPage.infoText | string | `nil` | Optional: If specified with a value, this overrides the info text shown on the landing page. Empty values are ignored. Use `disableInfo` to deactivate showing the info completely. |
| landingPage.infoTitle | string | `nil` | Optional: If specified with a value, this overrides the title of the info text shown on the landing page. Empty values are ignored. Use `disableInfo` to deactivate showing the info completely. |
| landingPage.loadingText | string | `nil` | Optional: If specified with a value, this overrides the message shown to the user while the session is started. Empty values are ignored and the default text is used. |
| landingPage.logo | string | `"logos/theiablueprint.svg"` | The logo of the application that should be displayed on the landing pages |
| landingPage.logoData | string | `nil` | set landingPage.logoData=$(cat path/to/file.svg | base64 -w 0 -) Another way is to directly add the base64 string to the values file. |
| landingPage.logoFileExtension | string | `"svg"` | The file extension of the logo. Must be set to match the logo respectively the logoData. This is required because browsers cannot show a binary image (e.g. png) with a svg ending and vice-versa. |
| landingPage.privacy | object | (see details below) | What the privacy page states about this installation. Only the research clause lives here. The retention and session figures the page shows are DERIVED in the landing page config map from the settings that actually produce them - `theia-workspace-garbage-collector.env.WORKSPACE_TTL`, `landingPage.ephemeralStorage` and `appDefinitions.defaults.timeout` - so changing a retention period cannot leave the privacy statement claiming something untrue. Do not restate those numbers here. |
| landingPage.privacy.controller | object | (see details below) | Who is accountable for the data, named on the privacy page. The defaults are deliberately obvious placeholders. Whoever deploys this is the controller, and a privacy statement naming somebody else's university is worse than one that visibly has not been filled in. |
| landingPage.privacy.controller.address | string | `""` | Postal address of that person, e.g. "1 Example Street, 00000 Example City". Optional; omitted when empty. |
| landingPage.privacy.controller.email | string | `""` | Where data protection enquiries go, e.g. "privacy@example.edu". |
| landingPage.privacy.controller.organisation | string | `""` | The legal entity responsible under the GDPR, e.g. "Example University". Empty by default on purpose: the page then says plainly that no controller has been configured, rather than presenting a placeholder as though it were this installation's real contact. |
| landingPage.privacy.controller.representative | string | `""` | The person accountable for this service, as named on the imprint, e.g. "Prof. Dr. Example Person". |
| landingPage.privacy.dataProtectionOfficer | object | (see details below) | The data protection officer, named separately from the controller because the GDPR requires a distinct contact point. Empty by default for the same reason as above. |
| landingPage.privacy.dataProtectionOfficer.email | string | `""` | Where the data protection officer is reached, e.g. "dpo@example.edu". |
| landingPage.privacy.dataProtectionOfficer.name | string | `""` | Optional name. Most institutions publish only the address. |
| landingPage.privacy.scientificUse | bool | `false` | State that anonymised usage data may also be used for scientific research. Leave off unless this installation has a legal basis for it: this is a processing purpose, not a cosmetic string. |
| landingPage.replicas | int | `1` | Number of landing page pods. More than one keeps the landing page up when a node goes away, and turns on its PodDisruptionBudget. |
| landingPage.sentry | object | (see details below) | Values related to Sentry on the landing page. |
| landingPage.sentry.dsn | string | `""` | The Sentry endpoint the landing page reports to. The landing page has no built-in default. |
| landingPage.sentry.enable | bool | `false` | Turn on Sentry browser monitoring on the landing page. Off by default, and it stays off until landingPage.sentry.dsn is set too. |
| landingPage.trustedArtemisHosts | list | `[]` | Hostnames trusted to start a session from a link. A link with `artemisToken` only starts a session on its own when the host in both `gitUri` and `artemisUrl` is on this list. Otherwise the student has to click Launch. |
| maintenancePage | object | (see details below) | Static page shown instead of Envoy's raw error when the landing page is down |
| maintenancePage.enabled | bool | `true` | Answer 502/503/504 on the landing route with files/maintenance.html ("EduIDE is currently unavailable") instead of Envoy's plain-text error. Covers the landing page only - the REST service and sessions keep their own errors. Needs Envoy Gateway (BackendTrafficPolicy responseOverride). |
| monitor | object | (see details below) | Values to influence the monitor initialization on the operator |
| monitor.activityTracker | object | (see details below) | Values to influence the activityTracker module |
| monitor.activityTracker.enable | bool | `true` | Should the activityTracker module be enabled |
| monitor.activityTracker.interval | int | `1` | Minutes between re-pinging the pods |
| monitor.enable | bool | `true` | Should the monitor be enabled |
| monitoring | object | `{"enabled":true}` | Whether this installation is scraped by Prometheus and appears on the dashboards.  The PodMonitor objects themselves are in `eduide-cluster`, not here. They have to be created in Rancher's own namespace to be discovered, and one PodMonitor per tenant writing into a shared namespace would collide on names. So the cluster chart owns the objects and this flag decides whether this release's namespace is in the list they watch - `bootstrap-cluster.yml` reads it when it derives that list.  Turning it off means this environment stops being scraped. Nothing else about the release changes; `monitor.enable` below is a different thing entirely (the operator's own session activity tracker). |
| networkPolicies | object | (see details below) | NetworkPolicies that isolate session pods. Session pods run untrusted user code. By default they reach cluster DNS and the internet, but not private ranges or the cloud metadata endpoint, and receive traffic only from the gateway/proxy and the operator. Set `allowExternalEgress: false` for DNS only. Operator, service and landing-page pods are left untouched. |
| networkPolicies.allowExternalEgress | bool | `true` | Allow sessions general outbound internet access (the metadata endpoint below stays blocked either way). Set false to lock sessions down to DNS only - this breaks in-session git clone and package downloads. |
| networkPolicies.dataBridgePort | int | `16281` | Data bridge port on the session pod. The operator connects to this port to inject each session's environment (Artemis token, GIT_URI, git identity) into prewarmed/eager sessions. The default-deny would otherwise drop it, so the session would start with no credentials (no autoclone, no Artemis sign-in). Must match `appDefinitions.*.options.dataBridgePort`. |
| networkPolicies.dnsNamespace | string | `"kube-system"` | Namespace of the cluster DNS resolver. Session pods may send DNS to it. |
| networkPolicies.enabled | bool | `true` | Master switch. Secure by default. |
| networkPolicies.gatewayNamespace | string | `"envoy-gateway-system"` | Namespace that runs the gateway/proxy data plane (Envoy Gateway by default). Session pods accept ingress only from pods in this namespace. Matched through the automatic `kubernetes.io/metadata.name` namespace label. |
| networkPolicies.metadataCidr | string | `"169.254.169.254/32"` | Cloud metadata endpoint. Always excluded from session egress so a compromised session cannot read instance credentials. |
| networkPolicies.monitorPort | int | `8081` | Port the operator polls on each session for activity. Must match `appDefinitions.defaults.monitor.port`. |
| networkPolicies.privateEgressCidrs | list | `["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","100.64.0.0/10"]` | Ranges excluded from general outbound access, so a session cannot reach the pods and services of the cluster. Add the cluster's pod and service CIDRs here when they are outside these private ranges. A host in one of these ranges that sessions must reach, such as a private Artemis, needs its range removed. |
| networkPolicies.sessionPorts | list | `[3000,5000]` | Ports on the session pod the gateway/proxy is allowed to reach. Covers the IDE port and the oauth2-proxy sidecar port. |
| oauth2Proxy | object | `{"cookieDomains":[],"cookieSecure":true,"sslInsecureSkipVerify":false,"whitelistDomains":[]}` | Values related to OAuth2 Proxy configuration |
| oauth2Proxy.cookieSecure | bool | `true` | Whether the session cookie is sent over HTTPS only (sets cookie_secure). Set to false only for an install served over plain HTTP (`gateway.httpEnabled`), where the browser would otherwise drop the cookie and login cannot finish. The cookie then travels in clear text. |
| oauth2Proxy.sslInsecureSkipVerify | bool | `false` | Whether OAuth2 Proxy skips TLS certificate verification of the OIDC provider (sets ssl_insecure_skip_verify). Defaults to false to enforce certificate validation. Set to true only when the provider uses a self-signed or otherwise untrusted certificate. |
| operator | object | (see details below) | Values related to the operator |
| operator.allowCustomEnvFromMap | bool | `true` | Whether a launch request may set arbitrary environment variables via `env.fromMap`. Reserved platform variables are always stripped by the operator regardless of this flag. (`--allowCustomEnvFromMap`.) |
| operator.allowedEnvFromConfigMaps | list | `[]` | Allowlist of ConfigMap names a launch request may inject into a session via `env.fromConfigMaps`. Empty (the default) denies all injection. Enforced by the operator (`--allowedEnvFromConfigMaps`). |
| operator.allowedEnvFromSecrets | list | `[]` | Allowlist of Secret names a launch request may inject into a session via `env.fromSecrets`. Empty (the default) denies all injection - a session receives only the platform environment. Add the specific Secret names an environment legitimately needs. Enforced by the operator (`--allowedEnvFromSecrets`, EduIDE-Cloud #144). |
| operator.bandwidthLimiter | string | `"K8SANNOTATION"` | Whether Theia Cloud shall limit network speed. This might not be fully supported on all cloud provider/in all clusters. Possible values: - K8SANNOTATION                   Set via kubernetes annotations (kubernetes.io/egress-bandwidth and kubernetes.io/ingress-bandwidth) - WONDERSHAPER                    Set via wondershaper init container - K8SANNOTATIONANDWONDERSHAPER    Set Kubernetes annotations and use wondershaper init container |
| operator.buildCache | object | `{"bazelUrl":"","enablePush":false,"enabled":false,"gradleUrl":""}` | Build cache configuration |
| operator.buildCache.bazelUrl | string | `""` | The URL of the remote Bazel build cache server. |
| operator.buildCache.enablePush | bool | `false` | Whether sessions are allowed to push to the build cache. |
| operator.buildCache.enabled | bool | `false` | Whether to enable build caching |
| operator.buildCache.gradleUrl | string | `""` | The URL of the remote Gradle build cache server. |
| operator.cloudProvider | string | `"K8S"` | Select your cloud provider. Possible values: - K8S      Plain Kubernetes - MINIKUBE Local deployment on Minikube |
| operator.clusterWideRbac | bool | `false` | Grant the operator's *namespaced* permissions (Sessions, Workspaces, Deployments, Pods, ConfigMaps, Services, ...) cluster-wide instead of only in its own namespace. The default (false) binds the shared "operator-api-access" ClusterRole through a namespaced RoleBinding, so those broad verbs apply only in the release namespace. Set true only for setups that genuinely reach across namespaces; this renders a ClusterRoleBinding. This flag does NOT affect the cluster-scoped resources the operator always needs (read-only CustomResourceDefinitions and PersistentVolumes, plus write access to PersistentVolumes when cloudProvider is MINIKUBE): those are granted via a separate minimal ClusterRole regardless of this setting, because a RoleBinding cannot grant access to cluster-scoped resources. |
| operator.continueOnException | bool | `false` | Whether the operator should stop in cases where an exception is not handled |
| operator.dependencyCache | object | `{"enabled":false,"url":""}` | Dependency cache configuration (Reposilite) |
| operator.dependencyCache.enabled | bool | `false` | Whether to enable the dependency cache |
| operator.dependencyCache.url | string | `""` | The URL of the dependency cache server. |
| operator.eagerStart | bool | `false` | Whether theia applications shall be started eager. This means that the application is already running without a user. When a user requests a new session, one of the already launched ones is assigned.  Currently only false is fully supported. |
| operator.image | string | `"{{ .Values.imageRegistry }}/eduide-cloud/operator:{{ .Values.versions.cloud }}"` | The operator image. Templated, so the tag follows versions.cloud unless the whole string is overridden. |
| operator.imagePullPolicy | string | `nil` | Optional: Override the imagePullPolicy for the operator's docker image. If this is omitted or empty, the root at .Values.imagePullPolicy is used. |
| operator.imagePullSecret | string | `nil` | Optional: the image pull secret |
| operator.leaderElection | object | (see details below) | Options to influence the operator's leader election |
| operator.logging | object | (see details below) | Allows to override the operator's log4j configuration |
| operator.maxWatchIdleTime | string | `"3600000"` | Configures the timeout in milliseconds when a watcher for either AppDefinitions, Workspaces, or Sessions is assumed to be not working. When this is detected the operator instance will stop and a new operator will set up fresh watchers. |
| operator.metricsPort | int | `0` | Port on which the operator serves Prometheus metrics at /metrics, such as theiacloud_sessions_ended_total by reason (inactivity, lifetime). The eduide-cluster chart's PodMonitor scrapes it. 0 serves nothing. Needs an operator image that knows --metricsPort; older ones fail to start with it. |
| operator.oAuth2ProxyVersion | string | `"v7.12.0"` | The version to use of the quay.io/oauth2-proxy/oauth2-proxy image |
| operator.replicas | int | `1` | Number of operator instances to create |
| operator.requestedStorage | string | `"250Mi"` | The amount of requested storage for each persistent volume claim (PVC) for workspaces. This is directly passed to created PVCs and must be a valid Kubernetes quantity. See https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/ |
| operator.sentry | object | (see details below) | Values related to Sentry on the operator. |
| operator.sentry.enable | bool | `false` | Set SENTRY_ENABLE=true in the operator deployment. Off by default: the DSN is compiled into the published images and points at TUM's Sentry, so enabling this outside TUM sends your hostnames and namespace names there. |
| operator.sessionsPerUser | string | `"1"` | Set the number of active sessions a single user can launch |
| operator.storageClassName | string | `"default"` | The name of the storage class for persistent volume claims for workspaces. This storage class must be present on the cluster. Most cloud providers offer a default storage class without additional configuration. |
| operator.wondershaperImage | string | `"theiacloud/theia-cloud-wondershaper:1.2.0-next"` | If bandwidthLimiter is set to WONDERSHAPER or K8SANNOTATIONANDWONDERSHAPER this image will be used for the wondershaper init container |
| operatorrole.name | string | `"operator-api-access"` |  |
| podDisruptionBudget | object | (see details below) | PodDisruptionBudgets for the landing page and REST service |
| podDisruptionBudget.enabled | bool | `true` | Render a PodDisruptionBudget (minAvailable: 1) for every Deployment above that runs more than one replica. Turn this off on single-node clusters: there a drain can never reschedule the evicted replica, so it waits on the last one forever. |
| poolScaler | object | (see details below) | The pool scaler: decides how many free prewarmed pods each AppDefinition keeps, by patching `spec.targetIdle`. See the EduIDE-pool-scaler README. |
| poolScaler.calendar | list | `[]` | Events for the static calendar provider, rendered into a ConfigMap and re-read by the scaler every round. Each needs `appDefinition`, `kind` (`exam`, `release`, `due`), `time` (RFC3339) and `participants`. |
| poolScaler.config | object | `{}` | The scaler configuration file, as in EduIDE-pool-scaler's examples/config.yaml. `namespace`, `mode` and `metricsAddr` are set by the chart. `budget.nodeSelector` defaults to `global.nodeSelector`, the nodes session pods run on.    config:     timezone: Europe/Berlin     strategies: [reactive, predictive]     prometheus:       url: http://prometheus-operated.cattle-monitoring-system:9090     appLimits:       java-17: {floor: 2, ceiling: 80} |
| poolScaler.enabled | bool | `false` | Deploy the pool scaler. One replica, `Recreate`, no leader election. |
| poolScaler.image | string | `"{{ .Values.imageRegistry }}/eduide-pool-scaler:{{ .Values.versions.poolScaler }}"` | The pool scaler image. Templated, so the tag follows versions.poolScaler unless the whole string is overridden. |
| poolScaler.imagePullPolicy | string | `nil` | Optional: override the root imagePullPolicy. |
| poolScaler.mode | string | `"shadow"` | `shadow` computes and exports every decision but patches nothing; `active` patches `spec.targetIdle`. Start in shadow. |
| poolScaler.monitoring.dashboardNamespace | string | `"cattle-dashboards"` | Namespace of the dashboard ConfigMap, watched by Grafana's sidecar. |
| poolScaler.monitoring.decisionStaleSeconds | int | `600` | Decision round older than this, in seconds, fires PoolScalerDecisionStale. |
| poolScaler.monitoring.enabled | bool | `false` | Create them. Needs the Prometheus Operator CRDs. |
| poolScaler.monitoring.namespace | string | `"cattle-monitoring-system"` | Namespace of the PodMonitor and the PrometheusRule. Must be one your Prometheus discovers; also the `namespace` label the alerts carry for routing, as in eduide-cluster's `monitoring.alerting.namespace`. |
| poolScaler.resources | object | `{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | Resources of the scaler container. |
| poolScaler.secret.artemisToken | string | `""` | Artemis pre-shared token. Only read when `create` is true. Comes from a deployment secret, never from a file in git. |
| poolScaler.secret.create | bool | `false` | Have the chart create the Secret from the two tokens below. Off means it already exists, or no token is needed. |
| poolScaler.secret.decisionModelToken | string | `""` | Decision model bearer token. Only read when `create` is true. |
| poolScaler.secret.name | string | `"pool-scaler-tokens"` | Name of the Secret. |
| preloading | object | (see details below) | Values to configure preloading of images on Kubernetes nodes. |
| preloading.deriveFromApps | bool | `true` | Set to false to preload only preloading.images and nothing derived. |
| preloading.enable | bool | `true` | Is image preloading enabled. |
| preloading.imagePullPolicy | string | `nil` | Optional: Override the imagePullPolicy for the image preloading containers. If this is omitted or empty, the root at .Values.imagePullPolicy is used. |
| preloading.images | list | `[]` | Extra images to preload, on top of the ones derived automatically.  Leave this empty. The chart preloads the image of every app it renders, every sidecar image and the landing page image without being told, so the list cannot fall out of step with what the installation actually offers. It used to be written out by hand per environment and addressed by array index, which is how production ended up offering c-templates while preloading everything except c-templates.  Each item is either an image reference string or a map: `{ image: "...", args: ["--version"] }` to use the image entrypoint (distroless-friendly), or `{ image: "...", command: [...], args: [...] }` for a full override. If only strings are used, the chart runs `/bin/sh -c 'echo …; exit 0'` (shell required in the image). |
| preloading.maxUnavailable | string | `"100%"` | How many nodes may pull at once when the image set changes, as a count or a percentage. The Kubernetes default of 1 walks the cluster one node at a time, each waiting for its whole image set, which on a large cluster means the last node starts long after the first has finished. These pods carry no traffic, so there is nothing to protect by staging the rollout. |
| preloading.nodeSelector | object | `{}` | Preload only onto nodes carrying these labels. Empty falls back to `global.nodeSelector`, and with both empty preloading runs on every node. Set this when some nodes cannot hold the images: the exited init containers keep them in use, so kubelet image GC cannot free that disk space. Sessions are not pinned by this, so one landing on another node pulls its image cold: pin both with `global.nodeSelector` instead. |
| service | object | (see details below) | Values of the Theia Cloud REST service |
| service.adminApiToken | string | `""` | Base64-encoded admin API token. Only read when adminApiTokenSecret.create is true. Comes from a deployment secret, never from a file in git. |
| service.adminApiTokenSecret | object | `{"create":false,"external":false,"key":"ADMIN_API_TOKEN","name":"service-admin-api-token"}` | The Kubernetes Secret holding the bearer token for admin API token protected endpoints. Set `create: true` and supply `adminApiToken` to have the chart manage it, or leave `create: false` and reference one you created yourself. |
| service.adminApiTokenSecret.create | bool | `false` | Have the chart create the Secret from `adminApiToken` below. |
| service.adminApiTokenSecret.external | bool | `false` | Set true if you created the Secret yourself, outside the chart. Leaving both this and `create` false means the admin API is simply not exposed - which is a valid way to run, and is the default. |
| service.authToken | string | `"asdfghjkl"` | The service authentication token used in the communication between website and REST-API for spam mitigation. This token is public. Please choose a random generated string. |
| service.image | string | `"{{ .Values.imageRegistry }}/eduide-cloud/service:{{ .Values.versions.cloud }}"` | The image to use. Templated, so the tag follows versions.cloud unless the whole string is overridden. |
| service.imagePullPolicy | string | `nil` | Optional: Override the imagePullPolicy for the service's docker image. If this is omitted or empty, the root at .Values.imagePullPolicy is used. |
| service.imagePullSecret | string | `nil` | Optional: the image pull secret |
| service.port | int | `8081` | service port (default: 8081) |
| service.protocol | string | `"https"` | protocol of the REST-API |
| service.replicas | int | `1` | Number of REST service pods. The service keeps no state of its own, so more than one is safe; it also turns on its PodDisruptionBudget. |
| service.sentry | object | (see details below) | Values related to Sentry on the service. |
| service.sentry.enable | bool | `false` | Set SENTRY_ENABLE=true in the service deployment. Off by default: the DSN is compiled into the published images and points at TUM's Sentry, so enabling this outside TUM sends your hostnames and namespace names there. |
| servicerole.name | string | `"service-api-access"` |  |
| skipPreflight | bool | `false` | Skip the check that eduide-cluster is installed on this cluster. Only useful for rendering against a cluster that intentionally lacks it. |
| theia-workspace-garbage-collector | object | `{"enabled":true,"image":{"tag":"5896ca3b55324af4b195256dd5c198fb751f5cb8"}}` | Reaps workspaces whose sessions are long gone. |
| versions | object | (see details below) | Image versions, one per source repository. Every image the chart deploys derives its tag from one of these three, so a release is three numbers rather than nineteen image strings scattered across environment values files. |
| versions.cloud | string | `"1.3.0"` | EduIDE-Cloud: the operator and the REST service. Released independently of the IDE images, so it carries its own version. 1.2.1 is the first release that accepts the env-injection allowlist flags (--allowCustomEnvFromMap and friends) this chart renders; 1.2.0 rejects them. 1.3.0 is the first release that accepts --sessionNodeSelector, which this chart renders when global.nodeSelector is set; older operators reject it. |
| versions.ide | string | `""` | The IDE images from the EduIDE repository (java-17, c, python, ...). Empty falls through to the chart's appVersion, which is what a release sets, so a plain `helm install --version 2.0.0` pins every IDE image to the tag that release published. |
| versions.landingPage | string | `"1.3.1"` | EduIDE-Landing-Page. Released independently as well. 1.2.2 is the first release whose privacy page reads the `landingPage.privacy` block below. 2.2.0 shipped that block while still pinning 1.2.1, which ignores it, so every installation kept the hardcoded text the block exists to replace. 1.3.0 listens on 8080 as non-root, which the landing page Deployment needs. 1.3.1 adds the remaining dependency security fixes. |
| versions.poolScaler | string | `"0.1.0"` | EduIDE-pool-scaler. Only used when `poolScaler.enabled` is true. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
