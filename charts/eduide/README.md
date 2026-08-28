# eduide

![Version: 2.2.0](https://img.shields.io/badge/Version-2.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.2.0](https://img.shields.io/badge/AppVersion-1.2.0-informational?style=flat-square)

EduIDE tenant release: operator, REST service, landing page and routes for one
environment. Requires eduide-cluster to be installed on the cluster first.

*This chart was tested with Helm version v3.17.0.*
*Other versions may work as well, but if you encounter any issues, we recommend trying with the tested version to rule out version-specific problems.*

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| oci://ghcr.io/eduide/charts | eduide-shared-cache | 0.5.3 |
| oci://ghcr.io/eduide/charts | theia-workspace-garbage-collector | 0.1.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| app | object | (see details below) | General information about the deployed app |
| app.id | Deprecated | `"asdfghjkl"` | The app id which is used in the communication between website and REST-API as a spam migitation. This id is public. Please choose an random generated string. Use service.authToken instead. |
| app.name | string | `"Theia Blueprint"` | The name of the application that may be displayed e.g. on the landing pages |
| appDefinitions | object | (see details below) | The IDE applications this installation offers.  This map is the single source of truth for three things that used to be configured separately and drifted apart: the AppDefinition custom resources, the app list the landing page shows, and the set of images preloaded onto every node. Adding a language is one entry here, not three edits in two repositories.  Each key is the AppDefinition name. `image` is a repository without a tag - the tag comes from versions.ide (or the chart's appVersion), so a release moves every IDE image at once. An entry with a `landingPage` key is offered in the landing page drop-down; one without is deployable but hidden. |
| appDefinitions.apps | object | `{"c-latest":{"image":"eduide/c","landingPage":{"label":"C","visible":false}},"c-templates-latest":{"image":"eduide/c-templates","landingPage":{"buildSystems":[{"id":"bazel","label":"Bazel"},{"id":"make","label":"Make"}],"label":"C"}},"java-17-latest":{"image":"eduide/java-17","landingPage":{"label":"Java 17","visible":false},"limitsMemory":"3000M","minInstances":3,"requestsCpu":"500m"},"java-17-templates-latest":{"image":"eduide/java-17-templates","landingPage":{"buildSystems":[{"id":"maven","label":"Maven"},{"id":"gradle","label":"Gradle"}],"label":"Java 17"},"limitsMemory":"3000M","requestsCpu":"500m"},"javascript-latest":{"image":"eduide/javascript","landingPage":{"label":"Javascript"}},"ocaml-latest":{"image":"eduide/ocaml","landingPage":{"label":"Ocaml"}},"python-latest":{"image":"eduide/python","landingPage":{"label":"Python"}},"rust-latest":{"image":"eduide/rust","landingPage":{"label":"Rust"}}}` | The applications. Key is the AppDefinition name. |
| appDefinitions.defaults | object | `{"downlinkLimit":30000,"imagePullPolicy":"IfNotPresent","limitsCpu":"2","limitsMemory":"2400M","maxInstances":1000,"minInstances":0,"mountPath":"/home/project","options":{"dataBridgeEnabled":"true","dataBridgePort":"16281"},"port":3000,"requestsCpu":"200m","requestsMemory":"500M","timeout":1440,"uid":101,"uplinkLimit":30000}` | Applied to every app that does not state its own. Only the four scaling and sizing values genuinely differ between languages. |
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
| keycloak.cookieSecret | string | `"OQINaROshtE9TcZkNAm5Zs2Pv3xaWytBmc5W7sPX7ws="` | The cookie secret. This should not be public! Only has to be specified when enable: true See https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/overview/#generating-a-cookie-secret for how to generate a strong cookie secret. |
| keycloak.enable | bool | `false` | Whether keycloak authentication shall be used |
| keycloak.realm | string | `"TheiaCloud"` | The Keycloak Realm. Only has to be specified when enable: true |
| landingPage | object | (see details below) | Values related to the landing page |
| landingPage.additionalApps | string | `nil` | The page may show these additional apps in a drop down. This is a map. The key maps to the app definition name The value contains the label shown in the UI and may optionally contain an image override that is forwarded to the landing page config.  Example: different-app-definition:   label: "Different App Definition"   image: "different-app-definition"   visible: false further-app-definition:   label: "Further App Definition" |
| landingPage.appDefinition | string | `"java-17-templates-latest"` | the app id to launch |
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
| landingPage.sentry | object | (see details below) | Values related to Sentry on the landing page. |
| landingPage.sentry.enable | bool | `false` | Set SENTRY_ENABLE=true in the landing page deployment. Off by default: the DSN is compiled into the published images and points at TUM's Sentry, so enabling this outside TUM sends your hostnames and namespace names there. |
| monitor | object | (see details below) | Values to influence the monitor initialization on the operator |
| monitor.activityTracker | object | (see details below) | Values to influence the activityTracker module |
| monitor.activityTracker.enable | bool | `true` | Should the activityTracker module be enabled |
| monitor.activityTracker.interval | int | `1` | Minutes between re-pinging the pods |
| monitor.enable | bool | `true` | Should the monitor be enabled |
| monitoring | object | `{"enabled":true}` | Whether this installation is scraped by Prometheus and appears on the dashboards.  The PodMonitor objects themselves are in `eduide-cluster`, not here. They have to be created in Rancher's own namespace to be discovered, and one PodMonitor per tenant writing into a shared namespace would collide on names. So the cluster chart owns the objects and this flag decides whether this release's namespace is in the list they watch - `bootstrap-cluster.yml` reads it when it derives that list.  Turning it off means this environment stops being scraped. Nothing else about the release changes; `monitor.enable` below is a different thing entirely (the operator's own session activity tracker). |
| oauth2Proxy | object | `{"cookieDomains":[],"sslInsecureSkipVerify":false,"whitelistDomains":[]}` | Values related to OAuth2 Proxy configuration |
| oauth2Proxy.sslInsecureSkipVerify | bool | `false` | Whether OAuth2 Proxy skips TLS certificate verification of the OIDC provider (sets ssl_insecure_skip_verify). Defaults to false to enforce certificate validation. Set to true only when the provider uses a self-signed or otherwise untrusted certificate. |
| operator | object | (see details below) | Values related to the operator |
| operator.bandwidthLimiter | string | `"K8SANNOTATION"` | Whether Theia Cloud shall limit network speed. This might not be fully supported on all cloud provider/in all clusters. Possible values: - K8SANNOTATION                   Set via kubernetes annotations (kubernetes.io/egress-bandwidth and kubernetes.io/ingress-bandwidth) - WONDERSHAPER                    Set via wondershaper init container - K8SANNOTATIONANDWONDERSHAPER    Set Kubernetes annotations and use wondershaper init container |
| operator.buildCache | object | `{"bazelUrl":"","enablePush":false,"enabled":false,"gradleUrl":""}` | Build cache configuration |
| operator.buildCache.bazelUrl | string | `""` | The URL of the remote Bazel build cache server. |
| operator.buildCache.enablePush | bool | `false` | Whether sessions are allowed to push to the build cache. |
| operator.buildCache.enabled | bool | `false` | Whether to enable build caching |
| operator.buildCache.gradleUrl | string | `""` | The URL of the remote Gradle build cache server. |
| operator.cloudProvider | string | `"K8S"` | Select your cloud provider. Possible values: - K8S      Plain Kubernetes - MINIKUBE Local deployment on Minikube |
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
| operator.oAuth2ProxyVersion | string | `"v7.12.0"` | The version to use of the quay.io/oauth2-proxy/oauth2-proxy image |
| operator.replicas | int | `1` | Number of operator instances to create |
| operator.requestedStorage | string | `"250Mi"` | The amount of requested storage for each persistent volume claim (PVC) for workspaces. This is directly passed to created PVCs and must be a valid Kubernetes quantity. See https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/ |
| operator.sentry | object | (see details below) | Values related to Sentry on the operator. |
| operator.sentry.enable | bool | `false` | Set SENTRY_ENABLE=true in the operator deployment. Off by default: the DSN is compiled into the published images and points at TUM's Sentry, so enabling this outside TUM sends your hostnames and namespace names there. |
| operator.sessionsPerUser | string | `"1"` | Set the number of active sessions a single user can launch |
| operator.storageClassName | string | `"default"` | The name of the storage class for persistent volume claims for workspaces. This storage class must be present on the cluster. Most cloud providers offer a default storage class without additional configuration. |
| operator.wondershaperImage | string | `"theiacloud/theia-cloud-wondershaper:1.2.0-next"` | If bandwidthLimiter is set to WONDERSHAPER or K8SANNOTATIONANDWONDERSHAPER this image will be used for the wondershaper init container |
| operatorrole.name | string | `"operator-api-access"` |  |
| preloading | object | (see details below) | Values to configure preloading of images on Kubernetes nodes. |
| preloading.deriveFromApps | bool | `true` | Set to false to preload only preloading.images and nothing derived. |
| preloading.enable | bool | `true` | Is image preloading enabled. |
| preloading.imagePullPolicy | string | `nil` | Optional: Override the imagePullPolicy for the image preloading containers. If this is omitted or empty, the root at .Values.imagePullPolicy is used. |
| preloading.images | list | `[]` | Extra images to preload, on top of the ones derived automatically.  Leave this empty. The chart preloads every appDefinitions.apps image, every sidecar image and the landing page image without being told, so the list cannot fall out of step with what the installation actually offers. It used to be written out by hand per environment and addressed by array index, which is how production ended up offering c-templates while preloading everything except c-templates.  Each item is either an image reference string or a map: `{ image: "...", args: ["--version"] }` to use the image entrypoint (distroless-friendly), or `{ image: "...", command: [...], args: [...] }` for a full override. If only strings are used, the chart runs `/bin/sh -c 'echo …; exit 0'` (shell required in the image). |
| preloading.resources | object | `{"limits":{"cpu":"10m","memory":"32Mi"},"requests":{"cpu":"1m","memory":"8Mi"}}` | Requests and limits for each preload container. There is one per image on every node, and they only sleep, so keep this small. Nine images at these values is 9m CPU and 72Mi per node. |
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
| service.sentry | object | (see details below) | Values related to Sentry on the service. |
| service.sentry.enable | bool | `false` | Set SENTRY_ENABLE=true in the service deployment. Off by default: the DSN is compiled into the published images and points at TUM's Sentry, so enabling this outside TUM sends your hostnames and namespace names there. |
| servicerole.name | string | `"service-api-access"` |  |
| skipPreflight | bool | `false` | Skip the check that eduide-cluster is installed on this cluster. Only useful for rendering against a cluster that intentionally lacks it. |
| theia-workspace-garbage-collector | object | `{"enabled":true,"image":{"tag":"599557839e5c5893eb0c20785dac671ae70f7e8a"}}` | Reaps workspaces whose sessions are long gone. |
| versions | object | (see details below) | Image versions, one per source repository. Every image the chart deploys derives its tag from one of these three, so a release is three numbers rather than nineteen image strings scattered across environment values files. |
| versions.cloud | string | `"1.2.0"` | EduIDE-Cloud: the operator and the REST service. Released independently of the IDE images, so it carries its own version. |
| versions.ide | string | `""` | The IDE images from the EduIDE repository (java-17, c, python, ...). Empty falls through to the chart's appVersion, which is what a release sets, so a plain `helm install --version 2.0.0` pins every IDE image to the tag that release published. |
| versions.landingPage | string | `"1.2.1"` | EduIDE-Landing-Page. Released independently as well. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
