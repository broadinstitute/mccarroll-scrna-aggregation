# mccarroll/scrna-aggregation: Running locally and on Google Cloud

The pipeline reads `gs://` artifacts of the single-cell pipeline. Tasks that read `gs://` need Google credentials
and a project ID. How you supply them depends on where the pipeline runs.

| Where | Profile | Credentials | Status |
|---|---|---|---|
| Your workstation | `docker` | your own gcloud Application Default Credentials | tested |
| Broad cluster/VM (for example as `dropseq`) | `docker` | a service account key JSON file | same mechanism, not yet tested with a real key |
| Google Cloud Batch (launched with `nextflow run`) | `googlebatch` | the Batch VM's service account (nothing is mounted); your own credentials launch the job | tested with the project's default service account (see below) |
| Seqera Cloud | `googlebatch` | the service account of the workspace compute environment | not yet tested |

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
   nextflow run . -profile docker --manifest <...> --analysis_id <...> --outdir <...>
   ```

The credentials file is mounted read-only into every task container as `/opt/gcp/adc.json`, and
`GOOGLE_APPLICATION_CREDENTIALS` is pointed at it.

### Environment variables and parameters

| Name | Kind | Needed when | Meaning |
|---|---|---|---|
| `GOOGLE_PROJECT_ID` | environment variable | `docker` profile with Application Default Credentials | project ID used by the Google storage client (becomes `GOOGLE_CLOUD_PROJECT` in the container). Not needed with a service account key, which carries its own `project_id`. |
| `--gcp_credentials_file` | parameter | credentials are not at the default path | host path of the credentials JSON. Default: `$HOME/.config/gcloud/application_default_credentials.json` |

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

Two different identities are involved:

| Who | Does what | Credentials |
|---|---|---|
| Nextflow, on your machine | submits the Batch job; reads and writes the `gs://` work directory | your own Application Default Credentials (`gcloud auth application-default login`, as for local runs) |
| Each task, on a Batch VM | reads the `gs://` artifacts and the work directory | the **VM's service account**, found automatically through the metadata server. Your credentials are not available there, and nothing is mounted. |

### Do I need to set up a service account?

Not if the job runs in the project that owns the data. If `google.batch.serviceAccountEmail` is not set, Batch runs the
VM as the project's default Compute Engine service account (`<project number>-compute@developer.gserviceaccount.com`).
That account has access to the buckets of its own project, so no configuration is needed. This was tested in both
projects below.

A service account is still used, and it is a different account from you. It only works when it has been granted
access to the buckets, so the project you run in matters.

### The project must have access to the bucket where the data lives

**Requirement:** the Google project you pass in `GOOGLE_PROJECT_ID` must have access to the root bucket that holds the data
(for example `mccarroll_scrnaseq_central_temp` or `bican-um1-mccarroll_standard`), and to the bucket of the work
directory. The pipeline does not check this before it starts. If the project has no access, the first task that reads
the bucket fails with `Permission denied` or `403`. Use `tests/batch_access_check` (below) to confirm it first.

### Choose the project at run time

The profile reads the project from the environment, so the same pipeline runs in any project. Use **the project that
owns the buckets you read** and write the work directory to a bucket that project can write to:

| Data | Project (`GOOGLE_PROJECT_ID`) | Work directory bucket used in tests |
|---|---|---|
| scRNA-seq (`mccarroll_scrnaseq_*` buckets) | `mccarroll-scrna-seq` | `mccarroll_scrnaseq_central_temp` |
| BICAN (`bican-um1-mccarroll_*` buckets) | `bican-um1-mccarroll` | `bican-um1-mccarroll_temp` |

```bash
export GOOGLE_PROJECT_ID=mccarroll-scrna-seq     # the project ID, not the project number
export GOOGLE_LOCATION=us-central1                # the region; keep jobs in the region of the buckets
nextflow run . -profile googlebatch -work-dir gs://mccarroll_scrnaseq_central_temp/nextflow/<your-scratch-path> ...
```

| Name | Kind | Meaning |
|---|---|---|
| `GOOGLE_PROJECT_ID` | environment variable | project that runs the Batch jobs and is billed for them |
| `GOOGLE_LOCATION` | environment variable | Batch region, for example `us-central1` |
| `-work-dir gs://...` | Nextflow option | work directory; Batch cannot use a local one |

### Reading buckets of another project

A job running in one project cannot read the buckets of the other unless its VM service account has been granted access.
This was seen directly: a job in `bican-um1-mccarroll` could not write to `mccarroll_scrnaseq_central_temp` (`Permission
denied` on the work directory), because the default service account of `bican-um1-mccarroll` is not in that bucket's access
list. If one run has to read both, grant the VM service account `roles/storage.objectViewer` on the other project's
buckets, or set `google.batch.serviceAccountEmail` to an account that already has access.

### Network

Batch needs a VPC network. A project without a network called `default` fails before any task starts:
`CODE_GCE_RESOURCE_NOT_FOUND ... networks/default was not found`. `bican-um1-mccarroll` has only `broad-allow`, so there
add:

```
google.batch.network    = 'global/networks/broad-allow'
google.batch.subnetwork = 'regions/us-central1/subnetworks/broad-allow'
```

`mccarroll-scrna-seq` has both `default` and `broad-allow` (the check below used `broad-allow`).

### Checking access before a long run

`tests/batch_access_check` runs one small task on Batch with the default service account and reads the size and first
1 KiB of one `gs://` object, so a large file is not downloaded. It needs no pipeline inputs:

```bash
export GOOGLE_PROJECT_ID=<project> GOOGLE_LOCATION=us-central1
nextflow run tests/batch_access_check -c tests/batch_access_check/nextflow.config \
  -work-dir gs://<bucket the project can write to>/nextflow/batch-access-check-work \
  --gcs_object gs://<bucket>/<path to an object>
```

It prints `OK size=... first_bytes_read=1024 ...`. `Permission denied` or `403` means the VM's service account cannot
read that object, or cannot write the work directory. It is not an nf-test, because nf-test always passes a local
`-work-dir`, and Batch needs a `gs://` one.

### Results so far

| Project | Check | Result |
|---|---|---|
| `bican-um1-mccarroll` | read one 8.4 GiB FASTQ in `bican-um1-mccarroll_standard`; work directory in `bican-um1-mccarroll_temp` | passed, default service account |
| `mccarroll-scrna-seq` | `LOCATE_SCRNA_ARTIFACTS` on the live manifest; work directory in `mccarroll_scrnaseq_central_temp` | passed, output identical to the baseline YAML |
| `bican-um1-mccarroll` | the same, against the `mccarroll_scrnaseq_central_temp` work directory | failed: no write access (cross-project) |

### Not decided yet

- A dedicated service account (`google.batch.serviceAccountEmail`) with narrower access than the default account, which
  is broad. The Broad service accounts that exist use long-lived JSON keys, which should be replaced by short-lived
  tokens. Not needed to run.
- The work directory bucket for real runs (`mccarroll_nextflow_test` is intended for this, but only a Seqera user has
  access today).
- Running on Seqera Cloud: the compute environment of the workspace supplies the service account and the project.
