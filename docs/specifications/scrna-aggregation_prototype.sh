#!/usr/bin/env bash
# MIT License
#
# Copyright 2026 Broad Institute
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Serial prototype of the scRNA aggregation workflow for Nextflow single cell pipeline outputs.  It reproduces the
# steps of ScRnaAggregationWorkflow (Zamboni), using locate_scRNA_artifacts to find the inputs.  Each step is a
# single command so that it can be tested on its own, and the script is the guide for the Nextflow implementation.
# Every tool is run in a docker container, the Python tools in drop-seq_python and the Java tools in drop-seq_java, both
# with the tag from --image-tag, so that the whole workflow is pinned to one version.  To test local code, build the
# images with the tag jn_test and use --image-tag jn_test.
# The script itself only calls those tools and reads the tab-separated samplesheet written by
# resolve_aggregation_manifest.  See scRNA_aggregation_plan.md in this directory.
#
# The containers read gs:// URLs with the application default credentials in ~/.config/gcloud (gcloud auth
# application-default login).  gs:// inputs are copied on the host with 'gcloud storage cp'.  gcloud rejects a core/project property that is a project number,
# so the project ID is set here.  Set CLOUDSDK_CORE_PROJECT in the environment to use another project.
set -euo pipefail
export CLOUDSDK_CORE_PROJECT=${CLOUDSDK_CORE_PROJECT:-bican-um1-mccarroll}

usage() {
  cat >&2 <<USAGE
Usage: $0 --manifest dges.yaml --analysis-id ID --out-dir DIR [--image-tag TAG] [options]

  --manifest FILE       Aggregation manifest, with the same schema as Zamboni's LaunchScRnaAggregation: 'dges' (each
                        with dge, and optionally donor, filters and joins) and 'dgeDefaults'.  See
                        resolve_aggregation_manifest --help.
  --analysis-id ID      Prefix of the output files.
  --out-dir DIR         Output directory.
  --tmp-dir DIR         Scratch directory.  Default: OUT_DIR/tmp.  The reduced GTF is only downloaded into it once.
  --image-tag TAG       Tag of the quay.io/broadinstitute/drop-seq_python and
                        quay.io/broadinstitute/drop-seq_java images.  Default: current
  --mmc-model MODEL     MapMyCells model (the mmc/<model> directory).  Default: the first one found.
  --mmc-level LEVEL     MapMyCells taxonomy level for the cell type.  Default: the top level of the taxonomy.
  --reference NAME      Reference name.  Skips the check that all libraries have the same reference.
  --java-memory MEM     Memory for the Java tools.  Default: 8g

Optional QC step, a donor QC table and PDFs of library, donor and cell type QC (aggregation_qc --help):
  --run-qc              Run it, at the end.  The options below are ignored without it.
  --qc-conditions-file FILE
                        Tab-separated file with a header and two columns, library and condition.  Every library
                        needs a condition.  Not with --qc-condition-column.
  --qc-condition-column COLUMN
                        Column of the cell metadata with the condition of the library (one value per library).
  --qc-core-cell-types FILE
                        Headerless file with the core cell types, one per line: the cell types that are consistently
                        present in the tissue, whatever the dissection, for a per-donor median UMI comparable between
                        donors.  The labels belong to the cell type column (MapMyCells model and level) of the run.
USAGE
  exit 1
}

MANIFEST= ANALYSIS_ID= OUT_DIR= TMP_DIR= IMAGE_TAG=current MMC_MODEL= MMC_LEVEL= REFERENCE= JAVA_MEMORY=8g
RUN_QC= QC_CONDITIONS_FILE= QC_CONDITION_COLUMN= QC_CORE_CELL_TYPES=
while [[ $# -gt 0 ]]; do
  if [[ $1 == --run-qc ]]; then
    RUN_QC=1
    shift
    continue
  fi
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --manifest) MANIFEST=$2 ;;
    --analysis-id) ANALYSIS_ID=$2 ;;
    --out-dir) OUT_DIR=$2 ;;
    --tmp-dir) TMP_DIR=$2 ;;
    --image-tag) IMAGE_TAG=$2 ;;
    --mmc-model) MMC_MODEL=$2 ;;
    --mmc-level) MMC_LEVEL=$2 ;;
    --reference) REFERENCE=$2 ;;
    --java-memory) JAVA_MEMORY=$2 ;;
    --qc-conditions-file) QC_CONDITIONS_FILE=$2 ;;
    --qc-condition-column) QC_CONDITION_COLUMN=$2 ;;
    --qc-core-cell-types) QC_CORE_CELL_TYPES=$2 ;;
    *) usage ;;
  esac
  shift 2
