# Native Local Host binding

This records the adopted trust and credential boundaries for the standard
Native Local CLI. These are implementation requirements, not claims that Local
execution or Provider approval has passed public acceptance. The existing
Native Remote CLI, its wire contracts and distribution remain intact.

## Explicit configuration adoption

The operator explicitly selects the configuration, execution account and private
user-owned Host state. Directory discovery, a Program or a URI cannot select
trusted authority. Merely passing a file to the preparation-only CLI is not an
adoption operation.

Adoption durably binds the exact selected source/configuration, admitted account
configuration, account, adoption/profile identity and managed-root identity.
Retain the original bytes and their identities; configuration identity rules do
not normalize Program, Model or Effect data values. Physical containment must
bind the selected root and reject symlink/path aliases that escape it.

Use the existing Native journal and its physical custody boundary. Do not create
a second Local journal, execution Owner, scheduler or approval mechanism.
Current admitted operator configuration determines current authority. A Run
retains the historical configuration and authority binding under which it was
admitted; current settings cannot silently replace those originals on restore.
Authority expansion requires explicit adoption. Restriction or deletion never
causes automatic profile reapplication or regeneration of removed grants.

An initial profile is published content whose finite body, identity preimage,
CID and containment rules have independent expectations before shipping. Empty
authority is valid. Connectivity, Connector registration and adoption do not
generate Provider read/apply permissions. Source read and Effect apply remain
independently authorized at their existing boundaries. Approval does not supply
otherwise denied authority.

## Initialization and interrupted adoption

Freshness requires an exclusive, explicitly selected private Host-state creation
and matching durable initialization intent. A missing configuration, adoption
row, key or database is not freshness evidence. Bind the real private state and
managed-root custody rather than accepting caller-supplied labels as proof.

Persist a one-time initialization intent under an exclusive fenced claim before
creating configuration content. Create without overwriting an existing file.
Confirm the exact created file identity and durably finalize adoption before
protected dispatch. Config creation and a journal commit are separate physical
events; their combined result is not assumed atomic.

| Observed state | Required action before protected I/O |
| --- | --- |
| Explicit fresh state, exclusive claim, no conflicting content | Persist intent; create exclusively; confirm identity; finalize adoption. |
| Matching recorded intent, creation not yet performed | Continue only under the original fenced claim and exclusive creation. |
| Matching intent and exact created content | Recover that initialization; finalize the original adoption without rewriting content. |
| Finalized adoption with matching custody/configuration/account/root | Open existing Owners and evaluate current admitted authority. |
| Concurrent initializer | Refuse or observe the original claim; never create a second initializer or combine grants. |
| Existing config without matching initialization/adoption proof | Refuse protected dispatch; require explicit recovery rather than overwrite or merge. |
| Divergent file, foreign account/root, ambiguous creation or lost custody | Refuse protected dispatch; do not reset keys or infer that execution never occurred. |
| Adopted configuration removed | Preserve adoption and original Run evidence; do not regenerate permissions. |

An unknown commit response requires reopening and inspecting the original
durable intent/adoption under its original identity. It is not permission to
retry fresh initialization, send a Provider request or create another Run.
Physical cleanup failures retain the existing Owner and retry handle; the
failure must not convert unfinished adoption into a fresh environment.

The first assembly slice selects private user-owned configuration and state
parent directories explicitly. It exclusively creates one named state child
and binds both real roots, the source file generation, exact source bytes,
admitted account/CID and original initialization nonce. The account document
budget is 1 MiB; initialization and physical configuration witnesses are
bounded to 8 KiB each. Explicit entries, including an empty entry set, are
accepted without generating a bootstrap profile. A named bootstrap profile is
refused until its original is installed and verified.

The immutable initialization intent precedes exclusive configuration creation.
The separately persisted configuration witness binds its actual device, inode,
length and original intent CID. An existing state child without its intent,
or copied configuration without its creation witness, cannot become fresh by
retrying adoption. Completed staging and an intent preceding creation can be
reopened under the same filesystem lock and original bindings. This staging
boundary is not final journal adoption and grants no protected execution.

