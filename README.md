
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
     - Uses the [envtpl](https://github.com/odenio/envtpl) tool to fill out [pgpool.conf.tmpl](conf/pgpool.conf.tmpl)
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
  Monitoring, formerly known as Stackdriver.

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
export CHART_VERSION=1.0.3            # a chart version: https://github.com/odenio/pgpool-cloudsql/releases
export VALUES_FILE=./my_values.yaml   # your values file

helm install \
  "${RELEASE_NAME}" \
  odenio/pgpool-cloudsql \
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
`deploy.repository` | Docker image repository of the runtime image | `odentech/pgpool-cloudsql`
`deploy.tag` | Docker image tag of the runtime image | `1.0.3`
`deploy.affinity` | Kubernetes [affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) spec applied to the deployment pods | `{}`
`deploy.tolerations` | Kubernetes [tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) spec applied to the deployment pods | `{}`
`deploy.podDisruptionBudget.maxUnavailable` | Maximum number of pods allowed to be unavailable during an update ([docs](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)) | 1
`deploy.resources.pgpool` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the pgpool container | `{}`
`deploy.resources.discovery` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the discovery container. | `{}`
`deploy.resources.exporter` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the pgpool2_exporter container. | `{}`
`deploy.resources.telegraf` | Kubernetes [resource block](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the telegraf container. | `{}`

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

<hr>
</details>

## pgpool options

<details>
<summary>Show More</summary>
<hr>

Parameter | Description | Default
--- | --- | ---
`pgpool.reservedConnections` | When this parameter is set to 1 or greater, incoming connections from clients are not accepted with error message "Sorry, too many clients already", rather than blocked if the number of current connections from clients is more than (`numInitChildren` - `reservedConnections`). ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html#GUC-RESERVED-CONNECTIONS)) | `0`
`pgpool.numInitChildren` | The number of preforked Pgpool-II server processes. ([docs](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html#GUC-NUM-INIT-CHILDREN)) | `32`
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

<hr>
</details>

# Monitoring with Google Cloud Monitoring (AKA Stackdriver)

As configured, pgpool-cloudsql exports the following Google Cloud Monitoring
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

The bad news is that it has several critical bugs in it; at the time of this
writing we have two pull requests awaiting evaluation upstream:

- [Counter types were exported as gauges](https://github.com/pgpool/pgpool2_exporter/pull/10)
- [No metric for ratio of available connections](https://github.com/pgpool/pgpool2_exporter/pull/9)

We are currently running a build of the exporter that has our fixes
pre-applied; you can see this in the [Dockerfile](Dockerfile).

## Oh god, Telegraf

Having cobbled together a prometheus-like metrics endpoint, the obvious last
step was to use [telegraf](https://github.com/influxdata/telegraf) to forward
the data to Stackdriver.

Unfortunately, when we did so, we immediately noticed something very strange:
any counter- type metric, no matter what values telegraf appeared to be
sending, produced a graph that was a flat line at some seemingly random value
between 0 and 1, and manual queries for the timeseries data from the
stackdriver API would at first return data and then after a few minutes return
only `{"unit": "not_a_unit"}` for the exact same query.

The issue turned out to be that the telegraf stackdriver output plugin (which
we here at oden wrote) was not actually setting the start time correctly on
CUMULATIVE stackdriver metrics, and the stackdriver API imposes some frankly
odd conditions on same.

We have [an open PR](https://github.com/influxdata/telegraf/pull/10097) against
telegraf that fixes this behavior, and for now we are deploying a version of
telegraf helpfully provided by influxdata as part of their PR review process.
(This, also, is in the dockerfile.)

Lastly, it's worth calling out the [telegraf config
file](Helm/templates/configmap.yaml); in order to correctly fill in the
required attributes of a stackdriver `gke_container` resource, we run telegraf
under a [wrapper script](bin/telegraf.sh) that queries the GCP instance
metadata API in order to fill out the relevant environment variables.