done
[[ -n $MANIFEST && -n $ANALYSIS_ID && -n $OUT_DIR ]] || usage
if [[ -n $QC_CONDITIONS_FILE && -n $QC_CONDITION_COLUMN ]]; then
  echo "ERROR: --qc-conditions-file and --qc-condition-column cannot be used together" >&2
  exit 1
fi
if [[ -z $RUN_QC && -n $QC_CONDITIONS_FILE$QC_CONDITION_COLUMN$QC_CORE_CELL_TYPES ]]; then
  echo "WARNING: the --qc-* options are ignored without --run-qc" >&2
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
# Run a command, echoing it first so that the log reads like the Zamboni workflow.log.
run() { log "RUN: $*"; "$@"; }
# Copy a local file or a gs:// URL to a local path.
fetch() {
  case $1 in
    gs://*) run gcloud storage cp "$1" "$2" ;;
    *) run cp "$1" "$2" ;;
  esac
}
has_column() { head -n 1 "$1" | tr '\t' '\n' | grep -qx -- "$2"; }

# ---------------------------------------------------------------------------------------------------------------
# 0. Create output and temporary directories
# ---------------------------------------------------------------------------------------------------------------
TMP_DIR=${TMP_DIR:-$OUT_DIR/tmp}
mkdir -p "$OUT_DIR" "$TMP_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
TMP_DIR=$(cd "$TMP_DIR" && pwd)
MANIFEST=$(cd "$(dirname "$MANIFEST")" && pwd)/$(basename "$MANIFEST")
PREFIX=$OUT_DIR/$ANALYSIS_ID

# Run a tool in a container.  The directories are mounted at the same paths as on the host, so that paths in files
# written by one tool are valid for the next.  The container runs as the current user, so that it does not write
# root-owned files.
PY_IMAGE=quay.io/broadinstitute/drop-seq_python:$IMAGE_TAG
JAVA_IMAGE=quay.io/broadinstitute/drop-seq_java:$IMAGE_TAG
in_container() {
  local image=$1
  shift
  log "RUN: [$image] $*"
  docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e GOOGLE_APPLICATION_CREDENTIALS=/gcloud/application_default_credentials.json \
    -e GOOGLE_CLOUD_PROJECT="$CLOUDSDK_CORE_PROJECT" -v "$HOME/.config/gcloud":/gcloud:ro \
    -v "$OUT_DIR":"$OUT_DIR" -v "$TMP_DIR":"$TMP_DIR" -v "$(dirname "$MANIFEST")":"$(dirname "$MANIFEST")":ro \
    -w "$OUT_DIR" "$image" "$@"
}
py() { in_container "$PY_IMAGE" "$@"; }
jv() { in_container "$JAVA_IMAGE" "$@"; }

# ---------------------------------------------------------------------------------------------------------------
# 1. Locate the artifacts of each library: one <uei>.yaml per library in ARTIFACT_DIR.  Then resolve the manifest
#    into a samplesheet, libraries.tsv, with one row per library: its DGE, cell metadata, MapMyCells model and
#    annotations, the reduced GTF, and a file with the join_and_filter_tsv arguments for its donor, joins and filters.
# ---------------------------------------------------------------------------------------------------------------
ARTIFACT_DIR=$OUT_DIR/artifacts
RESOLVED_DIR=$OUT_DIR/resolved_manifest
py locate_scRNA_artifacts --manifest "$MANIFEST" --output-dir "$ARTIFACT_DIR"
py resolve_aggregation_manifest --manifest "$MANIFEST" --artifacts-dir "$ARTIFACT_DIR" \
  --analysis-id "$ANALYSIS_ID" ${REFERENCE:+--reference "$REFERENCE"} ${MMC_MODEL:+--mmc-model "$MMC_MODEL"} \
  --output-dir "$RESOLVED_DIR"
