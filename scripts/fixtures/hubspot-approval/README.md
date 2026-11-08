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

## Reproduce with an existing normal installation

From the consumer checkout, run the existing bounded local-check wrapper with
`scripts/test-packed-hubspot-source.mjs ORIGINAL_SOURCE NORMAL_RELEASE_DIRECTORY CLOSED_APPLICATION --approval`.
All three paths must be absolute. Set `ACTQL_TEST_PRESERVE_SCRATCH=1` and clear
ambient `NODE_PATH`, `NODE_OPTIONS`, `ACTQL_LOCAL_SOURCE_PROFILE` and
`ACTQL_LOCAL_EFFECT_PROFILE`. The original Source must be clean and match the
normal release manifest. The runner verifies archives and every installed
member before and after, including a failed functional attempt; it builds and
installs nothing. The default selection still runs the two existing Source
cases; `--approval` selects only this one distinct three-process case.

The fixture uses the selected installed runtime's original initialization
owner to obtain the declared alias, then closes that preparation before the
public workflow. Each child keeps its original 30-second whole-process limit.
Capture, approval and recovery use separate processes and fresh explicit HOME,
Host and Credential roots. Both live descriptor snapshots include each exact
root and its descendants, with physical path aliases resolved, using `lsof` on
macOS or `/proc/self/fd` on Linux. An unavailable observer fails explicitly.
These observations do not constitute a physical cleanup acknowledgement.
Keep the printed original root and its state, receipts, stdout, stderr and
summary on every outcome; never reopen a failed state merely to retry.
