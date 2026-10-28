# Data flow of the first steps

How the manifest, the artifacts and the `join_and_filter_tsv` arguments flow through the first steps of the pipeline, after the manifest / argument /
resolver work of sessions 5 and 6. Status: the Groovy classes and their tests are done; the inputs (edge 0), LOCATE (1), the library resolver (2, in the workflow), SUMMARIZE + MERGE_LIBRARY_METRICS (3)
and FORMAT_MAPMYCELLS_ANNOTATIONS + BUILD_LIBRARY_CELL_METADATA (4) are wired; **all steps are wired**; `RESOLVE_AGGREGATION_MANIFEST` has been deleted (replaced by the Groovy `LibraryResolver`).

Legend: `[process]` runs in a container; `[exec]` is an `exec` process (`WRITE_TEXT_FILE`: runs in the head job, no container, no VM); `[groovy]` runs in the head job (no container, pure functions in `lib/`, unit tested); `==>` a published file.

Typing: the scripts use `nextflow.enable.types = true`. Channel items are records, not tuples: `Manifest(id, manifest)` from the initialisation, a `Library(id, analysis_id, position, mmc_model, dge, cell_metadata, mmc_annotations, args, files)` record
declared in `workflows/scrna-aggregation.nf` for each library, and the process inputs and outputs declared in `modules/local/*/main.nf`. Every record has a top-level `id` (the library id, or the analysis id for analysis-level steps) and no `meta` map: each process input lists the named fields it uses. Per-library pieces are joined with `join(by: 'id')`, not by tuple position.
`params` is a typed block in `main.nf` (types only); the default values are in `conf/params.config`, included by `nextflow.config`.

## The flow