LIBRARIES=() ARTIFACT_FILES=() DGES=() CELL_METADATA_FILES=() MMC_MODELS=() MMC_ANNOTATIONS=() ARGS_FILES=()
while IFS=$'\t' read -r library_id artifact_file dge cell_metadata mmc_model mmc_annotations reduced_gtf args_file; do
  LIBRARIES+=("$library_id")
  ARTIFACT_FILES+=("$artifact_file")
  DGES+=("$dge")
  CELL_METADATA_FILES+=("$cell_metadata")
  MMC_MODELS+=("$mmc_model")
  MMC_ANNOTATIONS+=("$mmc_annotations")
  ARGS_FILES+=("$args_file")
  REDUCED_GTF=$reduced_gtf  # the same for all of the libraries, as checked by resolve_aggregation_manifest
done < <(tail -n +2 "$RESOLVED_DIR/libraries.tsv")

# ---------------------------------------------------------------------------------------------------------------
# 2. Library metrics, one row per library (replaces R buildSummaryTable)
# ---------------------------------------------------------------------------------------------------------------
METRICS_FILES=()
for i in "${!LIBRARIES[@]}"; do
  library=${LIBRARIES[$i]}
  py summarize_scRNA_experiments --artifacts "${ARTIFACT_FILES[$i]}" \
    --summary "$ARTIFACT_DIR/$library.library_metrics.txt" --tearsheet-dir "$OUT_DIR/tearsheets"
  METRICS_FILES+=("$ARTIFACT_DIR/$library.library_metrics.txt")
done
py cat_tsvs --output "$PREFIX.library_metrics.txt" "${METRICS_FILES[@]}"

# ---------------------------------------------------------------------------------------------------------------
# 3. Cell metadata of each library: cmd.tsv, with PREFIX as the first column, and the MapMyCells results joined
#    on to the end if there are any (replaces the scPred join_and_filter_tsv step).  A donor in the manifest
#    overrides the donor column of cmd.tsv, which already has the donors of a village or a single donor library.
# ---------------------------------------------------------------------------------------------------------------
LOCAL_DGES=() LIBRARY_METADATA_FILES=()
CELL_TYPE_COLUMN=
for i in "${!LIBRARIES[@]}"; do
  library=${LIBRARIES[$i]}
  # join and filter arguments from the manifest, one per line
  manifest_args=()
  while IFS= read -r arg; do manifest_args+=("$arg"); done < "${ARGS_FILES[$i]}"
  lib_tmp=$TMP_DIR/$library
  mkdir -p "$lib_tmp"
  fetch "${CELL_METADATA_FILES[$i]}" "$lib_tmp/cmd.tsv"
  fetch "${DGES[$i]}" "$lib_tmp/$(basename "${DGES[$i]}")"
  LOCAL_DGES+=("$lib_tmp/$(basename "${DGES[$i]}")")
  join_args=()  # the MapMyCells join is first, so that the manifest joins and filters can use its columns
  if [[ ${MMC_ANNOTATIONS[$i]} != NA ]]; then
    fetch "${MMC_ANNOTATIONS[$i]}" "$lib_tmp/mmc.csv"
    py convert_mmc_csv --input "$lib_tmp/mmc.csv" --column-prefix "${MMC_MODELS[$i]}_" \
      ${MMC_LEVEL:+--level "$MMC_LEVEL"} --cell-type-column-output "$lib_tmp/cell_type_column.txt" \
      --output "$lib_tmp/mmc.tsv"
    this_column=$(<"$lib_tmp/cell_type_column.txt")
    if [[ -n $CELL_TYPE_COLUMN && $CELL_TYPE_COLUMN != "$this_column" ]]; then
      log "ERROR: $library has cell type column $this_column but earlier libraries have $CELL_TYPE_COLUMN"
      exit 1
    fi
    CELL_TYPE_COLUMN=$this_column
    join_args=(--join "$lib_tmp/mmc.tsv" cell_barcode cell_id)
  else
    log "WARNING: no MapMyCells result for $library"
  fi
  py join_and_filter_tsv --input "$lib_tmp/cmd.tsv" \
    --output "$OUT_DIR/$library.joined_filtered_cell_metadata.txt" \
    --set-first --set PREFIX "$library" ${join_args[@]+"${join_args[@]}"} ${manifest_args[@]+"${manifest_args[@]}"}
  LIBRARY_METADATA_FILES+=("$OUT_DIR/$library.joined_filtered_cell_metadata.txt")
