# Retained check-only prefix

Base: main `d63c620d6f633d715d4e2a9cedbb0591bfb6dcb4`.
B implements the delegated finite common Stage/check-context seam for #1506.
This is not a new checker, evaluator, wire contract or publication permission.

The existing generated prefix experiment failed at
`Admission.Structure(EmptyDeclarations, stages[0].results)` before reaching the
common pipeline checker. Its source and receipts remain in #1506's
`p1-carrier-prefix-boundary.json`; they are not successful prefix evidence.

An opaque generated `stage_syntax.Prefix` owns the original Cursor and Stages.
Earlier Stages keep strict declarations and real Result/import definitions.
Only the last Stage remains open, without Results/Effects/table-write roots;
root exports must be empty. `admit_generated_source` and authored parse retain
complete-Program admission unchanged. No Prefix-to-Program conversion exists.

`stage_parameters.prepare_prefix` retains that exact owner and declarations.
The existing `stage_results.check_local_program` loop checks all pipelines,
imports and source-bound operation slots, retaining typed topology and unresolved
publication debts. Catalog and local attachment use their existing owners.
`prepare_local_program` and `wire_results` explicitly reject a Prefix source.
The legacy `program(source)` accessor is complete-source-only; mixed static
callers use `complete_program(source)`, which returns None for prefixes.

Independent controls verify nullable object capture, both imports, source Cursor,
projection and unresolved order; malformed unused types and required input order
remain refusals. Actual focused results, Catalog controls and interfaces remain
pending. Frontend lowering, Host/Local/HTTPS, four Carrier completion and all
backend execution are not established by this common API unit.