```
  params.manifest (YAML: dgeDefaults + dges[dge, donor, filters, joins])           analysis id, params.mmc_model
        |
        v
 [groovy] PIPELINE_INITIALISATION  (fails here, before any cloud access)
        |  loadAggregationManifest(manifest)
        |    AggregationManifest.parse ........ strict schema, dgeDefaults projected deeply, duplicate DGEs, no line breaks
        |    JoinFilterArguments.build ........ (per entry, only to check that two files are not staged under one name)
        |  -> entries: [ {dge, donor, filters{col->spec}, joins[]} ... ]   (manifest order)
        |
        +-----------------------------------------------+
        |                                               |
        v                                               |
 [process] LOCATE_SCRNA_ARTIFACTS                       |
   in : [id=analysis, manifest]  (reads dge + donor; lists gs://)
   out: artifacts/<uei>.yaml, one per DGE               |
        |                                               |
        v                                               |
 [groovy] map { LibraryResolver.readArtifactTexts(dir) }  (in the workflow; the YAML text of each library)
        |   combined with the manifest entries in a head-job map that runs the [groovy] steps below (no process)
        |                                               |
        v                                               v
 [groovy] LibraryResolver.resolve(entries, artifacts, analysis id, [reference, mmcModel])        <- replaces RESOLVE_AGGREGATION_MANIFEST
        |   matches entry.dge = artifact.user_dge; library id = artifact uei
        |   per library: dge (the DGE the manifest names, of any type), cellMetadata, mmcModel, mmcAnnotations (NA if none),
        |                args + files (JoinFilterArguments.build: --set donor, --join..., filters; files = what to stage)
        |   checks: ids unique and != analysis id, one reference, one reduced GTF, same MapMyCells model,
        |           no staged file named like the task's own files
        |  -> libraries{ id -> record }, reducedGtf, reference
        |
        +--> LibraryResolver.summaryText -> [exec] WRITE_RESOLVED_SUMMARY -> <analysis>.resolved_libraries.txt ==> pipeline_info/   (plain text for people; nothing reads it back)
        |
        +--> flatMap (toLibraries) -> one Library record per library: id, meta(id=library, analysis_id, mmc_model), dge, cell_metadata, mmc_annotations (null for none), args (List), files (List)
        |
        +--> per library (ch_libraries items; the pieces are joined on the library id)
               |
               +--> [process] SUMMARIZE_SCRNA_EXPERIMENTS       in: [id=lib, artifacts/<lib>.yaml] (libraries combined with the artifacts directory; the YAML is <library id>.yaml in it)
               |                                                 -> <lib>.library_metrics.txt (work directory only), tearsheet ==> tearsheets/
               |                  all libraries, in manifest order (position, from a join with the libraries; collect() then toSorted) -> [process] MERGE_LIBRARY_METRICS -> <analysis>.library_metrics.txt ==> flat in outdir
               |
               +--> [process] FORMAT_MAPMYCELLS_ANNOTATIONS     only if mmc_annotations is not null (ext.args: --column-prefix <model>_ [--level params.mmc_level])
               |                in: [id=lib, mmcAnnotations csv, mmc_model] -> <lib>.mmc.tsv (not published), cell_type_column (string)
               |                all columns -> [groovy] LibraryResolver.checkCellTypeColumn(ids, columns) (fails if they differ)
               |                            -> cell type column (value, '' for none; used by DONOR_CELL_TYPE_REPORT and the metacells)
               |
               +--> [process] BUILD_LIBRARY_CELL_METADATA   (work directory only)                            [done: takes --args-file]
                                in : cellMetadata, <lib>.mmc.tsv (or null: libraries joined with the TSVs with remainder: true), args (List), files (staged by base name, or [])
                                cmd: printf the args, one per line (single-quoted; none: a zero-byte file) > <lib>.join_and_filter_args.txt
                                     join_and_filter_tsv --input <cmd.tsv> --set-first --set PREFIX <lib> [--join <lib>.mmc.tsv cell_barcode cell_id]
                                       --args-file <lib>.join_and_filter_args.txt
                                out: <lib>.joined_filtered_cell_metadata.txt
               |
               +--> [process] BUILD_LIBRARY_H5AD   (built joined with libraries on id, for the manifest DGE; the reduced GTF from the resolver; 6 GB default)
               |                in : id, dge, cell_metadata (= <lib>.joined_filtered_cell_metadata.txt), reduced_gtf
               |                cmd: build_library_h5ad --dge --cell-metadata --reduced-gtf --output h5ad/<lib>.h5ad
               |                out: h5ad/<lib>.h5ad ==> h5ad/   (X = raw counts, obs = cell metadata indexed <lib>_<barcode> with CELL_BARCODE (ext.args --uppercase-column cell_barcode), var = gene IDs + gene_symbol)
               |
               +--> ONE sorted list of the built libraries (id, analysis_id, position, cell metadata, DGE = the manifest DGE), in manifest order (position)
                        |--> [process] MERGE_CELL_METADATA (alias of MERGE_LIBRARY_METADATA; --index-col PREFIX --index-col cell_barcode) -> <analysis>.cell_metadata.txt ==> flat in outdir
                        |--> [process] MAKE_TRIPLET_DGE (prefixes, DGEs, barcode lists in that order; reduced GTF from the resolver; 15 GB)
                                  -> matrix.mtx.gz, barcodes.tsv.gz, features.tsv.gz ==> flat in outdir      [done: edge 5]
                        |
                        |  only if resolver.hasDonors (every library has a manifest donor or a village in its artifacts; a mix fails in the resolver)
                        |--> [process] DONOR_METACELLS (alias of MAKE_METACELLS_FROM_TRIPLET_DGE, group by donor) -> <analysis>.donors.metacells.txt.gz ==> flat
                        |  and only if there is a cell type column (some library has MapMyCells results)
                        |--> [process] DONOR_CELL_TYPE_METACELLS (group by donor and the cell type column) -> <analysis>.donor_cell_type.metacells.txt.gz ==> flat
                        |--> [process] DONOR_CELL_TYPE_REPORT (merged cell metadata, cell type column) -> <analysis>.donor_cell_type.txt ==> flat   [done: edge 6]
                        |
                        |  only if run_qc (off by default); one flatMap gated on run_qc
                        +--> [process] AGGREGATION_QC (merged cell metadata, <analysis>.library_metrics.txt; optional: donor file from LibraryResolver.commonDonorFile, cell type column, conditions file or column, core cell types)
                                  cmd: aggregation_qc --cell-metadata --library-metrics --analysis-id [--donor-file] [--cell-type-column] [--conditions-file | --condition-column] [--core-cell-types]
                                  out: qc_pdfs (*.pdf) and qc_donor_qc (<analysis>.donor_qc.txt, optional) ==> qc_plots/ in outdir
```

