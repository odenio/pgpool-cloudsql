# Upgrading Steps

## `v1.6.1` → `v1.7.0`

### 🛑 Removed pgpool versions

Support for the v4.1 and v4.2 branches of pgpool is **removed**; both are past
end of life upstream. If you are pinning `pgpool.version` to a `4.1.x` or
`4.2.x` release, the values validator will now refuse to install and you must
move to 4.3 or later first.

### Software upgrades

Every remaining release channel moves to its current patch release, and the
v4.6 and v4.7 branches are added:

Branch | Old | New
--- | --- | ---
4.7 | (none) | `4.7.2`
4.6 | (none) | `4.6.7`
4.5 | `4.5.8` | `4.5.12`
4.4 | `4.4.13` | `4.4.17`
4.3 | `4.3.16` | `4.3.20`

The default `pgpool.version` stays on the 4.5 branch, now `4.5.12`. 4.6 and 4.7
are available opt-in.

Neither new branch requires a configuration change on our side:

* **4.6** adds `log_backend_messages` and removes nothing. Its one migration
  note is that `health_check_user`, `sr_check_user`, `recovery_user` and
  `wd_lifecheck_user` changed default from `nobody` to the empty string, which
  does not affect us because the chart has always required and set the first two
  explicitly.
* **4.7** retires slony clustering mode (never used here), flips the
  `log_pcp_processes` default from `on` to `off`, and renames `logdir` to
  `work_dir`. We continue to emit `logdir`, which 4.7 still accepts with a
  deprecation warning and which is the only spelling 4.3 through 4.6 understand.

### 🛑 The default `pgpool.version` was previously broken

`v1.4.1` bumped the pgpool releases in the build matrix but not in
`values.yaml`, so from `v1.4.1` through `v1.6.1` the default `pgpool.version`
stayed at `4.5.4` while the images published were `4.5.8`. A `helm install` that
did not set `pgpool.version` explicitly therefore resolved to an image tag that
was never built (e.g. `odentech/pgpool-cloudsql:1.6.1-4.5.4`) and the pods would
sit in `ImagePullBackOff`. The default now tracks the build matrix, and
`script/check-versions.sh` runs on every pull request to fail the build if the
matrix, the values schema, the chart defaults, or the documented version lists
ever disagree again.

### Fixed: the socket directory setting was wrong on half the supported versions

The generated `pgpool.conf` set `socket_dir`. Pgpool renamed that parameter to
`unix_socket_directories` in 4.4.0 and kept no alias, so on 4.4 and later the
setting was dropped and pgpool used its own default. Pgpool reports an unknown
parameter as `unrecognized configuration parameter` at `INFO`, but it does so
while parsing, before `log_min_messages` from the same file takes effect, and
the built-in default suppresses `INFO` -- so nothing actually reaches the log
and the setting failed silently. Spelling it the new way would just move the
same dead setting onto 4.3, which this release still supports. Since every
supported version defaults the socket directory to `/tmp`, which is exactly what
we were setting, the line is omitted entirely instead. No behavior change on any
version.

### Fixed: the docker build workflow never ran

`.github/workflows/docker.yaml` triggered on `release: [published]`, but our
releases are cut by `helm/chart-releaser-action` using the default
`GITHUB_TOKEN`, and GitHub deliberately does not deliver workflow-triggering
events for that token. The workflow had therefore never executed once, and
images had to be built by hand with `script/build-docker.sh`.

`release.yml` now calls the docker build directly as a reusable workflow, and
does so *before* chart-releaser publishes: a merge to `main` works out the
version, pushes every image, and only then releases the chart, so the chart is
never installable ahead of the images it names. The workflow also accepts
`workflow_dispatch` for a manual rebuild. `script/build-docker.sh` still works and is still the right tool for
building an image with a patch from `patches/` applied.

Separately, the Dockerfile's source download URL is updated: pgpool.net retired
the `download.php?f=` endpoint, so *every* build against it had begun failing
with a 404 regardless of version. Tarballs now come from
`https://www.pgpool.net/source/`.

## `v1.6.0` → `v1.6.1`

This is a maintenance release:

* the version of the Go runtime used to build the envtpl package is bumped from 1.25 to 1.26.2
* the Alpine Linux base image is updated from v3.22 to v3.23

## `v1.5.0` → `v1.6.0`

### New features

