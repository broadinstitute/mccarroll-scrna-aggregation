# mccarroll/scrna-aggregation: Testing

The tests use [nf-test](https://www.nf-test.com) (0.9.5). Run every command from the repository root (see [Before you start](#before-you-start)). For coding conventions and known pitfalls, see [development.md](development.md).

There are four kinds of tests:

| Kind | What it does | Needs |
|---|---|---|
| Unit tests | One module or Groovy function at a time, on tiny fixtures | Docker for the modules that run a tool |
| Synthetic pipeline tests | The end-to-end tests on synthetic data: the whole pipeline on tiny local libraries | Docker only |
| Live tests | The modules and the whole pipeline on the real data of `tests/live_data/manifest.yaml`, compared with a baseline | Docker, network, Google credentials, the baseline |
| Google Cloud Batch run | The whole pipeline on Google Cloud Batch (a script; costs a little money) | `nextflow`, `gsutil`, Google credentials, the baseline |

## Before you start

- **The repository root.** Run every command from the top of the repository, the directory that holds `nf-test.config`:

  ```bash
  cd path/to/mccarroll-scrna-aggregation
  ```

  From any other directory nf-test finds no `nf-test.config` ("Warning: This pipeline has no nf-test config file") and scans everything below that directory, which gives a flood of warnings about unrelated files and then an error.
- **Docker** must be running (Docker Desktop or Colima). The tests pull the public Drop-seq images on first use. On an Apple Silicon Mac, see [Make the tests faster on Apple Silicon](#make-the-tests-faster-on-apple-silicon-colima) at the end: the default setup is several times slower.
- **`nf-test`** (0.9.5) and **`nextflow`** on your `PATH`.
- **The project ID**, exported once per shell:

  ```bash
  export GOOGLE_PROJECT_ID=mccarroll-scrna-seq
  ```

  The input validation tests, the live tests, `tests/run_all_tests.sh` and the Google Cloud Batch run need it (the pipeline's credentials check stops without it). The unit tests and the synthetic pipeline tests do not.
- **Google credentials and the baseline** for the live tests and the Google Cloud Batch run: see those sections.

## Where the tests are

- The pipeline tests run the QC step by default: `tests/nextflow.config` sets `run_qc = true`, while the pipeline default (`conf/params.config`) is `false`. A test that checks the default sets `run_qc = false` itself.
- Unit tests sit next to the unit, as in nf-core: `modules/local/<tool>/tests/main.nf.test`, with a `nextflow.config` and a `fixtures/` directory beside it. Tests of the Groovy code and the pre-flight checks are in `subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/`.
- Pipeline-level tests are in the top-level `tests/`: `pipeline.synthetic.nf.test`, `pipeline.validation.nf.test` and `pipeline.live.nf.test`.
- Test names start with `Should ...`.
- Test output goes to `.nf-test/` (git-ignored). `nf-test.config` sets the default profile to `docker,test`.

## Run the unit tests

All the unit tests (every module and the Groovy and pre-flight tests; not the live ones, which are `gcs.nf.test`, `live.nf.test` and `resolver.live.nf.test`):

```bash
nf-test test modules/local/*/tests/main.nf.test subworkflows/local/*/tests/*.function.nf.test
```

They need Docker for the modules that run a tool, and no credentials, network or project ID. To run less:

```bash
nf-test test modules/local/<module>/tests/main.nf.test                    # one module
nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/  # the Groovy and pre-flight tests (the live resolver test in this directory also needs the baseline)
nf-test test tests/pipeline.validation.nf.test                            # input validation and --help (no containers start; needs GOOGLE_PROJECT_ID)
```

## Run the synthetic pipeline tests

These are the end-to-end tests on synthetic data: they run the whole pipeline, from manifest to published files, on tiny libraries in `tests/fixtures/synthetic/` (see its `README.md`). They need Docker and nothing else: no network, credentials or baseline.

```bash
nf-test test tests/pipeline.synthetic.nf.test
```

Three of these tests (the donor-level join) need the fix of `join_and_filter_tsv` (Drop-seq pull request 594), which is in the public image tagged `current` (pull it again if the tests fail with an old image).

To look at a run, the inputs are in `.nf-test/synthetic_root` and the outputs are in `.nf-test/tests/<test id>/` (`output/` holds the published files, `work/` every task directory, `meta/nextflow.log` the log). nf-test prints the test id.

## Run the live tests

The live tests are tied to one manifest, `tests/live_data/manifest.yaml` (one library, analysis id `SMRI_V11.unfiltered`), and one baseline directory, `tests/live_data/baseline/`; both paths are fixed in the tests, so step 2 needs no manifest argument. The baseline must be made from that manifest (step 1); a baseline from any other manifest makes the live tests fail. The data set is small: it checks that the software works, not the biology. Larger data sets are run by hand with the pipeline and validated separately. They run on the real data and compare the result with the **baseline**: the output of the prototype shell script (`docs/specifications/scrna-aggregation_prototype.sh`) on the same manifest. A test passes when the generated file has the same content as the baseline's file. When it does not, the test prints the first differing lines.

### Prerequisites

- Docker and network access.
- Google Cloud Application Default Credentials: `gcloud auth application-default login`.
- `GOOGLE_PROJECT_ID` exported (see [Before you start](#before-you-start)).
- The baseline (step 1).

### Step 1: make the baseline

The baseline goes into `tests/live_data/baseline/` (git-ignored). It needs `gcloud` on the host (`gcloud auth login`) and about 340 MB of scratch space. Make it with the QC step, because the whole-pipeline live test runs the QC step and compares its files:

```bash
docs/specifications/scrna-aggregation_prototype.sh --manifest tests/live_data/manifest.yaml \
    --analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag current --run-qc
```

Remake the baseline when the tool images change in a way that changes the results.

### Step 2: run the tests

```bash
nf-test test --tag live       # only the live tests
```

To run one live test file, pass it to `nf-test test`:

```bash
nf-test test tests/pipeline.live.nf.test                                       # the whole pipeline, with the QC step
nf-test test modules/local/summarize_scrna_experiments/tests/gcs.nf.test       # one module
```

The live module tests are `gcs.nf.test` or `live.nf.test` in each module's `tests/` directory. `run_date` and `run_status` in the library metrics come from the newest Nextflow trace in the bucket, so a newer run of the library makes those two columns differ from an older baseline.

## Run all the tests

```bash
tests/run_all_tests.sh
```

This runs every nf-test: the unit, input validation, synthetic and live tests. It needs everything from [Before you start](#before-you-start) and the live tests' prerequisites (the baseline and Google credentials). It stops at once, with a clear message, if the project ID, the credentials file, `nf-test` or the baseline is missing. On the fast Colima setup below it takes about 12 minutes; the default Colima setup on Apple Silicon is two to three times slower.

## Run the whole pipeline on Google Cloud Batch

`tests/google_cloud_batch_run/run.sh` runs the whole pipeline on the live manifest with `-profile googlebatch`, with `gs://` work and output directories, then checks the result against the baseline. It is a script and not an nf-test, because nf-test always passes a local work directory and Google Cloud Batch needs a `gs://` one. It is not part of `tests/run_all_tests.sh`. Background on identities, projects and network: [credentials.md](credentials.md).

Needs Application Default Credentials, `nextflow`, `gsutil` and the baseline. The project must own the data and be able to write the work bucket (the live data is in `mccarroll-scrna-seq`). The `googlebatch` profile needs `GOOGLE_PROJECT_ID` (see [Before you start](#before-you-start)) and `GOOGLE_LOCATION`:

```bash
export GOOGLE_LOCATION=us-central1
tests/google_cloud_batch_run/run.sh [gs://<bucket>/<path>]
# default base: gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing
```

The script writes `<base>/work` and `<base>/out`, downloads the output to `testing_google_cloud_batch_run/out` (git-ignored), and prints PASS or FAIL for each check. The exit status is the number of failures (1 if the run itself failed, 2 if a prerequisite is missing). The run takes a few minutes. Delete the scratch data when you are done: `gsutil -m rm -r <base>/work <base>/out`. At the end the script prints each task's requested memory, peak memory and run time, to tune `conf/modules.config`.

If it fails:

- `Missing Google project Id`: `GOOGLE_PROJECT_ID` is not exported.
- `CODE_GCE_RESOURCE_NOT_FOUND ... networks/default`: the profile uses the `broad-allow` network of `GOOGLE_PROJECT_ID`; check that the project has it.
- `Permission denied` or `403` on a bucket: the project cannot reach that bucket (see [credentials.md](credentials.md), "The project must have access to the bucket where the data lives").

## Make the tests faster on Apple Silicon (Colima)

The Drop-seq images are `linux/amd64` only. On an Apple Silicon Mac every tool run is emulated. With a Colima profile that uses the QEMU virtual machine and `sshfs` mounts, the emulation is slow. The same test file ran in 159 s there and in 47 s with Apple's Virtualization framework (`vz`), Rosetta and `virtiofs` mounts (measured on an M-series Mac, 10 CPUs and 32 GiB for the VM), and the whole suite takes about 12 minutes on the fast setup. Linux x86 machines run the images natively and need none of this.

Check your profile:

```bash
colima list              # every profile and whether it is running
colima status            # the profile named default (or the one in COLIMA_PROFILE)
colima status rosetta    # a named profile, here the fast one created below
```

`colima status` says "running using QEMU" (and `mountType: sshfs`) for the slow setup and "running using macOS Virtualization.Framework" (and `mountType: virtiofs`) for the fast one. Which profile the tests use is decided by the Docker context: `docker context show` prints `colima` for the `default` profile and `colima-rosetta` for the profile created below. Colima cannot change the VM type of an existing profile, so create a new one next to it:

```bash
colima start rosetta --vm-type vz --vz-rosetta --mount-type virtiofs --cpu 10 --memory 32 --disk 100
docker context show      # colima-rosetta: Colima switches the Docker context itself
```

The new profile has its own images; Docker pulls them on first use, so the first test run is slower. After a reboot or `colima stop`, start the profile again with `colima start rosetta`. To stop typing the profile name, add `export COLIMA_PROFILE=rosetta` to your shell profile: then `colima start`, `colima stop` and `colima status` use it. To go back to the old profile, `docker context use colima` (the profile named `default`).
