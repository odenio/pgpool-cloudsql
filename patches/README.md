# experimental patches and how to use them

**THESE PATCHES ARE NEVER APPLIED IN THE PUBLIC odentech/pgpool-cloudsql DOCKER REPO**

If you perchance wish to test a patch to pgpool2 in your deployment of
pgpool-cloudsql, you will need to build your own docker images and then
override the default docker repository when deploying the helm chart.

## Build your own docker images

The `script/build-docker.sh` tool will build and push release docker images
for pgpool-cloudsql with every patch found in this directory applied sequentially.

By default this will attempt to push to the `odentech/pgpool-cloudsql` docker hub
repository. However you, person reading this, probably don't have write access to
that repo, so you'll need to use your own, e.g.:

```sh
REPOSITORY=mydockerid/pgpool-cloudsql ./script/build-docker.sh
```

...but replace "mydockerid/pgpool-cloudsql" with the name of your own docker
hub (or other) container image repository.

The script will automatically produce image tags in the default format of
`chart_version-pgpool_version`.

## Deploy with your custom images

When deploying, you will need to overwrite the default value of `deploy.repository`:

```sh
helm install --set deploy.repository=mydockerid/pgpool-cloudsql pgpool-cloudsql pgpool-cloudsql
```
