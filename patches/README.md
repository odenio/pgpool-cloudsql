# experimental patches and how to use them

**THESE PATCHES ARE NEVER APPLIED IN THE PUBLIC odentech/pgpool-cloudsql DOCKER REPO**

If you perchance wish to test a patch to pgpool2 in your deployment of
pgpool-cloudsql, you will need to build your own docker images and then
override the default docker repository when deploying the helm chart.

## Build your own docker images

The `script/build-docker.sh` tool will build and push release docker images
for pgpool-cloudsql with every patch found in this directory applied sequentially.

You will need to supply your own docker repository that you have write
access to, either as the first argument to the build script or in the REPOSITORY
environment variable:

```sh
./script/build-docker.sh myrepository/pgpool-cloudsql
```

...or...

```sh
REPOSITORY=myrepository/pgpool-cloudsql ./script/build-docker.sh
```

...but replace "myrepository/pgpool-cloudsql" with the name of your own docker
hub or other container image repository.

By default, the script will automatically produce image tags in the default format of
`chart_version-pgpool_version`, e.g. `1.7.1-4.7.2` and so forth. You can optionally
set an image tag suffix as either the second positional argument or with the `TAG_SUFFIX`
environment variable:

```sh
./script/build-docker.sh myrepository/pgpool-cloudsql mytestfix
```

...or...

```sh
REPOSITORY=myrepository/pgpool-cloudsql TAG_SUFFIX=mytestfix ./script/build-docker.sh
```

Doing so will append that value to the default image tag after a hyphen, e.g.
`1.7.1-4.7.2-mytestfix`.

## Deploy with your custom images

When deploying, you will need to overwrite the default value of `deploy.repository`:

```sh
helm install \
  --set deploy.repository=myrepository/pgpool-cloudsql \
  --set deploy.tag=1.7.1-4.7.2-mytestfix \
  --set pgpool.version=4.7.2 \
  pgpool-cloudsql pgpool-cloudsql
```

Note that while if `deploy.repository` and `deploy.tag` are set, that image is used
no matter what value `pgpool.version` is set to, but `pgpool.version` still needs to
be a string that will pass template validation.
