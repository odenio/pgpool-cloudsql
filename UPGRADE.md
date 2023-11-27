# Upgrading Steps

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
