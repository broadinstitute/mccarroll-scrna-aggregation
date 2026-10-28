#!/usr/bin/env bash
# Live check: runs the WHOLE pipeline on Google Batch (profile googlebatch, gs:// work dir and outdir) on tests/live_data/manifest.yaml,
# then checks the result. Not an nf-test: nf-test always passes a local -work-dir and Google Batch needs a gs:// one. It costs a little money.
#
#   export GOOGLE_PROJECT_ID=mccarroll-scrna-seq GOOGLE_LOCATION=us-central1
#   tests/google_cloud_batch_run/run.sh [gs://<bucket>/<path>]    # default: gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing
#
# Needs: nextflow, gcloud Application Default Credentials, gsutil, the baseline in tests/live_data/baseline (docs/testing.md).
# Writes <base>/work and <base>/out (the base is removed first for out/), downloads out/ to testing_google_cloud_batch_run/out (git-ignored).
# Checks (each prints PASS or FAIL; the exit status is the number of failures):
#   1. the published files equal the baseline (md5 of the decompressed content; the metacell header line is ignored)
#   1c. the QC step (--run_qc true): donor_qc.txt equals the baseline's (so the head job read the gs:// donor file) and the 8 PDFs exist, are not empty and start with %PDF
#   2. the top level of --outdir lists exactly the expected entries
#   3. exec processes (WRITE_*) ran in the head job, every other task on google-batch (Google Batch)
#   4. every task COMPLETED, and the tasks ran in the public quay.io/broadinstitute drop-seq images
# Then it prints a per-process table of the requested memory and the peak memory and run time, to tune conf/modules.config.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO"
BASE=${1:-gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing}
BASE=${BASE%/}
ANALYSIS=SMRI_V11.unfiltered
RUN=testing_google_cloud_batch_run
BASELINE=tests/live_data/baseline

