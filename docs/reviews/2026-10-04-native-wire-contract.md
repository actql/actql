# Native Client wire derivation

## Scope and authority

Fixes #349 against main `7763fe148d80f4443b52f7428143ae325301fe9a`.
The initial `actql-client-host/0.1` contract and existing public JS acceptance
remain the authority. There is no new wire version, schema CID, compatibility
adapter, authorization decision, or runtime schema engine.

The existing machine contract now records the connection mode/owner and Hybrid
constraints previously expressed in `validClientConnection`. Its `response_rules`
records profile connection-field equality and profile/admission requested-durable
requirements. The existing generator emits both JS and ordinary Native functions
from these rules and the same projected connection/profile/admission/RunRef
schemas. Native no longer has independent copies of those validators.

Native generation deliberately accepts only the schema forms used here and
fails closed on unsupported keywords, patterns and combinations. In particular,
untyped conditional bounds, a closed object with no properties, and simultaneous
const/enum cannot silently lose a constraint. Generation uses the repository's
pinned MoonBit formatter; initialize `MOON_HOME` as documented for development.
The read-only generator checks Native output alongside existing JS/types.

The existing behavior is retained, including UTF-16 maximum lengths, scalar
minimum lengths, safe integers, repeated capabilities, connection ownership,
requested durability and the Native durable-downgrade diagnostic. An attach
response now honors the same requested-durable admission rule as submit.
Native rejects invalid connections before I/O and malformed profiles before
sending the subsequent operation. This is validation convergence, not evidence
of an authorization bypass or repair.

## Actual baseline counterexamples

A fresh selected Native CLI build from the exact main source was exercised over
mTLS with a response fixture. Its command exited successfully for each of these
profiles; the actual JS `validClientProfile` rejected each:

- An otherwise valid profile with `extra: true`
- `scopeRef: "a\nb"`
- An ASCII scopeRef of length 257

The valid control passed both entry points. This replaces the issue's Native
source-path-only evidence with executable transport evidence. The baseline build
was the selected `src/cmd/native_client` target (27 tasks), not a full Core build.

## Independent corpus and ordering

`scripts/fixtures/client-wire-contract-corpus.mjs` has independently authored
expected outcomes. No expectation imports or calls the product generator or
validator. Its 102 cases run through the actual JS public entry points and the
fresh Native executable over mTLS in `scripts/test-native-client-wire.test.mjs`.
The Native process runs outside the checkout with an empty executable PATH.

The cases cover valid profiles, admissions, RunRefs and connection combinations;
unknown and missing fields; empty strings, control characters, ASCII and astral
length boundaries; integer limits; invalid CIDs; mode/owner agreement; Hybrid
requirements; and submit/attach durability downgrades. The RunRef cases use a
valid lookup request and vary the remote found response, avoiding a malformed
request or a foreign-reference mismatch as the rejection oracle.

For every malformed profile, a subsequent submit attempt must fail and the
server must observe only connect. Invalid connections must cause zero requests.
The original Native transport suite remains unchanged apart from importing the
new corpus after its existing assertions. Thus the normal distribution-client
CI command executes the new cases without changing its gate or test inventory.

## Derivation and verification evidence

- Final focused corpus/generator/wire tests: 126/126 (102 + 6 + 18). The original
  Native transport assertions also pass, including their existing downgrade
  diagnostic, submission-unknown, held reply, read and attach checks
- SDK caller regressions: 54/54 across index, in-process Host port and redirect
  tests, using this worktree's actual client-wire package
- Selected Native release build with `--deny-warn`: pass
- Read-only generation, changed Native formatting and scoped diff checks: pass
- Actual rule-evolution probe: temporarily change authoritative scope maximum
  256 to 255 and the requested profile durability value from durable to volatile,
  regenerate and rebuild the selected Native executable. Two independently
  expected rejections pass through both actual JS and Native entry points.
  Restore the contract/generated files, rebuild and rerun the normal corpus
- Generator tests also reject unsupported evolution and compare exact generated
  Native/JS output, so a stale consumer cannot pass freshness checks

No full local Core, all-target, proof, packed or performance campaign was run.
The mTLS response fixture proves transport validation and request ordering;
it does not prove real Host frontend admission, provider execution or a complete
Program Run. Natural CI for the submitted SHA is reported separately.

## Adjacent duplicated-validator inventory

- `valid_reference` is now generated and also covers Native found-request lookup
  and attach identity checks. Equality to the requested attach ref remains a
  separate caller identity binding
- `valid_held` still duplicates held/checkpoint structural and state-dependent
  rules. Migrating it is a separate bounded extension; this change makes no
  claim that every Native response schema is generated
- `valid_request_lookup` retains its found/unknown/not-found envelope and
  request-ID checks; its nested RunRef now uses the common derivation
- `preparation_refusal` retains its closed-code parsing, bounded JSON budget and
  uncertainty classification. Its existing test reads the machine-contract
  refusal-code list
- Delivery lookup already delegates attempt/record/receipt admission to the
  portable `run_publication` owner, followed by request-identity binding. It is
  not replaced with a second schema implementation
- Command option, endpoint, bounded-file, request-construction and stream
  termination checks are transport behavior, outside this response-schema unit
