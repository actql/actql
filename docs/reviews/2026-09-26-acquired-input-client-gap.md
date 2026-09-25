# Acquired-input Client connection, 2026-09-26

The standard `@actql/node` Host still accepts only a source-free Values
Program. Its packed source-free smoke is a useful baseline, not evidence for
an acquired-input Local or Remote Run. The shared MoonBit owners below already
exist; the listed product connections do not.

| Product connection | Existing owner | Missing connection and owner |
| --- | --- | --- |
| Installed source view and current read authority | `program_check` and the DuckDB acquisition Host | `embedded-local.mjs` loads a check environment with no source views. Distribution must install a real catalog and grant from the chosen Local source; Program text must not authorize a local file read. |
| Logical request identity | `prepare_client_request_identity` in `run_publication_host` | `embedded-local.mjs` always supplies the fixed source-free input intent. Distribution must bind the checked source selection and preserve the same request ID across lookup, restart, and retry. |
| Checked compilation and Run evidence | `run_publication_host`, `run_publication` | `issue_prepared_client_values_compilation` and `sourceFreeValuesPlan` issue only the direct Values plan, empty initial input set, and no-source ObservationSet. Distribution owns a shared acquired-input issuer built from the checked Program and actual capture evidence, with independent Run/Result binding tests. |
| Physical capture and downstream computation | `prepare_trusted_capture_port`, `capture_verified_source`, `open_captured_dag`, and the installed DuckDB Host | `open_source_free_local_host` installs no acquisition capability and calls `open_prepared_source_free_client_run`. Distribution must bind the physical acquisition's verified observation to the checked source port, then run the existing DAG and publication strategy. |
| Remote mode of the same Program | Cloud-owned Run Host, common Run owner, native Site | Cloud submit currently calls `compileValues`; the native Site smoke also installs a fixed Values executor. Cloud must accept the same checked source and capture contract after the OSS shared issuer is available, without a TypeScript Run state machine. |

The first acceptance fixture should use a real acquired relation, a checked
subsequent computation, and a named Result with independent values and order.
Install packed artifacts in a clean directory, then run the same application
function and Program with only `connect()` options changed for embedded Local
and an actual HTTP Remote Host. Verify request reconciliation, attach, no
implicit recomputation on read, cancellation, and cleanup on both routes.

At `aee02f6b42a159357f57c41d7d143c3a50c8ff3c`,
`check:distribution-client` passed using the repository's pinned MoonBit
installation. Its 88 Node tests and native Client mTLS smoke cover the current
source-free and transport paths. The acquired-input acceptance above was not
run and remains the Distribution product task. The Cloud live-Site/default-
Worker/local-R2 combined gate remains a separate Cloud task.
