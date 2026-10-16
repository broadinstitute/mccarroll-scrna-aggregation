# Data flow of the first steps

How the manifest, the artifacts and the `join_and_filter_tsv` arguments flow through the first steps of the pipeline, after the manifest / argument /
resolver work of session 5. Status: the Groovy classes and their tests are done; the inputs (edge 0), LOCATE (edge 1) and RESOLVE_LIBRARIES (edge 2) are wired; **wiring the rest into `workflows/scrna-aggregation.nf` and deleting
`RESOLVE_AGGREGATION_MANIFEST` are still to do** (marked `[todo]`); `BUILD_LIBRARY_CELL_METADATA` already takes the arguments file.

Legend: `[process]` runs in a container; `[groovy]` runs in the head job (no container, pure functions in `lib/`, unit tested); `==>` a published file.

## The flow

```
  params.manifest (YAML: dgeDefaults + dges[dge, donor, filters, joins])           analysis id, params.reference, params.mmc_model
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
        |   passed as val to [process] RESOLVE_LIBRARIES, whose script block runs the [groovy] steps below
        |                                               |
        v                                               v
 [groovy] LibraryResolver.resolve(entries, artifacts, analysis id, [reference, mmcModel])        <- replaces RESOLVE_AGGREGATION_MANIFEST
        |   matches entry.dge = artifact.user_dge; library id = artifact uei
        |   per library: dge (donor DGE, else selected cells), cellMetadata, mmcModel, mmcAnnotations (NA if none),
        |                args + files (JoinFilterArguments.build: --set donor, --join..., filters; files = what to stage)
        |   checks: ids unique and != analysis id, one reference, one reduced GTF, same MapMyCells model,
        |           no staged file named like the task's own files
        |  -> libraries{ id -> record }, reducedGtf, reference
        |
        +--> LibraryResolver.summaryText -> <analysis>.resolved_libraries.tsv  (in the RESOLVE_LIBRARIES work directory; not published)
                |   splitCsv -> one item per library: [meta(id=library, analysis_id, mmc_model), row]   (ch_libraries; unused so far)
        |
        +--> per library (the library record becomes meta + channel items)
               |
               +--> JoinFilterArguments.toArgsFileText(args) (a file in the work directory)     [todo: collectFile; not published]
               |
               +--> [process] SUMMARIZE_SCRNA_EXPERIMENTS       in: [meta(lib), artifacts/<lib>.yaml] -> <lib>.library_metrics.txt
               |
               +--> [process] FORMAT_MAPMYCELLS_ANNOTATIONS     only if mmcAnnotations != NA
               |                in: [meta(lib), mmcAnnotations csv] -> <lib>.mmc.tsv, cell_type_column (string)
               |
               +--> [process] BUILD_LIBRARY_CELL_METADATA                                          [done: takes --args-file]
                                in : cellMetadata, <lib>.mmc.tsv (or none), files (staged by base name), <lib>.join_and_filter_args.txt
                                cmd: join_and_filter_tsv --input <cmd.tsv> --set-first --set PREFIX <lib> [--join <lib>.mmc.tsv cell_barcode cell_id]
                                       --args-file <lib>.join_and_filter_args.txt
                                out: <lib>.joined_filtered_cell_metadata.txt
        ... then MAKE_TRIPLET_DGE, MERGE_LIBRARY_METADATA, DONOR_CELL_TYPE_REPORT, MAKE_METACELLS_FROM_TRIPLET_DGE (unchanged)
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
| `libraries.tsv` | RESOLVE output with task-local paths | `LibraryResolver.resolve` result, written by RESOLVE_LIBRARIES as `<analysis>.resolved_libraries.tsv` in its work directory (not published) with the arguments file name instead of a path |
| New checks | | same user_dge in two artifacts; libraries with MapMyCells results of different models (set `mmc_model`); staged files named like `<lib>.mmc.tsv`, the arguments file, the cell metadata or the output |

## Where to look when something looks wrong
- What did the YAML become? `<analysis>.resolved_libraries.tsv` (one row per library, in the RESOLVE_LIBRARIES task directory; not published) and `<lib>.join_and_filter_args.txt` (the exact arguments, one per line; not
  published, it is the staged input in the work directory of the library's BUILD_LIBRARY_CELL_METADATA task).
- What did a task run? Its `.command.sh` (shows `--args-file`), and the args file staged next to it.
- Why was a manifest rejected? The message names the DGE entry, the key and the rule (`tests/manifest.function.nf.test` lists every rule).
