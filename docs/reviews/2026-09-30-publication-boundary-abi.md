# Publication boundary ABI follow-up

The portable MoonBit publication owner remains the source of progression
decisions. Its numeric FFI codes are now decoded once in the common JS runtime
adapter. The publication orchestrators consume named actions, and the decoder
rejects unknown, fractional, or absent codes before they can select an I/O or
cleanup branch. The existing delivered-Result action adapter uses the same
boundary.

| Owner | ABI decoder | Consumer | Type boundary |
| --- | --- | --- | --- |
| `run_publication` setup, attempt, cancellation, finalization, commit failure, unknown retry | `runtime-core.mjs` → `publication-action.mjs` | `run-publication.mjs` | `PublicationRequestContract`, `PublicationAttemptContract`, `PublicationRecordContract`, `PublicIndexEntryContract` |
| `run_publication` prepared release and cleanup-owner progression | same decoder | `completed-run-publication.mjs` | owner-issued cleanup handles (unchanged) |
| `run_publication` durable payload failure and cleanup-owner progression | same decoder | `durable-result-payload.mjs` | owner-issued payload and cleanup handles (unchanged) |
| `run_publication` Result delivery progression | existing decoder | Result access and delivery adapters | existing branded `DeliveryContractView<Kind>` |

The selected publication roles are phantom TypeScript distinctions over the
existing owner-issued token. `admitPublicationContract()` preserves the exact
literal role at the type boundary; issuance and commit APIs accept the
appropriate role. The portable owner still validates actual token ownership,
contract role, and full evidence at runtime. The type change does not make a
CID, wire string, or hand-written object an authority and does not change the
public wire or contract version.

Independent negative type cases reject a same-shaped object and swaps between
request, attempt, and record. Runtime tests also reject foreign role tokens.
The action-vector test pins all relevant ABI codes and unknown-code refusal;
publication and cleanup tests exercise the installed path. No provider-specific
branch or new progression engine was added.

## H1–H3 remaining-work audit

This audit uses the bounded items in the prior Host runtime result, not a new
Host-wide refactor scope. Each independent PR is based on main; it is not a
claim that the PR has been merged.

| Unit | Existing baseline | Final bounded follow-up |
| --- | --- | --- |
| H1 | Durable Run terminal/unknown observations, publication precedence, rollback cause retention, and private authorization diagnostics | [#71](https://github.com/actql/actql/pull/71) retains Client request journal initialization/prepare cleanup custody; [#75](https://github.com/actql/actql/pull/75) preserves the typed installed Run-control projection issue. |
| H2 | `client-dispatch-owner` owns physical start, cancellation, stop observation and cleanup; retained journal reads reject corrupt records | [#73](https://github.com/actql/actql/pull/73) hands off Source acquisition outcome and recovery custody before ordinary error wrapping. Installed Run observation and cancellation use the existing owner and named ABI adapter; there is no second state machine. |
| H3 | Branded delivery views, four named delivery action families, independent acquisition fixture and controlled expiry clock | [#75](https://github.com/actql/actql/pull/75) names installed Run observation arguments; this PR distinguishes selected publication roles and decodes the remaining publication/payload actions. |

The broader Connector SDK type surface, D Outbound, and unrelated optional
Bridge results are not part of H1–H3. Final acceptance still requires the
same-SHA CI for each open PR and review/merge by the repository owner.
