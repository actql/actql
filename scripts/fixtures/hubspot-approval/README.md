# HubSpot record approval fixture

Use the original `update.aql` and `read.aql` with the
[shared record workflow](../record-approval/README.md). The same authored
Program selects one company's native string `id`, reviews `name`, explicitly
approves one UPDATE and reads the same saved Result before status on reopening.

`provider.mjs` supplies only synthetic Account/property/record responses and
protocol assertions for an owned local TLS server. It never implements the
product Account, Credential, approval, dispatch claim or cleanup. It checks a
credential header's presence, not a real HubSpot token's validity. Provider
authentication and real-account permission acceptance remain separate.

The synthetic Catalog declares `name` and an existing writable string
`actql_request_id` marker. The Effect profile selects business field `name` and
that distinct marker property; it creates neither a provider property nor an
UPSERT capability. The update route requires the exact selected company and
new value, the logical request CID as `objectWriteTraceId`, and the dispatch
marker CID in the same physical body. It accepts only one original write.
The independent control company remains unchanged. Wrong targets, changed
values, missing/malformed markers and additional fields refuse before mutation.

Metadata, target reads and update use their original installed Site, declared
Resources and current checks. For the owned fixture, derive one complete
Account wire with `recordApprovalHostAccountConfiguration` and pass that same
wire to the Source profile and Host authorization. Do not pass a provider-only
subset to one side: the original Checkpoint's configuration identity must
match the Site that later issues its grant. This is caller configuration,
not permission to weaken the product's identity check.

Capture must show the sealed original Review and leave the provider unchanged.
Only the explicit approval phase may send the marked update. Separate-process
Saved recovery must perform no provider request or resend. Keep the first
unexpected failure and its fresh state; no missing response or timeout proves
absence, nonacceptance or cleanup acknowledgement. Record each actual public
close and observe live state/Credential descriptors independently.
