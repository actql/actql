# Scenarios and acceptance checks

The ten Programs in `examples/` use the stage grammar. Provider-like names
refer to synthetic Catalog fixtures. Expected behavior is an acceptance
definition, not an execution report.

| Fixture | Purpose | Acceptance checks |
| --- | --- | --- |
| parent-child-notify.aql | Parent, child, then notification | Notification-only revision changes, unchanged upstream local templates, row correlation and unknown outcomes |
| upload-attach.aql | Upload then attach | Acceptance versus usable Ref availability, stamped/native capability and management-write permissions |
| unattended-two-saas.aql | Unattended integration across two services | Stage/Effect count does not add review; item counts and amounts remain cumulative |
| two-messages.aql | Two messages to one channel | Target versus item identity, duplicate-content rejection |
| infer-timeout.aql | One transient model failure | Finite retry, typed outcomes, costs and unknown usage |
| pdf-summary.aql | Attachment, summary, then CRM | Capture classification defaults, MIME/content/scope and ModelTask egress |
| webhook-dedupe.aql | Repeated delivery of one request | New business request versus recovery, logical locator versus dispatch key |
| local-mcp.aql | Single-row JSON | SDK extraction and durable secure defaults |
| approval-drift.aql | Target or explanation changes | Local review scope, no silent approval reuse, stale renewal |
| placement.aql | Large aggregate placement | Captured local/remote observations, exact numeric paths, shared graph and budget |

The failure scenario captures changes in stage A, successfully updates CRM in
stage B, then receives a known permanent notification failure in stage C.
Normal execution leaves the cursor unchanged. An authorized operator may
explicitly abandon C's unmet duty with signed evidence: the Run stays failed
while a separate exceptional source-commit receipt permits progression.
An unknown outcome requires durable reconciliation handoff. Refetching data
under a new request ID is not recovery of the original request.

Run every scenario both as direct stages and as canonically extracted Programs
plus Run Graph. [acceptance-cases.json](acceptance-cases.json) defines the
behavioral expectations. Each implementation records independent execution
evidence, including crash and resume.

## Ordered derive examples

[d11/ordered-derive.aql](d11/ordered-derive.aql) covers retaining an input value,
shadowing, prior-slot references and select.
[d11/dependency-before-selection.aql](d11/dependency-before-selection.aql)
checks that dependencies are evaluated before necessary fields are removed.
Use both for source, value and evidence regression checks.
