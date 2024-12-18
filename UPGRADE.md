# Upgrading Steps

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
