# Data flow of the first steps

How the manifest, the artifacts and the `join_and_filter_tsv` arguments flow through the first steps of the pipeline, after the manifest / argument /
resolver work of sessions 5 and 6. Status: the Groovy classes and their tests are done; the inputs (edge 0), LOCATE (1), the library resolver (2, in the workflow), SUMMARIZE + MERGE_LIBRARY_METRICS (3)
and FORMAT_MAPMYCELLS_ANNOTATIONS + BUILD_LIBRARY_CELL_METADATA (4) are wired; **all steps are wired**; `RESOLVE_AGGREGATION_MANIFEST` has been deleted (replaced by the Groovy `LibraryResolver`).

Legend: `[process]` runs in a container; `[exec]` is an `exec` process (`WRITE_TEXT_FILE`: runs in the head job, no container, no VM); `[groovy]` runs in the head job (no container, pure functions in `lib/`, unit tested); `==>` a published file.

Typing: the scripts use `nextflow.enable.types = true`. Channel items are records, not tuples: `Manifest(meta, manifest)` from the initialisation, a `Library(id, meta, dge, cell_metadata, mmc_annotations, args, files)` record
declared in `workflows/scrna-aggregation.nf` for each library, and the process inputs and outputs listed in [testing.md](testing.md). Per-library pieces are joined with `join(by: 'id')`, not by tuple position.
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
   in : [meta(id=analysis), manifest]  (reads dge + donor; lists gs://)
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
        +--> flatMap (toLibraries) -> one Library record per library: id, meta(id=library, analysis_id, mmc_model), dge, cell_metadata, mmc_annotations, args (List), files (List)
        |
        +--> per library (ch_libraries items; the pieces are joined on the library id)
               |
               +--> [exec] WRITE_ARGS_FILE { JoinFilterArguments.toArgsFileText(library.args) } -> <lib>.join_and_filter_args.txt   (work directory only, not published)
               |
               +--> [process] SUMMARIZE_SCRNA_EXPERIMENTS       in: [meta(lib), artifacts/<lib>.yaml] (YAML picked from the artifacts directory by file name = library id)
               |                                                 -> <lib>.library_metrics.txt (work directory only), tearsheet ==> tearsheets/
               |                  all libraries, in manifest order (meta.position; collect() then toSorted) -> [process] MERGE_LIBRARY_METRICS -> <analysis>.library_metrics.txt ==> flat in outdir
               |
               +--> [process] FORMAT_MAPMYCELLS_ANNOTATIONS     only if mmcAnnotations != NA (ext.args: --column-prefix <model>_ [--level params.mmc_level])
               |                in: [meta(lib), mmcAnnotations csv] -> <lib>.mmc.tsv (not published), cell_type_column (string)
               |                all columns -> [groovy] LibraryResolver.checkCellTypeColumn(ids, columns) (fails if they differ)
               |                            -> cell type column (value, '' for none; used by DONOR_CELL_TYPE_REPORT and the metacells)
               |
               +--> [process] BUILD_LIBRARY_CELL_METADATA   (work directory only)                            [done: takes --args-file]
                                in : cellMetadata, <lib>.mmc.tsv (or []), <lib>.join_and_filter_args.txt, files (staged by base name, or [])
                                cmd: join_and_filter_tsv --input <cmd.tsv> --set-first --set PREFIX <lib> [--join <lib>.mmc.tsv cell_barcode cell_id]
                                       --args-file <lib>.join_and_filter_args.txt
                                out: <lib>.joined_filtered_cell_metadata.txt
               |
               +--> ONE sorted list of the built libraries (id, meta, cell metadata, DGE = the manifest DGE), in manifest order (meta.position)
                        |--> [process] MERGE_CELL_METADATA (alias of MERGE_LIBRARY_METADATA; --index-col PREFIX --index-col cell_barcode) -> <analysis>.cell_metadata.txt ==> flat in outdir
                        |--> [process] MAKE_TRIPLET_DGE (prefixes, DGEs, barcode lists in that order; reduced GTF from the resolver; 15 GB)
                                  -> matrix.mtx.gz, barcodes.tsv.gz, features.tsv.gz ==> flat in outdir      [done: edge 5]
                        |
                        |  only if resolver.hasDonors (every library has a manifest donor or a village in its artifacts; a mix fails in the resolver)
                        |--> [process] DONOR_METACELLS (alias of MAKE_METACELLS_FROM_TRIPLET_DGE, group by donor) -> <analysis>.donors.metacells.txt.gz ==> flat
                        |  and only if there is a cell type column (some library has MapMyCells results)
                        |--> [process] DONOR_CELL_TYPE_METACELLS (group by donor and the cell type column) -> <analysis>.donor_cell_type.metacells.txt.gz ==> flat
                        |--> [process] DONOR_CELL_TYPE_REPORT (merged cell metadata, cell type column) -> <analysis>.donor_cell_type.txt ==> flat   [done: edge 6]
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
| How the arguments reach the tool | `<lib>.join_and_filter_args.txt` written by RESOLVE, expanded by the shell in the prototype | the same file, written by the workflow, read by `join_and_filter_tsv --args-file` (no `ext.args`, no shell quoting) |
| `libraries.tsv` | RESOLVE output with task-local paths | `LibraryResolver.resolve` result, kept as Groovy values in the channel; `LibraryResolver.summaryText` writes it as plain text to `<outdir>/pipeline_info/<analysis>.resolved_libraries.txt` for people |
| New checks | | same user_dge in two artifacts; libraries with MapMyCells results of different models (set `mmc_model`); staged files named like `<lib>.mmc.tsv`, the arguments file, the cell metadata or the output |

The software versions are written the same way: `WRITE_VERSIONS` (exec) writes `scrna-aggregation_software_versions.yml` to `pipeline_info/`. The old `topic: versions` channel is gone.
Publishing: `SCRNA_AGGREGATION` emits one channel per published file; the entry workflow in `main.nf` lists them in `publish:` and the `output { }` block says where each goes under `--outdir` (`outputDir` in `nextflow.config`, mode `publish_dir_mode`). Nothing else is published. There is no `publishDir` any more.

## Where to look when something looks wrong
- What did the YAML become? `<outdir>/pipeline_info/<analysis>.resolved_libraries.txt` (plain text: per library the DGE, cell metadata, MapMyCells result, extra files and arguments) and `<lib>.join_and_filter_args.txt` (the exact arguments, one per line; not
  published, it is the staged input in the work directory of the library's BUILD_LIBRARY_CELL_METADATA task).
- What did a task run? Its `.command.sh` (shows `--args-file`), and the args file staged next to it.
- Why was a manifest rejected? The message names the DGE entry, the key and the rule (`tests/manifest.function.nf.test` lists every rule).