done
# The cell type column chosen above (the same for all libraries), used by the donor / cell type report and metacells.
# Written only if there are MapMyCells results, so its absence means there is no cell type column.
if [[ -n $CELL_TYPE_COLUMN ]]; then
  echo "$CELL_TYPE_COLUMN" > "$PREFIX.cell_type_column.txt"
fi

# ---------------------------------------------------------------------------------------------------------------
# 4. Write the MakeTripletDge manifest
# ---------------------------------------------------------------------------------------------------------------
TRIPLET_MANIFEST=$PREFIX.make_triplet_dge.yaml
echo "dges:" > "$TRIPLET_MANIFEST"
for i in "${!LIBRARIES[@]}"; do
  cat >> "$TRIPLET_MANIFEST" <<MANIFEST_ENTRY
- dge: ${LOCAL_DGES[$i]}
  prefix: ${LIBRARIES[$i]}
  barcode_list: $OUT_DIR/${LIBRARIES[$i]}.joined_filtered_cell_metadata.txt
  barcode_column: cell_barcode
MANIFEST_ENTRY
done

# ---------------------------------------------------------------------------------------------------------------
# 5. Combine expression data across libraries
# ---------------------------------------------------------------------------------------------------------------
# The reduced GTF is in the reference directory of the libraries.  It is large, so it is only downloaded if it is
# not already in TMP_DIR.
reduced_gtf_local=$TMP_DIR/$(basename "$REDUCED_GTF")
[[ -s $reduced_gtf_local ]] || fetch "$REDUCED_GTF" "$reduced_gtf_local"
jv MakeTripletDge -m "$JAVA_MEMORY" TMP_DIR="$TMP_DIR" VALIDATION_STRINGENCY=SILENT \
  OUTPUT="$OUT_DIR/matrix.mtx.gz" OUTPUT_CELLS="$OUT_DIR/barcodes.tsv.gz" OUTPUT_FEATURES="$OUT_DIR/features.tsv.gz" \
  MANIFEST="$TRIPLET_MANIFEST" REDUCED_GTF="$reduced_gtf_local"

# ---------------------------------------------------------------------------------------------------------------
# 5b. h5ad file of each library, in OUT_DIR/h5ad: the counts of its DGE for the cells of its cell metadata, with the
#     cell metadata as obs (indexed by <library>_<cell barcode>, so that the files can be combined) and the genes of
#     the reduced GTF as var (indexed by gene ID, with the gene symbol as a column).  The cell_barcode column of obs is written as
#     CELL_BARCODE, which the readers of these files require
# ---------------------------------------------------------------------------------------------------------------
mkdir -p "$OUT_DIR/h5ad"
for i in "${!LIBRARIES[@]}"; do
  py build_library_h5ad --dge "${LOCAL_DGES[$i]}" --cell-metadata "${LIBRARY_METADATA_FILES[$i]}" \
    --reduced-gtf "$reduced_gtf_local" --uppercase-column cell_barcode --output "$OUT_DIR/h5ad/${LIBRARIES[$i]}.h5ad"
done

# ---------------------------------------------------------------------------------------------------------------
# 6. Combine the cell metadata of the libraries
# ---------------------------------------------------------------------------------------------------------------
CELL_METADATA=$PREFIX.cell_metadata.txt
py cat_tsvs --output "$CELL_METADATA" --index-col PREFIX --index-col cell_barcode \
  "${LIBRARY_METADATA_FILES[@]}"

# Donors, and so everything below, are only available if the DGEs were assigned to donors.
if ! has_column "$CELL_METADATA" donor; then
  log "WARNING: no donor column in $CELL_METADATA, so there are no donor reports or metacells"