The discovery container now accepts multiple skip labels in
`discovery.replicaSkipLabel` as a comma-separated list. Any replica with one of
those labels set to `"true"` will be excluded from pgpool's backend pool.

Existing single-label configurations continue to work unchanged.

## `v1.4.1` → `v1.5.0`

### New features

Add the ability to exclude specific CloudSQL read replicas from pgpool's
backend pool by GCP instance label. This is useful when you have dedicated
read replicas that serve a specific consumer (e.g. an analytics engine) and
you don't want pgpool load-balancing general application traffic to them.

To use this feature, apply one or more GCP labels to the CloudSQL instance you
want to exclude (e.g. `pgpool-cloudsql-skip: "true"`), and set the
`discovery.replicaSkipLabel` chart value to the label key or comma-separated
label keys:

```yaml
discovery:
  replicaSkipLabel: "pgpool-cloudsql-skip"
```

When unset (the default), all replicas of the primary are included as before.

### VALUES - New:

Parameter | Description | Default
--- | --- | ---
`discovery.replicaSkipLabel` | If set, replicas with any listed GCP instance label set to `"true"` are excluded from pgpool's backend pool. Provide either a single label or a comma-separated list. | `""`

## `v1.4.0` → `v1.4.1`

### SECURITY

This release addresses [CVE-2025-46801](https://nvd.nist.gov/vuln/detail/CVE-2025-46801)
and is strongly recommended for all users.  The available version of pgpool
in each release channel is bumped to the latest:

- `4.5.8`
- `4.4.13`
- `4.3.16`
- `4.2.23`
- `4.1.23`

Additionally:

* the version of the Go runtime used to build the envtpl package is bumped from 1.24 to 1.25
* the Alpine Linux base image is updated from v3.21 to v3.22

## `v1.3.3` → `v1.4.0`

The 1.4.0 release removes support for using
[telegraf](https://github.com/influxdata/telegraf) to publish metrics to Google
Cloud Monitoring: it is recommended that you configure [Google Cloud Managed
Service for Prometheus](https://cloud.google.com/stackdriver/docs/managed-prometheus) if
you are running pgpool-cloudsql in a Google Kubernetes Engine cluster, or use
the [Prometheus Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md)
of the [Opentelemetry Collector](https://opentelemetry.io/docs/collector/) otherwise.

## `v1.3.2` → `v1.3.3`

This is a maintenance release:

* the version of the Go runtime used to build the envtpl package is bumped from 1.23 to 1.24
* the Alpine Linux base image is updated from v3.20 to v3.21

## `v1.3.1` → `v1.3.2`

This is a maintenance release:

* the version of the Go runtime used to build the envtpl package is bumped from 1.22 to 1.22
* the pgpool2_exporter package is built from source rather than installed from the github release artifact

## `v1.3.0` → `v1.3.1`

This is a maintenance release:

* the version of the Go runtime used to build the envtpl package is bumped from 1.18 to 1.22
* the pgpool2_exporter package is upgraded to v1.2.2
* the underlying alpine linux release used for the deploy image is upgrade to 3.20
* fix various pedantic warnings generated by the Dockerfile

## `v1.2.0` → `v1.3.0`

### SECURITY

This release addresses [CVE-2024-45624](https://nvd.nist.gov/vuln/detail/CVE-2024-45624)
and is strongly recommended for all users.  Support for affected versions of pgpool (`4.5.0`,
`4.4.5`, `4.3.8`, `4.2.15` and `4.1.18`) is _removed_, and the available version of pgpool
in each release channel is bumped to the latest:

- `4.5.4`
- `4.4.9`
- `4.3.12`
- `4.2.19`
- `4.1.22`

Support for the v4.0 branch of pgpool is removed entirely, hence the minor as opposed to
patch semver bump here.

### New features:

Support for setting the [read_only_function_list](https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html#GUC-READ-ONLY-FUNCTION-LIST) pgpool configuration parameter is added.

### VALUES - New:

Parameter | Description | Default
--- | --- | ---
`pgpool.readOnlyFunctionList` | A comma-separate list of Postgres function names which do not UPDATE the database and therefore can be safely load-balanced over read replicas. | `""`

## `v1.1.10` → `v1.2.0`

### New features

This release allows runtime picking of a version of PGPool-II from among the multiple
supported releases:

- `4.5.0`
- `4.4.5`
- `4.3.8`
- `4.2.15`
- `4.1.18`
- `4.0.25`

In order to keep deployed image size small, we do this by creating a docker
image for each combination of chart release and pgpool release, e.g.:
`odentech/pgpool-cloudsql:1.2.0-4.5.4`.

This means that the behavior of the `deploy.tag` setting has changed subtly: it
is no longer required, the default value is empty, and if the installer sets a
non-empty value, that overrides the tag portion of the image entirely. If you
are setting `deploy.tag` manually, you almost certainly want to be setting
`deploy.repository` as well!

*WARNING* - dynamic process management is only supported in v4.4 and above: we
have added a JSONschema values validator and attempting to configure dynamic
process managment with e.g. `pgpool.version=4.3.8` will fail validation and
refuse to install.

Also: provide some basic build-time tooling for testing and deploying patches
to pgpool itself, and document how to do this.

### VALUES - New:

Parameter | Description | Default
--- | --- | ---
`pgpool.version` | Pick which version of the actual PGPool-II binary to deploy from among the current release branches. | `4.5.0`

## `v1.1.9` → `v1.1.10`

### Software upgrade

This release updates pgpool from v4.4.4 to [v4.5.0](https://www.pgpool.net/docs/45/en/html/release-4-5-0.html).

### New features

Enable support for pgpool's dynamic process management mode.  This is disabled by default.

### VALUES - New:

Parameter | Description | Default
--- | --- | ---
pgpool.processManagmentMode | Whether to use static or dynamic [process management](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html). Allowable values are `static` and `dynamic` | `static`
pgpool.processManagementStrategy | When using [dynamic process managment](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html), defines how aggressively to scale down idle connections. Allowable values are `lazy`, `gentle` and `aggressive`. | `gentle`
pgpool.minSpareChildren | When using [dynamic process management](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html), sets the target for the minimum number of spare child processes. | `10`
pgpool.maxSpareChildren | When using [dynamic process management](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html), sets the target for the maximum number of spare child processes. | `10`

## `v1.1.8` → `v1.1.9`

### New features

Allow finer-grained control of startupProbe, readinessProbe and livenessProbe
settings for the `pgpool` and `exporter` containers.

### VALUES - New:

Parameter | Description | Default
--- | --- | ---
`deploy.startupProbe.pgpool.enabled` | whether to create a [startup probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes) for the pgpool container | `true`
`deploy.startupProbe.pgpool.initialDelaySeconds` | | `5`
`deploy.startupProbe.pgpool.periodSeconds` | | `5`
`deploy.startupProbe.pgpool.timeoutSeconds` | | `4`
`deploy.startupProbe.pgpool.successThreshold` | | `1`
`deploy.startupProbe.pgpool.failureThreshold` | | `1`
`deploy.startupProbe.exporter.enabled` | whether to create a [startup probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes) for the exporter container | `true`
`deploy.startupProbe.exporter.initialDelaySeconds` | | `5`
`deploy.startupProbe.exporter.periodSeconds` | | `5`
`deploy.startupProbe.exporter.timeoutSeconds` | | `4`
`deploy.startupProbe.exporter.successThreshold` | | `1`
`deploy.startupProbe.exporter.failureThreshold` | | `15`
`deploy.readinessProbe.pgpool.enabled` | whether to create a [readiness probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes) for the pgpool container | `true`
`deploy.readinessProbe.pgpool.initialDelaySeconds` | | `5`
`deploy.readinessProbe.pgpool.periodSeconds` | | `5`
`deploy.readinessProbe.pgpool.timeoutSeconds` | | `4`
`deploy.readinessProbe.pgpool.successThreshold` | | `1`
`deploy.readinessProbe.pgpool.failureThreshold` | | `2`
`deploy.readinessProbe.exporter.enabled` | whether to create a [readiness probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes) for the exporter container | `true`
`deploy.readinessProbe.exporter.initialDelaySeconds` | | `5`
`deploy.readinessProbe.exporter.periodSeconds` | | `5`
`deploy.readinessProbe.exporter.timeoutSeconds` | | `4`
`deploy.readinessProbe.exporter.successThreshold` | | `1`
`deploy.readinessProbe.exporter.failureThreshold` | | `2`
`deploy.livenessProbe.pgpool.enabled` | whether to create a [liveness probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes) for the pgpool container | `true`
`deploy.livenessProbe.pgpool.initialDelaySeconds` | | `5`
`deploy.livenessProbe.pgpool.periodSeconds` | | `5`
`deploy.livenessProbe.pgpool.timeoutSeconds` | | `4`
`deploy.livenessProbe.pgpool.successThreshold` | | `1`
`deploy.livenessProbe.pgpool.failureThreshold` | | `2`
`deploy.livenessProbe.exporter.enabled` | whether to create a [liveness probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes) for the exporter container | `true`
`deploy.livenessProbe.exporter.initialDelaySeconds` | | `5`
`deploy.livenessProbe.exporter.periodSeconds` | | `5`
`deploy.livenessProbe.exporter.timeoutSeconds` | | `4`
`deploy.livenessProbe.exporter.successThreshold` | | `1`
`deploy.livenessProbe.exporter.failureThreshold` | | `2`

## `v1.1.7` → `v1.1.8`

### Software upgrade

This release updates pgpool from v4.4.3 to [v4.4.4](https://www.pgpool.net/docs/44/en/html/release-4-4-4.html).

### New features

Inactive replicas are now not removed from the configuration file until a
threshold in seconds has been reached.  Because pgpool itself will direct
traffic away from a replica that is failing its health checks, there is no need
to immediately prune nodes that are not seen as active by the discovery script,
whether due to not being in the `RUNNABLE` state for some reason or having been
fully deleted.  This reduces the amount of potential config file thrashing
during common operations like restoring a db cluster from a backup.

### VALUES - New:
- `discovery.pruneThreshold` -- Value in seconds for how long a replica can be unavailable (not in state `RUNNABLE` or fully missing) before we remove it from the configuration file and force a reload.  Default is 900.

## `v1.1.6` → `v1.1.7`

This release adds the ability to disable the telegraf component and add custom pod annotations.

### VALUES - New:
- `telegraf.enabled` -- Allows enabling/disabling the telegraf component; default is `true` to preserve existing behavior
- `deploy.annotations` -- A map of kubernetes annotations to apply to each pod. Default is empty.

## `v1.1.5` → `v1.1.6`

> ℹ️ : telegraf 1.26.2

This release rolls telegraf back to 1.26.2 -- for reasons that we have yet to
determine, using the 1.28.x branch of telegraf results in an order-of-magnitude
increase in Google Cloud Monitoring metrics usage.

If you are _not_ seeing usage issues with Google Cloud Monitoring, you may
safely ignore this update. :)

## `v1.1.4` → `v1.1.5`

> ℹ️ : telegraf 1.28.3

This release updates telegraf to the latest version, and fixes a templating error
in which the ignoreLeadingWhiteSpace value was being applied in the wrong place.

## `v1.1.3` → `v1.1.4`

> ℹ️ : this release allows to set primary and replicas weights.

### VALUES - New:
- `pgpool.primaryWeight` -- It specifies the load balancing ratio of the primary postgres instance; default is 0
- `pgpool.replicasWeight` -- It specifies the load balancing ratio of the replicas; default is 1

## `v1.1.2` → `v1.1.3`

> ℹ️ overall upgrade:

    - 3.18 alpine
    - 1.19 golang
    - telegraf 1.28.1
    - pgpool 4.4.3 (nurikoboshi)
    - pgpool_exporter 1.2.1
    - latest pkg from alpine
## `v1.1.1` → `v1.1.2`

> ℹ️ this release fixes the initial value of the database region during the discovery phase.


## `v1.1.0` → `v1.1.1`

> ℹ️ this release allows discovering database instances worldwide inside your GCP project, and not only in the pod region.

### VALUES - New:
- `discovery.stayInRegion` -- The discover logic looks for databases in the same pod's region, all regions otherwise; default is true


## `v1.0.X` → `v1.1.0`

> 🛑 this release changes the default error handling behavior for the metrics/monitoring containers; you will need to update your values.yaml if you wish to preserve the previous behavior.

### Feature highlights

* Added the ability to control pod restart behavior if either of the monitoring containers ([pgpool2\_exporter](https://github.com/pgpool/pgpool2_exporter) and [telegraf](https://github.com/influxdata/telegraf) restart -- depending on your workload, it may not be helpful to interrupt in-flight db transactions due to errors that are outside the critical path

### VALUES - New:
- `exporter.exitOnError` -- Exit the container if the exporter process exits (otherwise, restart the exporter after a 1s delay); default is false
- `telegraf.exitOnError` -- Exit the container if the telegraf process exits (otherwise, restart telegraf after a 1s delay); default is false