Restoration uses the existing SQLite adapter's retained-only open, after format
and custody admission. It refuses missing/empty databases and missing schema
constituents without creation, migration or schema repair. Fresh initialization
has a separate exclusive creation proof; ordinary open or physical absence is
not that proof.

## Direct Local credential grant/use scope

Add a distinct typed Direct Local scope to the existing common credential
grant/use Owner and its Native physical adapter. Do not encode Direct Local
work as a Remote Site, runtime bundle or DispatchRequest. A Client request or
Effect Ledger CID does not inhabit those identity domains.

The existing Remote wire, identity preimage and CID domain remain unchanged.
Local and Remote scopes/grants are distinct alternatives and cannot substitute
for one another. The Local contract binds these actual inputs:

- Local Host, account, original adoption and current authorization identity.
- Original Run invocation and the checked unit/operation occurrence.
- Original attempt and credential-use fence.
- Connector registration/revision and the exact Provider target/request.
- Applicable expiry and the original grant/use identity.

The grant/use Owner validates these bindings before credential use and send.
Recheck current Source read or Effect apply authority, installation identity,
expiry and cancellation fences at their existing boundaries. Approval is
additional evidence, not a substitute for current authorization.

Sending follows the existing durable send-start record. A confirmed response is
reused under its original request and attempt. A possibly sent request remains
unknown and retains reconciliation custody; neither reopening credentials nor
restarting the CLI permits a blind resend. Retain responsibility for observation
and cleanup of started work after cancellation.

## Public execution and restoration

Trusted Host assembly connects to the existing original Submission, pre-start
Run persistence, checked Source/Compute, publication and Result Owners. Prepare
and durably bind the original Run before protected physical work. The public
CLI then exposes bounded read, original lookup and cancellation through those
Owners. An exited CLI is not evidence of cancellation or cleanup completion.

Restore the original Submission and Run, not a newly compiled execution.
Preserve saved Source/Compute/Model responses, request identities, approved
materials and unknown Effect responsibility. Metadata lookup does not reopen a
payload, consume another read grant or send a Provider request. A new read is an
explicit new operation; receipt-confirmed completion remains distinct from a
delivered prefix or normal transport terminator.

## Independent acceptance requirements

These expectations are fixed independently of implementation output. A contract
record or internal fixture is not public execution evidence.

| Counterexample or route | Required result |
| --- | --- |
| Untrusted project config or foreign selected account | Protected I/O count zero. |
| Missing adoption proof, lost custody or divergent file | Refusal; no initialization repair, grant regeneration or protected I/O. |
| Crash at intent persistence, exclusive creation or final adoption commit | Recover the exact matching original state or refuse ambiguity; no duplicate adoption. |
| Concurrent bootstrap or managed-root escape | No unauthorized dispatch or merged authority. |
| Source followed by multiple checked processing steps and Named Result | Independent expected rows/schema/order through the installed Native CLI; bounded read. |
| Process exit followed by original lookup/read/cancel | Original Submission/Run preserved; saved work not reexecuted; original operation loss remains distinguishable. |
| Local/Remote substitution, wrong Run/unit/attempt/Provider | Refuse before credential send. |
| Expired grant or stale/currently denied authority | Refuse before send; approval cannot override it. |
| Required Effect approval | Zero writes before approval; intended count after approval under the same Run. |
| Saved response or unknown Provider result after restart | Reuse confirmed originals; do not resend unknown work or report it as success. |
| Temporary cleanup failure | Same Owner/handle retained; retry, with no early capacity return or double release. |

Publish each implemented slice with fixed source SHA, actual artifact/digest,
commands and explicit executed/unverified coverage. Public npm publication,
Cloud deployment, secret rotation and production Provider writes are outside
this implementation authorization. Hosted CI remains stopped. Focused local
checks cover changed boundaries; heavy cross-target/proof/package campaigns
remain with the integration verification owner.