else
  # -------------------------------------------------------------------------------------------------------------
  # 7. Donor / cell type report
  # -------------------------------------------------------------------------------------------------------------
  if [[ -n $CELL_TYPE_COLUMN ]]; then
    py donor_cell_type_report --input "$CELL_METADATA" --output "$PREFIX.donor_cell_type.txt" \
      --cell-type-column "$CELL_TYPE_COLUMN"
  fi

  # -------------------------------------------------------------------------------------------------------------
  # 8. Aggregate expression by donor
  # -------------------------------------------------------------------------------------------------------------
  metacell_args=(MATRIX="$OUT_DIR/matrix.mtx.gz" FEATURES="$OUT_DIR/features.tsv.gz" BARCODES="$OUT_DIR/barcodes.tsv.gz"
                 MAPPING="$CELL_METADATA" CELL_BARCODE_COLUMN=cell_barcode TMP_DIR="$TMP_DIR" VALIDATION_STRINGENCY=SILENT)
  jv MakeMetacellsFromTripletDge -m "$JAVA_MEMORY" "${metacell_args[@]}" \
    OUTPUT="$PREFIX.donors.metacells.txt.gz" GROUP_COLUMNS=donor

  # -------------------------------------------------------------------------------------------------------------
  # 9. Aggregate expression by donor and cell type
  # -------------------------------------------------------------------------------------------------------------
  if [[ -n $CELL_TYPE_COLUMN ]]; then
    jv MakeMetacellsFromTripletDge -m "$JAVA_MEMORY" "${metacell_args[@]}" \
      OUTPUT="$PREFIX.donor_cell_type.metacells.txt.gz" GROUP_COLUMNS=donor GROUP_COLUMNS="$CELL_TYPE_COLUMN"
  else
    log "WARNING: no MapMyCells results, so no donor by cell type metacells"
  fi
fi

# ---------------------------------------------------------------------------------------------------------------
# 10. Optional QC: <analysis>.donor_qc.txt and PDFs of library, donor and cell type QC, written to OUT_DIR.
#     The expected donors are the donor_file of each library's artifact YAML (the donorFile of its village), which
#     is passed only if every library has one: aggregation_qc skips the donor outputs without it, or if the libraries'
#     donor files differ.  Files given on the command line are copied to TMP_DIR, which the container can read.
# ---------------------------------------------------------------------------------------------------------------
if [[ -n $RUN_QC ]]; then
  qc_dir=$TMP_DIR/qc
  mkdir -p "$qc_dir"
  qc_args=()
  donor_files=() all_have_donor_file=1
  for i in "${!LIBRARIES[@]}"; do
    donor_file=$(sed -n 's/^  donor_file: //p' "${ARTIFACT_FILES[$i]}")
    if [[ -z $donor_file || $donor_file == NA ]]; then
      all_have_donor_file=
    else
      fetch "$donor_file" "$qc_dir/${LIBRARIES[$i]}.donors.txt"
      donor_files+=("$qc_dir/${LIBRARIES[$i]}.donors.txt")
    fi
  done
  if [[ -n $all_have_donor_file ]]; then
    qc_args+=(--donor-file "${donor_files[@]}")
  else
    log "WARNING: not every library has a donor file, so there will be no donor QC"
  fi
  [[ -z $CELL_TYPE_COLUMN ]] || qc_args+=(--cell-type-column "$CELL_TYPE_COLUMN")
  if [[ -n $QC_CONDITIONS_FILE ]]; then
    fetch "$QC_CONDITIONS_FILE" "$qc_dir/conditions.txt"
    qc_args+=(--conditions-file "$qc_dir/conditions.txt")
  fi
  [[ -z $QC_CONDITION_COLUMN ]] || qc_args+=(--condition-column "$QC_CONDITION_COLUMN")
  if [[ -n $QC_CORE_CELL_TYPES ]]; then
    fetch "$QC_CORE_CELL_TYPES" "$qc_dir/core_cell_types.txt"
    qc_args+=(--core-cell-types "$qc_dir/core_cell_types.txt")
  fi
  py aggregation_qc --cell-metadata "$CELL_METADATA" --library-metrics "$PREFIX.library_metrics.txt" \
    --analysis-id "$ANALYSIS_ID" --output-dir "$OUT_DIR" "${qc_args[@]}"
fi

log "Done: $OUT_DIR"