## How the arguments reached `join_and_filter_tsv`, before and after

| | Before (prototype script / RESOLVE) | After |
|---|---|---|
| Who reads the manifest | `locate_scRNA_artifacts` (dge, donor) and `resolve_aggregation_manifest` (python, after LOCATE) | the workflow, once, in `PIPELINE_INITIALISATION` (Groovy); LOCATE still reads dge + donor |
| `dgeDefaults` | shallow: an entry's `filters` replaced the default `filters` | deep, as in the original Zamboni workflow: columns and keys merge, the entry wins; default `joins` only if the entry has none |
| Unknown keys, `libraryId`, `donor` in defaults, list-form `filters` | some ignored or accepted | rejected with a message naming the DGE entry |
| Where errors appear | after LOCATE listed `gs://` | manifest-only errors before LOCATE; artifact errors right after it |
| Donor | read from the artifact (copied there from the manifest by LOCATE) | read from the manifest entry |
| File paths in the arguments | original paths | staged base names; the originals go in `files` for Nextflow to stage; two files with one base name are rejected |
| How the arguments reach the tool | `<lib>.join_and_filter_args.txt` written by RESOLVE, expanded by the shell in the prototype | the same file, written by the BUILD_LIBRARY_CELL_METADATA task from its `args` list (each argument single-quoted for `printf`), read by `join_and_filter_tsv --args-file` (no `ext.args`; the tool reads the arguments from the file, not from the shell) |
| `libraries.tsv` | RESOLVE output with task-local paths | `LibraryResolver.resolve` result, kept as Groovy values in the channel; `LibraryResolver.summaryText` writes it as plain text to `<outdir>/pipeline_info/<analysis>.resolved_libraries.txt` for people |
| New checks | | same user_dge in two artifacts; libraries with MapMyCells results of different models (set `mmc_model`); staged files named like `<lib>.mmc.tsv`, the arguments file, the cell metadata or the output |

The software versions are written the same way: `WRITE_VERSIONS` (exec) writes `scrna-aggregation_software_versions.yml` to `pipeline_info/`. The old `topic: versions` channel is gone.
Publishing: `SCRNA_AGGREGATION` emits one channel per published file; the entry workflow in `main.nf` lists them in `publish:` and the `output { }` block says where each goes under `--outdir` (`outputDir` in `nextflow.config`, mode `publish_dir_mode`). Nothing else is published. There is no `publishDir` any more.

## Where to look when something looks wrong
- What did the YAML become? `<outdir>/pipeline_info/<analysis>.resolved_libraries.txt` (plain text: per library the DGE, cell metadata, MapMyCells result, extra files and arguments) and `<lib>.join_and_filter_args.txt` (the exact arguments, one per line; not
  published, the library's BUILD_LIBRARY_CELL_METADATA task writes it in its work directory).
- What did a task run? Its `.command.sh` (shows the `printf` that writes the args file and `--args-file`), and the args file next to it.
- Why was a manifest rejected? The message names the DGE entry, the key and the rule (`tests/manifest.function.nf.test` lists every rule). Files the manifest names that do not exist, or that this run's credentials cannot read, are all listed at once, before any process.
