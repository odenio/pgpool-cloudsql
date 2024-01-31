
# the pgpool postgres proxy and load balancer

This chart uses the [PGPool-II](https://pgpool.net) and an enormous amount of
too-clever-by-half scripting to provide automatic load balancing across a
Google CloudSQL Postgres database and one or more read replicas in the same
region.

The primary moving parts are:

- [PGPool](https://pgpool.net) itself.  This runs in the pod's primary container, launched
  from the [pgpool.sh](bin/pgpool.sh) wrapper script

- A [discovery](bin/discovery.sh) script that runs in a separate container.  Once a minute, this script:
     - Uses the `gcloud` cli to list any primary dbs that match the `PRIMARY_INSTANCE_PREFIX` env
       variable as a prefix. (i.e. a prefix of `metadata-` matches `metadata-4093504851`)
     - Lists all currently active read replicas of the primary database
     - Uses the [envtpl](https://github.com/subfuzion/envtpl) tool to fill out [pgpool.conf.tmpl](conf/pgpool.conf.tmpl)
       and copy the result into `/etc/pgpool/pgpool.conf` if it differs from what is already there.
     - If replicas have been added or removed, it runs [pcp_reload_config](https://www.pgpool.net/docs/42/en/html/pcp-reload-config.html)
       which forces the pgpool process to re-read its configuration file.
     - If replicas have been added, it runs [pcp_attach_node](https://www.pgpool.net/docs/42/en/html/pcp-attach-node.html)
       to tell pgpool to begin routing traffic to it

- The [pgpool prometheus exporter](https://github.com/pgpool/pgpool2_exporter), which
  exposes a Prometheus-compatible `/metrics` HTTP endpoint with statistics gleaned
  from PGPool's [internal stats commands](https://www.pgpool.net/docs/42/en/html/sql-commands.html).

- The [telegraf](https://github.com/influxdata/telegraf) monitoring agent,
  configured to forward the metrics exposed by the exporter to Google Cloud
  Monitoring, formerly known as Stackdriver. (This portion is optional; if you
  have an existing apparatus for scraping prometheus metrics, you can point
  it directly at the exporter.)

In general you should expect that if you add a new replica, it should start
taking 1/Nth of the select query load (where N is the number of replicas)
within 5 to 15 minutes (beware of stackdriver reporting lag!).

By default as we've configured it, pgpool will send all mutating statements
(UPDATE/INSERT/DELETE and all statements including SELECT inside a transaction
with a mutating statement) to the primary instance, and load balance (on a
per-statement level) all SELECTs evenly across the available read replicas.

The exception is that any statement containing the string `DO NOT LOAD BALANCE`
(inside a comment is okay and in fact expected) will be routed to the primary
instance no matter what.  This is configureable at deploy time as
`.pgpool.primaryRoutingQueryPatternList` in [values.yaml](Helm/values.yaml).

## Upgrade Guides

Old Version | New Version | Upgrade Guide
--- | --- | ---
v1.1.10 | v1.2.0 | [link](UPGRADE.md#v1110--v120)
v1.1.8 | v1.1.10 | [link](UPGRADE.md#v118--v1110)
v1.1.9 | v1.1.9 | [link](UPGRADE.md#v118--v119)
v1.1.7 | v1.1.8 | [link](UPGRADE.md#v117--v118)
v1.1.6 | v1.1.7 | [link](UPGRADE.md#v116--v117)
v1.1.5 | v1.1.6 | [link](UPGRADE.md#v115--v116)
v1.1.4 | v1.1.5 | [link](UPGRADE.md#v114--v115)
v1.1.3 | v1.1.4 | [link](UPGRADE.md#v113--v114)
v1.1.2 | v1.1.3 | [link](UPGRADE.md#v112--v113)
v1.1.1 | v1.1.2 | [link](UPGRADE.md#v111--v112)
v1.1.0 | v1.1.1 | [link](UPGRADE.md#v110--v111)
v1.0.X | v1.1.0 | [link](UPGRADE.md#v10x--v110)

# Installing the Chart

## Step One: add our Helm repository to your client:

```sh
helm repo add pgpool-cloudsql https://odenio.github.io/pgpool-cloudsql && \
helm repo update
```

## Step Two: install the chart

```sh
export RELEASE_NAME=my-pgpool-service # a name (you will need 1 installed chart for each primary DB)
export NAMESPACE=my-k8s-namespace     # a kubernetes namespace
export CHART_VERSION=1.1.4           # a chart version: https://github.com/odenio/pgpool-cloudsql/releases
export VALUES_FILE=./my_values.yaml   # your values file

helm install \
  "${RELEASE_NAME}" \
  pgpool-cloudsql/pgpool-cloudsql \
  --atomic \
  --timeout=5m0s \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}"
```

Please note that there are several Helm values that you are required to fill
out; a bare-minimum local `my_values.yaml` would look like this:

```yaml
discovery:
  primaryInstancePrefix: my-cloudsql-instance-name-prefix
pgpool:
  srCheckUsername: <postgres_username>
  srCheckPassword: <postgres_password>
  healthCheckUsername: <postgres_username>
  healthCheckPassword: <postgres_password>
exporter:
  postgresUsername: <postgres_username>
  postgresPassword: <postgres_password>
```

See below for the full list of possible values:

# Chart Values

## Kubernetes deployment options
<details>
<summary>Show More</summary>
<hr>

Parameter | Description | Default
--- | --- | ---
`deploy.replicaCount` | Number of pod replicas to deploy | `1`
`deploy.repository` | Docker image repository of the runtime container image | `odentech/pgpool-cloudsql`
`deploy.tag` | If set, override the tag of the runtime container image. If left empty, we use the concatenation of the chart version (`1.2.0`) and the selected `pgpool.version` e.g. `1.2.0-4.5.0` | `""`
`deploy.service.tier` | Value for the "tier" [label](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) applied to the kubernetes [service](https://kubernetes.io/docs/concepts/services-networking/service/) | `db`
`deploy.service.additionalLabels` | Map of additional k/v string pairs to add as labels for the kubernetes service | `{}`
`deploy.annotations` | Kubernetes [annotation](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/) spec applied to the deployment pods | `{}`
`deploy.affinity` | Kubernetes [affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) spec applied to the deployment pods | `{}`
`deploy.tolerations` | Kubernetes [tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) spec applied to the deployment pods | `{}`
`deploy.podDisruptionBudget.maxUnavailable` | Maximum number of pods allowed to be unavailable during an update ([docs](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)) | 1
`deploy.resources.pgpool` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the pgpool container | `{}`
`deploy.resources.discovery` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the discovery container. | `{}`
`deploy.resources.exporter` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the pgpool2_exporter container. | `{}`
`deploy.resources.telegraf` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the telegraf container. | `{}`
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
<hr>
</details>

## PCP options
<details>
<summary>Show More</summary>
<hr>

Parameter | Description | Default
--- | --- | ---
`pcp.password` | Password used for connecting to the pgpool process control interface by [PCP commands](https://www.pgpool.net/docs/42/en/html/pcp-commands.html).  This is interpolated at startup into both the [pcp.conf](https://www.pgpool.net/docs/42/en/html/configuring-pcp-conf.html) and [pcppass](https://www.pgpool.net/docs/42/en/html/pcp-commands.html#:~:text=2.-,PCP%20password%20file,-The%20file%20.pcppass) files so that the discovery script can send commands to pgpool. (If unset, a random one is generated at runtime.) | `""`

<hr>
</details>

## Discovery options
<details>
<summary>Show More</summary>
<hr>

Parameter | Description | Default
--- | --- | ---
`discovery.primaryInstancePrefix` | *REQUIRED* Search sting used to find the primary instance ID; is fed to `gcloud sql instances list --filter name:${PRIMARY_INSTANCE_PREFIX}`.  *Must* match only one instance. | (none)
`discovery.pruneThreshold` | Threshold in seconds after which an undiscoverable (missing or not in state `RUNNABLE`) replica will be removed from the generated configuration file. | `900`

<hr>
</details>

## pgpool2_exporter options
<details>
<summary>Show More</summary>
<hr>

Parameter | Description | Default
--- | --- | ---
`exporter.postgresUsername` | *REQUIRED* Username used by [pgpool2_exporter](https://github.com/pgpool/pgpool2_exporter) to connect to pgpool with.  This must be a valid postgres username in your installation. | `""`
`exporter.postgresPassword` | *REQUIRED* Password used with `exporter.postgresUsername` | `""`
`exporter.postgresDatabase` | Postgres database used in the connection string by `pgpool2_exporter` -- this must be a valid database name in your Postgres installation. | `postgres`
`exporter.exitOnError` | Exit the container if the exporter process exits | `false`

<hr>
</details>

## telegraf options

<details>
<summary>Show More</summary>
<hr>

Parameter | Description | Default
--- | --- | ---
`telegraf.enabled` | If true, deploy and configure the telegraf container | `true`
`telegraf.exitOnError` | Exit the container if the telegraf process exits | `false`

<hr>
</details>

## pgpool options

<details>
<summary>Show More</summary>
<hr>

Parameter | Description | Default
--- | --- | ---
`pgpool.version` | Which version of pgpool to deploy. Currently supported: `4.5.0`, `4.4.5`, `4.3.8`, `4.2.15`, `4.1.18`, `4.0.25`  | `4.5.0`
`pgpool.reservedConnections` | When this parameter is set to 1 or greater, incoming connections from clients are not accepted with error message "Sorry, too many clients already", rather than blocked if the number of current connections from clients is more than (`numInitChildren` - `reservedConnections`). ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html#GUC-RESERVED-CONNECTIONS)) | `0`
pgpool.processManagmentMode | Whether to use static or dynamic [process management](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html). Allowable values are `static` and `dynamic` | `static`
pgpool.processManagementStrategy | When using [dynamic process managment](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html), defines how aggressively to scale down idle connections. Allowable values are `lazy`, `gentle` and `aggressive`. | `gentle`
pgpool.minSpareChildren | When using [dynamic process management](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html), sets the target for the minimum number of spare child processes. | `5`
pgpool.maxSpareChildren | When using [dynamic process management](https://www.pgpool.net/docs/45/en/html/runtime-config-process-management.html), sets the target for the maximum number of spare child processes. | `10`
`pgpool.numInitChildren` | This defines the hard limit for concurrent incoming connections: when using static process management pgpool will pre-fork exactly this many children. When using dynamic process management, pgpool will try to maintain a pool of child processes that satisfy the values of minSpareChilden and maxSpareChildren but will never go over numInitChildren. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html#GUC-NUM-INIT-CHILDREN)) | `32`
`pgpool.maxPool` | The maximum number of cached connections in each Pgpool-II child process. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html#GUC-MAX-POOL)) | `32`
`pgpool.childLifeTime` | Specifies the time in seconds to terminate a Pgpool-II child process if it remains idle. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html#GUC-CHILD-LIFE-TIME)) | `5min`
`pgpool.childMaxConnections` | Specifies the lifetime of a Pgpool-II child process in terms of the number of client connections it can receive. Pgpool-II will terminate the child process after it has served child_max_connections client connections and will immediately spawn a new child process to take its place. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html#GUC-CHILD-MAX-CONNECTIONS)) | `8192`
`pgpool.connectionLifetime` | Specifies the time in seconds to terminate the cached connections to the PostgreSQL backend. This serves as the cached connection expiration time.  ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html#GUC-CONNECTION-LIFE-TIME)) |  `0`
`pgpool.clientIdleLimit` | Specifies the time in seconds to disconnect a client if it remains idle since the last query. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html#GUC-CONNECTION-IDLE-LIMIT)) | `300`
`pgpool.ignoreLeadingWhiteSpace` | When set to on, Pgpool-II ignores the white spaces at the beginning of SQL queries in load balancing. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html#GUC-IGNORE-LEADING-WHITE-SPACE)) | `on`
`pgpool.primaryRoutingQueryPatternList` | Specifies a semicolon separated list of regular expressions matching SQL patterns that should always be sent to primary node. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html#GUC-PRIMARY-ROUTING-QUERY-PATTERN-LIST)) | `.*DO NOT LOAD BALANCE.*`
`pgpool.allowSqlComments` | When set to on, Pgpool-II ignore the SQL comments when identifying if the load balance or query cache is possible on the query. When this parameter is set to off, the SQL comments on the query could effectively prevent the query from being load balanced or cached. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html#GUC-ALLOW-SQL-COMMENTS)) | `on`
`pgpool.disableLoadBalanceOnWrite` | Specify load balance behavior after write queries appear. Options are `off`, `transaction`, `trans_transaction`, `always` and `dml_adaptive`. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html#GUC-DISABLE-LOAD-BALANCE-ON-WRITE)) | `transaction`
`pgpool.statementLevelLoadBalance` | When set to on, the load balancing node is decided for each read query. When set to off, load balancing node is decided at the session start time and will not be changed until the session ends. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-load-balancing.html#GUC-STATEMENT-LEVEL-LOAD-BALANCE)) | `on`
`pgpool.logMinMessages` | Controls which minimum message levels are emitted to log. Valid values are `DEBUG5`, `DEBUG4`, `DEBUG3`, `DEBUG2`, `DEBUG1`, `INFO`, `NOTICE`, `WARNING`, `ERROR`, `LOG`, `FATAL`, and `PANIC`. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-logging.html#GUC-LOG-MIN-MESSAGES)) | `ERROR`
`pgpool.logErrorVerbosity` | Controls the amount of detail emitted for each message that is logged. Valid values are `TERSE`, `DEFAULT`, and `VERBOSE`, each adding more fields to displayed messages. `TERSE` excludes the logging of `DETAIL`, `HINT`, `QUERY` and `CONTEXT` error information.  ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-logging.html#GUC-LOG-ERROR-VERBOSITY)) | `TERSE`
`pgpool.srCheckUsername` | *REQUIRED* Specifies the PostgreSQL user name to perform streaming replication check. The user must have LOGIN privilege and exist on all the PostgreSQL backends. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-streaming-replication-check.html#GUC-SR-CHECK-USER)) | `""`
`pgpool.srCheckPassword` | Specifies the password of the `srCheckUsername` PostgreSQL user to perform the streaming replication checks. Use '' (empty string) if the user does not requires a password. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-streaming-replication-check.html#GUC-SR-CHECK-PASSWORD)) | `""`
`pgpool.srCheckDatabase` | Specifies the database to perform streaming replication delay checks. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-streaming-replication-check.html#GUC-SR-CHECK-DATABASE)) | `postgres`
`pgpool.healthCheckUsername` | *REQUIRED* Specifies the PostgreSQL user name to perform health check. The same user must exist in all the PostgreSQL backends. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-health-check.html#GUC-HEALTH-CHECK-USER)) | `""`
`pgpool.healthCheckPassword` | Specifies the password for the PostgreSQL user name configured in health_check_user to perform health check. The user and password must be same in all the PostgreSQL backends. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-health-check.html#GUC-HEALTH-CHECK-PASSWORD)) | `""`
`pgpool.healthCheckDatabase` | Specifies the PostgreSQL database name to perform health check. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-health-check.html#GUC-HEALTH-CHECK-DATABASE)) | `postgres`
`pgpool.coredumpSizeLimit` | Size limit in blocks of core files that pgpool is allowed to emit if a worker crashes; this is fed to `ulimit -c` in the [wrapper script](bin/pgpool.sh), so valid values are any integer or `"unlimited"`. | `"0"`

<hr>
</details>

# Monitoring with Google Cloud Monitoring (AKA Stackdriver)

If the telegraf container is enabled, pgpool-cloudsql exports the following Google Cloud Monitoring
[metricDescriptors](https://cloud.google.com/monitoring/custom-metrics/creating-metrics)
with the [gke_container](https://cloud.google.com/monitoring/api/resources#tag_gke_container)
resource type and all resource labels automatically filled in.

An example Stackdriver dashboard definition can be found in
[monitoring/dashboard.json](monitoring/dashboard.json).

The full list of metricDescriptor definitions is in
[monitoring/metrics.json](monitoring/metrics.json).

<details>
<summary>Full metric descriptor list</summary>
<hr>

All metricDescriptors are created under the `custom.googleapis.com/telegraf/` prefix.

Metric Descriptor | List of Metric Labels
--- | ---
`pgpool2_backend_by_process_total/gauge` | `pool_pid, host, url`
`pgpool2_backend_by_process_used/gauge` | `backend_id, pool_id, username, pool_pid, host, url, database`
`pgpool2_backend_by_process_used_ratio/gauge` | `pool_pid, host, url`
`pgpool2_backend_total/gauge` | `host, url`
`pgpool2_backend_used/gauge` | `host, url`
`pgpool2_backend_used_ratio/gauge` | `host, url`
`pgpool2_frontend_total/gauge` | `host, url`
`pgpool2_frontend_used/gauge` | `username, host, url, database`
`pgpool2_frontend_used_ratio/gauge` | `host, url`
`pgpool2_last_scrape_duration_seconds/gauge` | `host, url`
`pgpool2_last_scrape_error/gauge` | `host, url`
`pgpool2_pool_backend_stats_ddl_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_delete_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_error_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_fatal_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_insert_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_other_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_panic_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_select_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_status/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_backend_stats_update_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_cache_cache_hit_ratio/gauge` | `host, url`
`pgpool2_pool_cache_free_cache_entries_size/gauge` | `host, url`
`pgpool2_pool_cache_num_cache_entries/gauge` | `host, url`
`pgpool2_pool_cache_num_hash_entries/gauge` | `host, url`
`pgpool2_pool_cache_used_cache_entries_size/gauge` | `host, url`
`pgpool2_pool_cache_used_hash_entries/gauge` | `host, url`
`pgpool2_pool_health_check_stats_average_duration/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_average_retry_count/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_fail_count/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_max_duration/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_max_retry_count/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_min_duration/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_retry_count/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_skip_count/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_status/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_success_count/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_health_check_stats_total_count/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_nodes_replication_delay/gauge` | `role, hostname, host, url, port`
`pgpool2_pool_nodes_select_cnt/counter` | `role, hostname, host, url, port`
`pgpool2_pool_nodes_status/gauge` | `role, hostname, host, url, port`
`pgpool2_scrapes_total/counter` | `host, url`
`pgpool2_up/gauge` | `host, url`

<hr>
</details>

# Monitoring with Prometheus directly

Using telegraf to forward prometheus metrics to Google Cloud
Monitoring/Stackdriver is optional: the `pgpool2_exporter` container exposes a
prometheus-style `/metrics` endpoint on port 9090/tcp (and named as the
`metrics` port in the pod port configuration), and if you have an existing
local Prometheus infrastructure or if you are using the [Google Managed Service
for Prometheus](https://cloud.google.com/stackdriver/docs/managed-prometheus),
you can scrape and ingest those metrics directly.

The details of this will be specific to your local Prometheus setup, but
traditionally prometheus-on-kubernetes collection agents (whether the native
prometheus one or the Opentelemetry Collector) use Kubernetes annotations to
configure their scrape targets. To add annotations to your pods, use the
`.deploy.annotations` value in your Helm values.yaml, for example:

```yaml
deploy:
  annotations:
    prometheus.io/scrape: enabled
    prometheus.io/path: /metrics
    prometheus.io/port: metrics
```

# background info: maybe the real friends were all the yaks we shaved along the way

A billion fussy details stood in between us and the simple-seeming state of
affairs described above, and it's possible you may have to debug them in anger,
so here are a few of them:

## inter-container authentication

The updater container uses the [pcp cli
commands](https://www.pgpool.net/docs/42/en/html/pcp-commands.html) to talk to
pgpool over its tcp control port (9898/tcp).  The PCP protocol requires
password auth; this is set up in the [pcp.conf](conf/pcp.conf) file that is in
the shared volume mounted as `/etc/pgpool` in both containers.  A random PCP
password is set up at runtime if you do not set `.pcp.password` in
`values.yaml`.

If you need to run any of the `pcp_*` commands yourself for interactive
debugging, you will need to use the `-h localhost -w` flags.  The `-w` flag
forces the commands to use the `/root/.pcppass` file as the auth source so that
the updater script (and you) can issue pcp commands without typing the
password.

Note: the `pcp.conf` file is generated at runtime from the
[template](conf/pcp.conf.tmpl).

## config reloads don't do what you think

Adding a new replica to `pgpool.conf` and running
[pcp_reload_config](https://www.pgpool.net/docs/42/en/html/pcp-reload-config.html)
does not commence sending traffic to that node!  It only makes pgpool aware
that the node _exists_ -- you have to then run the
[pcp_attach_node](https://www.pgpool.net/docs/42/en/html/pcp-attach-node.html)
command to tell pgpool that the node is able to receive traffic.  The discovery
script does this for you automatically.

## node ID to hostname/ip bindings must be stable

Pgpool gets extremely unhappy if the hostname or IP address of a node changes
out from underneath it; we've addressed this by adding an [extremely
sleazy](bin/functions.sh) persistence model: for every IP address we observe,
we create a new node ID, and node IDs are never recycled for the lifetime of
the pod.

The pgpool documentation is silent on the question of how many backend nodes it
is capable of monitoring: if you delete and then re-create a large number of
replicas for some reason, it might be advisable to slowly roll the pgpool pods
to make sure they start from scratch.

## Oh god, Stackdriver

Getting useful stackdriver metrics out of pgpool was easily 60% of the process
of pulling this project together.  By default, the _only_ statistics interface
that pgpool offers is a series of ["SQL-like"
commands](https://www.pgpool.net/docs/42/en/html/sql-commands.html) that are
run inside a psql session.  Importantly, the tables returned by these commands
are not actual tables and cannot be queried with SELECT or JOIN.  (You can add
the ability to do that with the [pgpool_adm
extension](https://www.pgpool.net/docs/42/en/html/pgpool-adm.html) but of
course there is no way to install that on a CloudSQL instance.)

But there was some good news: the
[pgpool2_exporter](https://github.com/pgpool/pgpool2_exporter) is a standalone
binary that scrapes and parses the data returned by the "sql-like" commands and
exports it as a prometheus-compatible `/metrics` endpoint.

## Oh god, Telegraf

Lastly, it's worth calling out the [telegraf config
file](Helm/templates/configmap.yaml); in order to correctly fill in the
required attributes of a stackdriver `gke_container` resource, we run telegraf
under a [wrapper script](bin/telegraf.sh) that queries the GCP instance
metadata API in order to fill out the relevant environment variables.
