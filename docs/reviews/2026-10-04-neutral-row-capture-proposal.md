# Proposal: provider-neutral row capture for installed SaaS sources

Historical baseline: the Salesforce Read execution/capture path described below
is superseded by [the completed Read migration](2026-10-04-salesforce-neutral-read.md).
Its retired files and exports are an inventory of the earlier implementation,
not current entry points. Salesforce Effect and overall connector-authoring
completion remain separate.


Connection point for the connector author foundation (S2), published for
review before implementation because it touches the common capture owner.
Base: #298. Consumers: the GitHub Issue read (#301, #312) and the Salesforce
Read migration.

## 1. The constraint that forces a decision

A captured source is `@query.CapturedInputSource`
(`src/execution_query/captured_source.mbt`). It is built only by
`@query.prepare_trusted_capture_port` + `capture_verified_source`, from a
`CompletedOutput` that the selected acquisition attempt produced. Every
current builder is provider-typed: Salesforce, DuckDB broad/native, mock.
None takes already-checked rows.

Salesforce reaches capture only because its provider packages
(`connectors/salesforce/catalog`, `connectors/salesforce/host`) are compiled
into the common runtime through `src/client_salesforce_host` and 25
`clientProgramSalesforce*` exports. A connector whose provider MoonBit is a
separate bundle (the GitHub bridge, or any future author) cannot pass typed
MoonBit values to the common runtime: the two bundles do not share type
instances. Copying the Salesforce pattern for each provider would put every
provider into the common runtime, which the author interface must avoid.

## 2. Proposed contract

Rows cross from the provider driver to the common runtime as a neutral typed
wire, and the common runtime admits them against the declared view.

1. **Declared view (static contract).** The connector publishes, per source
   view: `source_ref`, Resource, ordered fields with value contracts and
   nullability, `view_cid`, carrier schema and data policy. This is the same
   content Salesforce already publishes into the Check Environment
   (`connector_catalogs`, `source_views`, schema snapshot and capability
   members), produced from a connector-owned declaration instead of
   Salesforce types.
2. **Row wire (runtime evidence).** A page is UTF-8 JSON: an array of rows,
   each an object keyed by the declared field names. A missing key is a
   refusal; `null` is admitted only for a nullable field. The page also
   carries its `useCid` and response digest for evidence. Provider meaning
   (pagination, PR exclusion, field mapping) stays in the provider bundle;
   the wire has no provider-specific shape.
3. **Common admission.** A new top-level common package, provisionally
   `src/client_row_source_host` (no `connectors/*` dependency; same layer as
   `client_local_host`), exported from `connectors_builtin_node` as
   provider-neutral `clientProgramRowSource*` entries:

   | Entry | Role | Existing owners it calls |
   | --- | --- | --- |
   | `prepare_row_source_acquisition(requirement, view, contracts, registration, limits)` | resolve `source_ref` to the declared view, bind and choose the candidate, prepare the evidence context | `admit_query_evidence_contracts`, `prepare_capability_registry`, `bind_acquisition_candidate`, `choose_acquisition_candidate`, `query_requirement_source_evidence_members/_facts` |
   | `start_row_source_attempt(acquisition, nonce, verify)` | register the issuer and reserve the selected attempt | `register_query_evidence_issuer`, `reserve_selected_query_evidence_attempt` |
   | `accept_row_source_page(run, page_json, use_cid, response_sha256)` | admit each row value against the declared field contract; bounded | `@value_admission.admit`, `@execution.append_admitted_input` |
   | `finish_row_source_attempt` / `abort_row_source_attempt` | close admission; abort releases custody | `finish_admitted_input` |
   | `capture_row_source(run)` | residual, completed output, retention, evidence capture, captured source | `bind_query_receipt`, `execute_query_receipt_guarded`, `completed_output`, `measure_query_retention`, `issue_query_evidence`, `capture_query_evidence`, `prepare_trusted_capture_port`, `capture_verified_source` |
   | `issue_row_source_evidence(...)` | source evidence while the read is currently authorized | `admit_completed_source_input_logical`, `seal_run_evidence_value` |

   The call order and custody are exactly those of the Salesforce broad
   attempt (`src/connectors/salesforce/host/broad_evidence.mbt`), minus the
   Salesforce catalog calls. The registration name and revision come from the
   installed declaration and are verified by the Host (#298), not trusted.
4. **What stays out.** No new scheduler, ledger or capture owner. Completion
   is still decided by the common attempt: a stopped driver (rate limit,
   refused link, ceiling) aborts the attempt and nothing is captured.

## 3. Migration consequence

`src/client_salesforce_host` and the Salesforce broad attempt become the
first users of this package: their generic steps move here, and Salesforce
keeps only its page parsing and SOQL planning in its own bundle. The 25
`clientProgramSalesforce*` exports and the provider imports of
`connectors_builtin_node` are then removed in that migration PR, with no
compatibility path.

## 4. Questions for review

1. Owner: is a top-level `client_row_source_host` acceptable as the capture
   connection point, or should it live inside an existing common package
   that already depends on `query_planning`?
2. Row wire: JSON objects keyed by declared field name (proposed), or arrays
   in declared field order?
3. Sequencing with #285/#292: the multi-source gate stays
   `duckdb-acquired`-only; this proposal is single-source and does not
   change that gate.
