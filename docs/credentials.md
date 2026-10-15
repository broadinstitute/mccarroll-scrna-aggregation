# mccarroll/scrna-aggregation: Running locally and on Google Cloud

The pipeline reads `gs://` artifacts of the single-cell pipeline. Tasks that read `gs://` need Google credentials
and a project ID. How you supply them depends on where the pipeline runs.

| Where | Profile | Credentials | Status |
|---|---|---|---|
| Your workstation | `docker` | your own gcloud Application Default Credentials | tested |
| Broad cluster/VM (for example as `dropseq`) | `docker` | a service account key JSON file | same mechanism, not yet tested with a real key |
| Google Cloud Batch / Seqera Cloud | `googlebatch` | the job's service account (nothing is mounted) | profile stub only, settings not final |

## Running locally (`docker` profile)

1. Log in once with **application default** credentials. This is different from `gcloud auth login`, which only
   authenticates the gcloud CLI. Applications use the application default credentials.

   ```bash
   gcloud auth application-default login
   ```

   This writes `$HOME/.config/gcloud/application_default_credentials.json`.

2. Export your project **ID** (not the project number). For the McCarroll lab single-cell data this is
   `bican-um1-mccarroll`; adding the line to your shell profile saves repeating it. A project ID is an identifier, not
   a credential, so it is safe to write down. Access still requires valid credentials.

   ```bash
   export GOOGLE_PROJECT_ID=bican-um1-mccarroll
   ```

3. Run with the `docker` profile. The profile runs the containers as `linux/amd64`, because the Drop-seq images are
   amd64 only. This works on Apple Silicon through emulation, and is a no-op on an amd64 host:

   ```bash
   nextflow run . -profile docker --input <...> --outdir <...>
   ```

The credentials file is mounted read-only into every task container as `/opt/gcp/adc.json`, and
`GOOGLE_APPLICATION_CREDENTIALS` is pointed at it.

### Environment variables and parameters

| Name | Kind | Needed when | Meaning |
|---|---|---|---|
| `GOOGLE_PROJECT_ID` | environment variable | `docker` profile with Application Default Credentials | project ID used by the Google storage client (becomes `GOOGLE_CLOUD_PROJECT` in the container). Not needed with a service account key, which carries its own `project_id`. |
| `--gcp_credentials_file` | parameter | credentials are not at the default path | host path of the credentials JSON. Default: `$HOME/.config/gcloud/application_default_credentials.json` |
| `--image_tag` | parameter | you want a different image version | tag of the Drop-seq tool images (default `jn_test`; the images must already be available to Docker) |
| `--python_image` | parameter | you use a different registry or name | image name without tag (default `quay.io/broadinstitute/drop-seq_python`) |

### Pre-flight check

With the `docker` profile the pipeline checks the credentials before starting any process. It fails with a message
explaining the problem if:

- the credentials path does not exist, or is a directory. (Docker silently creates a directory at a missing mount
  source, which later gives a confusing error inside the container.)
- the file is not valid JSON.
- the file `type` is not `authorized_user` or `service_account`, or required fields are missing.
- the file is an `authorized_user` file and `GOOGLE_PROJECT_ID` is not set.

The check does not make a network call. It does not prove the credentials are accepted by Google. The first task that
reads `gs://` does that.

## Running with a service account key (cluster or VM)

Point the same profile at the key file:

```bash
nextflow run . -profile docker --gcp_credentials_file /path/to/service-account-key.json ...
```

- The key file is a secret, equivalent to a username and password. Never commit it, copy it into a work
  directory, or put its contents in a config file. It is mounted read-only.
- The file must be readable by the user running Nextflow, because containers run as that user.
- The service account needs read access (for example `roles/storage.objectViewer`) to the buckets that hold the
  single-cell pipeline outputs.

## Running on Google Cloud Batch (`googlebatch` profile)

The profile is a stub and its settings are not final. It reads:

```bash
export GOOGLE_PROJECT_ID=<project id>
export GOOGLE_LOCATION=<region, for example us-central1>
```

and needs a `gs://` work directory (`-work-dir gs://<bucket>/<path>`). Tasks authenticate as the job's service
account, supplied by the compute environment. Nothing is mounted. Still to be decided: the service account email
(`google.batch.serviceAccountEmail`) and the work directory bucket. The service account needs read access to the artifact
buckets and write access to the work bucket.