[[ -n ${GOOGLE_PROJECT_ID:-} && -n ${GOOGLE_LOCATION:-} ]] || { echo "ERROR: export GOOGLE_PROJECT_ID and GOOGLE_LOCATION first (see the header of this script)" >&2; exit 2; }
[[ $BASE == gs://* ]] || { echo "ERROR: the base location must be a gs:// path" >&2; exit 2; }
[[ -d $BASELINE/artifacts ]] || { echo "ERROR: no baseline in $BASELINE (see docs/testing.md, Live tests)" >&2; exit 2; }
command -v gsutil >/dev/null || { echo "ERROR: gsutil not found on PATH" >&2; exit 2; }

rm -rf "$RUN"; mkdir -p "$RUN"
gsutil -q -m rm -r "$BASE/out" 2>/dev/null || true   # a fresh outdir, so stale files cannot pass the checks

echo "== nextflow run on Google Batch: project $GOOGLE_PROJECT_ID, $GOOGLE_LOCATION, work $BASE/work, outdir $BASE/out"
# </dev/null: Nextflow reads the terminal, and a background job that does so is suspended by the shell (state T) and never runs.
# -ansi-log true: Nextflow's colored output and progress display. Without a terminal on stdin (see above) Nextflow would otherwise
# switch to plain text.
nextflow run . -ansi-log true -profile googlebatch -c tests/google_cloud_batch_run/trace.config \
  -work-dir "$BASE/work" --outdir "$BASE/out" \
  --manifest tests/live_data/manifest.yaml --analysis_id "$ANALYSIS" --run_qc true < /dev/null 2>&1 | tee "$RUN/nextflow.log"
[[ ${PIPESTATUS[0]} -eq 0 ]] || { echo "FAIL: the pipeline run failed (see $RUN/nextflow.log)"; exit 1; }

echo "== downloading $BASE/out"
mkdir -p "$RUN/out"
gsutil -q -m cp -r "$BASE/out/*" "$RUN/out/" || { echo "FAIL: download of the outdir failed"; exit 1; }

failures=0
check() { # check <ok: 0|1> <description>
  if [[ $1 -eq 0 ]]; then echo "PASS: $2"; else echo "FAIL: $2"; failures=$((failures + 1)); fi
}
content_md5() { # md5 of the decompressed content (gzip -f passes plain files through); the metacell header line is dropped
  gzip -dc -f "$1" | grep -v '^#MakeMetacellsFromTripletDge' | md5 -q
}

# 1. published files equal the baseline
merged=("$ANALYSIS.library_metrics.txt" "$ANALYSIS.cell_metadata.txt" matrix.mtx.gz barcodes.tsv.gz features.tsv.gz
        "$ANALYSIS.donor_cell_type.txt" "$ANALYSIS.donors.metacells.txt.gz"
        "$ANALYSIS.donor_cell_type.metacells.txt.gz")
for f in "${merged[@]}"; do
  [[ -f $RUN/out/$f && -f $BASELINE/$f && $(content_md5 "$RUN/out/$f") == "$(content_md5 "$BASELINE/$f")" ]]
  check $? "$f equals the baseline"
done

# 1b. the h5ad file of each library equals the baseline's (md5 of the bytes: the file is binary, see docs/testing.md)
for f in "$BASELINE"/h5ad/*.h5ad; do
  [[ -f $RUN/out/h5ad/$(basename "$f") && $(md5 -q "$RUN/out/h5ad/$(basename "$f")") == "$(md5 -q "$f")" ]]
  check $? "h5ad/$(basename "$f") equals the baseline"
done

# 1c. the QC step: donor_qc.txt equals the baseline's (it exists only if the head job read the gs:// donor file); the PDFs cannot be diffed
qc_pdfs=()
for n in library_metrics filtered_library_metrics donor_summary donor_nuclei_counts cell_type_counts cell_type_median_UMIs cell_type_proportions donor_cell_type_distributions; do
  qc_pdfs+=("$ANALYSIS.$n.pdf")
done
[[ -f $RUN/out/$ANALYSIS.donor_qc.txt && -f $BASELINE/$ANALYSIS.donor_qc.txt && $(content_md5 "$RUN/out/$ANALYSIS.donor_qc.txt") == "$(content_md5 "$BASELINE/$ANALYSIS.donor_qc.txt")" ]]
check $? "$ANALYSIS.donor_qc.txt equals the baseline"
for f in "${qc_pdfs[@]}"; do
  [[ -s $RUN/out/$f && $(head -c 4 "$RUN/out/$f") == "%PDF" ]]
  check $? "$f exists, is not empty and starts with %PDF"
done

# 2. exact top-level listing
expected=$(printf '%s\n' "${merged[@]}" "$ANALYSIS.donor_qc.txt" "${qc_pdfs[@]}" artifacts tearsheets h5ad pipeline_info | sort)
actual=$(ls "$RUN/out" | sort)
[[ $expected == "$actual" ]]
check $? "the top level of --outdir is exactly the merged files, the QC files, artifacts/, tearsheets/, h5ad/ and pipeline_info/"
[[ $expected == "$actual" ]] || diff <(echo "$expected") <(echo "$actual")

# 3 and 4. the trace (tab separated, columns found by name). The trace has no executor field: a task submitted to Google Batch has a job id in
# native_id, a task run by the head job (an exec process) has '-'.
TRACE=$RUN/trace.txt
[[ -s $TRACE ]] || { echo "FAIL: no trace at $TRACE"; exit 1; }
col() { head -1 "$TRACE" | tr '\t' '\n' | grep -n -x "$1" | cut -d: -f1; }
cProc=$(col process); cExec=$(col native_id); cStat=$(col status); cCont=$(col container)
cMem=$(col memory); cRss=$(col peak_rss); cReal=$(col realtime)

bad=$(awk -F'\t' -v p="$cProc" -v e="$cExec" 'NR>1 { exec_proc = ($p ~ /(^|:)WRITE_/); if ((exec_proc && $e != "-") || (!exec_proc && $e == "-")) print $p ": " $e }' "$TRACE")
[[ -z $bad ]]; check $? "WRITE_* ran in the head job and every other task on google-batch"; [[ -z $bad ]] || echo "$bad"

bad=$(awk -F'\t' -v s="$cStat" 'NR>1 && $s != "COMPLETED"' "$TRACE")
[[ -z $bad ]]; check $? "every task COMPLETED"; [[ -z $bad ]] || echo "$bad"

bad=$(awk -F'\t' -v p="$cProc" -v c="$cCont" 'NR>1 && $p !~ /(^|:)WRITE_/ && $c !~ /^quay.io\/broadinstitute\/drop-seq_(python|java):/ { print $p ": " $c }' "$TRACE")
[[ -z $bad ]]; check $? "every Google Batch task ran in a public quay.io/broadinstitute drop-seq image"; [[ -z $bad ]] || echo "$bad"

echo
echo "== memory and time per task: process, requested memory, peak_rss, realtime (as Nextflow reports them)"
awk -F'\t' -v p="$cProc" -v m="$cMem" -v r="$cRss" -v t="$cReal" 'NR>1 { print $p "\t" $m "\t" $r "\t" $t }' "$TRACE" | sort | column -t -s "$(printf '\t')"
echo
echo "$failures check(s) failed. Trace: $TRACE. Log: $RUN/nextflow.log. Scratch to delete when done: $BASE/work and $BASE/out"
exit $failures
