# Public wire codec projections

## Authority and scope

The registered `actql-client-host.json`, `actql-protocol-schemas.json` and
`actql-run-publication.json` remain the schema owners. Their existing response
and received-report relationships project through the Client wire generators.
These projections validate received evidence; they cannot grant authorization,
create a Run, acknowledge a Store commit, cancel work, or permit retransmission.

Numeric admission follows [JSON scalar spelling](json-encoding.md#scalar-spelling):
finite binary64 values exclude negative zero. Integer schema positions additionally
require safe integers and their registered bounds. Booleans are distinct from
numbers, including in constants. Python's arbitrary-size input integers must
produce a refusal rather than an overflow exception. Its ordinary response
`decode_json` already rejects invalid numeric spellings before shape admission.

The existing [Native wire derivation](../reviews/2026-10-04-native-wire-contract.md)
preserves Client–Host/publication maximum lengths in UTF-16 units and minimum
lengths in Unicode scalars. Neither the canonical JSON aggregate budgets nor
interactive control's separate scalar-length projection changes that convention.
Malformed surrogates are refused, never repaired. Ordinary wire strings are not
NFC-normalized; the Submission nonce's separate existing NFC/UTF-8 contract still
applies. The canonical-value field-name pattern uses ECMAScript whitespace,
including NBSP and BOM, but excluding NEL, U+180E and zero-width space.

The registered non-control identifier class is a nonempty whole string with
no U+0000–U+001F or U+007F anywhere, including a final LF or CR. Its source
machine-schema pattern uses an absolute-end negative lookahead, so a generic
schema search and all generated consumers apply the same law. This class
admits spaces, ordinary Unicode, U+2028 and U+2029 unless another existing
field rule excludes them. IDs are never trimmed or normalized. Other regex
classes retain their existing contracts.

The initial 0.1 compatibility correction removes Python's prior acceptance of
a terminal LF under its soft `$` anchor. JS without multiline mode and the
Native all-character predicate already refused that value; CR was already
refused by all three. Native is corroborating evidence, not the authority for
this decision. Existing valid ID bytes and identity preimages are unchanged.
Refusal occurs before signing, credential use or resolution transmission.

A request-correlated variant must match its registered identity. The caller's
expected identity is validated even for closed not-found/Unknown variants without
an echoed identity. Those observations remain not-found/Unknown; acceptance of a
wire shape does not permit a new submission or resend. Current schema CIDs and
input revisions are checked independently of their digest-shaped spellings.

## Deferred Local request capture

The existing wire preparation Owner can detach and deeply freeze a request
before Local service initialization awaits. Submission and check requests use
their existing JSON snapshot once; shallow control requests acquire the same
owned snapshot when they need to cross that wait. Original Workspace targeting,
JSON number refusals and validation of serializer-produced values remain.

The in-process ingress retains only the captured packet's exact object,
operation and structural preparation. The activated ingress consumes those
immutable facts without another serialization, deep freeze or body validation.
A copy or different operation re-enters normal preparation. This association
does not retain an authenticated principal, Account decision, Run or Result,
and does not bypass Source lineage or current authorization after reentry.
HTTP/raw packets keep ordinary admission; no wire fields or identities change.

## Source responsibilities and ten interface attributes

This table is a reference projection for the interface inventory, not a second
contract or an execution receipt. In Python, `_wire_codec.py` is generated;
`_wire.py` delegates structural/report/correlation checks and retains the existing
operation-specific chronology, Submission, cancellation and request checks.
`client-wire-scalar-rules.mjs` emits the limited numeric predicate for JS,
Python and Native; `client-check-report-rules.mjs` projects the same selected
report relationships for those consumers. No full engine is imported for Remote.

| Attribute | Existing owner and boundary |
| --- | --- |
| responsibility | The registered wire schemas and `response_rules`, `request_response_rules`, `check_report_rules`; Host operation owners retain execution meaning. |
| inputsOutputs | JSON scalars/objects and boolean validation; schema integer units, UTF-16 maxima/scalar minima, UTF-8 transport limits; no normalized replacement value. |
| identity | Generated current schema CID checks; registered request correlation; `_wire.submission_ref`, `cancellation` and public JS counterparts retain exact original reference/revision comparisons. |
| ownership | Codecs borrow received values synchronously and issue no capability. SDK `internal/check-observation`, `submission-observation`, `run-observation`, `result-read` retain their original private maps. Python `_values.Observation` and diagnostics retain custody. |
| synchronization | Validation is synchronous. Transport capture and reader lifecycle remain in their existing SDK/Python owners; no codec await, scheduler or callback. |
| failure | Invalid shape/value/reference returns false; transport and caller owners retain typed refusal/Unknown. Python integer conversion overflow is refused at scalar admission. |
| cancellation | Validation performs no cancellation or I/O. Existing client/reader close owners handle interruption and cleanup without resend. |
| resources | Schema limits remain unchanged. Python `_async._json` and SDK `transport-response.boundedHostJson` retain 1 MiB default control response limits; structural predicates do not claim a process-memory ceiling. |
| extension | Existing schema projection fails on unsupported schema vocabulary. Normal generator `--check` includes Python codec, JS artifacts and Native artifacts; no handwritten fallback or old-revision acceptance. |
| verification | Independent `public-wire-language-vectors.mjs`, actual JS/Python consumers, exact production Native codec/cancellation functions in a test-only module, mutation probes and generated freshness. Target/transport/product qualification remains separate. |

## Focused verification

The focused `node scripts/check-public-wire-codecs.mjs` guard runs read-only
generation, independent JS/Python vectors/mutations and actual Native vectors.
It requires the pinned compiler only for target verification, never as a Remote
package runtime dependency. To select affected regressions separately, run
the existing generators in read-only mode and the focused Node wrapper for
`public-wire-language-vectors.test.mjs`, `public-wire-language-mutations.test.mjs`
and affected generator/SDK tests. `ACTQL_PYTHON` selects the existing test Python;
the Remote import counter refuses any attempt to import Wasmtime, DuckDB or the
Local runtime distribution.

Under the existing local-check resource guard and pinned `MOON_HOME`/PATH,
`node scripts/prepare-native-public-wire-vectors.mjs` creates a fresh small test
module and actually executes the same independent vectors on Native with `-j 1`.
It copies the production `wire.generated.mbt` bytes unchanged and verifies them
against the generator. The generator supplies the existing received-check
predicate symbol; the harness does not guess a numbered function or route a
valid template report through a stronger bound-input Submission envelope.
Four cancellation helpers are copied exactly from Native `main.mbt`; no Native
operation or state machine is reimplemented. `inputs.json` records selected
source digests and the explicit isolated-codec qualification. Existing private
production functions can produce unused warnings in this smaller test module.

This proves the selected Native codec, not a freshly built CLI, HTTPS Host,
Wasm engine, complete Run, Local product or installed runtime wheel. A compile
without actual discovered/executed vector cases is not acceptance. Independent
expected answers are never generated by the product. Historical failure logs,
private diagnostic overlays and source-specific receipts remain separate from
fixed-source successful executions.
