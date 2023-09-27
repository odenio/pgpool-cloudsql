# Upgrading Steps
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