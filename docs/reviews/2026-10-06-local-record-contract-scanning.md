# Retained record contract scanning

## Scope and dependency

This component follows the identity-streaming change in #559, based on
`639821fb25eae73001dd53fe46042debd7b2709e`. That parent is still open; the
component must not bypass it or merge into the dependency branch. The eventual
merge target is main. No language, wire, CID, ordering or policy ceiling changes
are introduced. This is not completion of all Local retained paths.

## Production connection

The ordinary record append cursor previously called synchronous `type_equal`
inside its Fields transition. A recursive contract could walk all nested types
and all Object field names before returning one unit of control work.

`value_contract/equality_steps.mbt` now owns exact type equality as an opaque
continuation. `type_equal` drains that same implementation for synchronous
callers. The existing comparison compatibility rules are reused, not redefined
in a Local adapter. Each advance visits one contract, schedules one child,
checks one field-name fragment, or matches at most 64 UTF-16 units. Object
names are checked in reverse order before children, preserving the original
eager name/refusal precedence. Child visits retain canonical forward order.
The original visited-pair budget remains distinct from poll/control work.

`managed_record_storage/append_steps.mbt` retains that child in FieldContract.
The pending field is latched before comparison; replacing an element of the
caller's field array cannot substitute an unvalidated value on completion.
The current field/index remains uncommitted until equality succeeds. Fixed
scalar equality still completes in the original field poll. Contract mismatch
and pair exhaustion remain typed InvalidRecord, with no wire writer or output
commit. No evidence is weakened to accept compatible-but-unequal types.

The root/handle uses fixed append custody. Continuations reuse inactive wire
stack slots; deeper contracts reserve three slots per extra live frame before
the next step allocates it. A NULL value can have a deeper declared contract
than its wire: value depth is not imposed as a new contract restriction. Extra
slots are released after equality, while failed/cancelled child custody stays
owned until cleanup. Prior rows remain held until builder cancellation.

Pool reaches this cursor through its existing RecordAppend owner. The installed
public Pool regressions exercise that production connection and its scalar
fast path. They are not public cancellation evidence inside a recursive
contract: their output field contracts are fixed scalar/Vector types.

## Independently derived boundaries

- A 129-field Object has 130 visited pairs. Its 388 polls are one root,
  129 name checks, 129 child scheduling transitions and 129 child visits.
  130 pairs succeeds; 129 raises RelationLimit before child allocation.
  Its pending stack peaks at two frames, not an array of 129 copied children.
- One Object name with 130 UTF-16 units takes three name fragments. Exact
  equality completes in six polls: root, three fragments, child scheduling,
  child visit. A final-unit mismatch rejects in four polls, after only the
  root pair. Reference parameter spelling also uses exact fragments without
  NFC or newline normalization.
- Record wire `[["value",{"<130 a>":1}]]` has 148 bytes and five value nodes.
  Original construction work remains width+1+nodes = 7; 6 fails WorkLimit.
  Two outer arrays plus Object require wire depth three. Cursor slots are
  8+2+3*3 = 19, with three retained-row slots at commit.
- A NULL field with five nested two-field Object contracts needs 11 pairs.
  The comparison peaks at six live frames: five child iterators and one name
  frame. Its base cursor has 16 slots and six reusable continuation slots;
  another nine are reserved. Workspace 25 succeeds, 24 refuses before the
  next frame allocation. Pair allowance 10 rejects InvalidRecord. Contract
  slots are released before the 19-slot final append/row peak.

The fixtures also verify premature finish exclusion, prior-row custody,
single cursor cleanup, final builder reclamation and mismatched contract
refusal before any construction work. Existing record byte/node work remains
unchanged; additional control polls are not disguised as old pair usage.

## Executed evidence

These runs used the implementation candidate over the parent SHA above, not a
clean submitted revision. The eventual PR identifies its submitted SHA and
separately executed clean-HEAD checks. Do not attribute these counts to an
unexecuted later SHA.

The pinned toolchain PATH was selected for MoonBit commands. All execution
used the existing bounded/nonzero-test wrappers, with no concurrent gates.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/value_contract src/managed_record_storage src/managed_record_runtime \
  src/local_veca/pool_wbtest.mbt src/local_veca/pool_output_steps_wbtest.mbt \
  src/local_veca/pool_identity_output_wbtest.mbt
```

95/95 passed (`run-d9qgtZ`, `focused-test-xX6eh2`). A subsequently added typed
contract-mismatch fixture passed with the other three storage contract cases:
4/4 (`run-aYfkl4`, `focused-test-d3iiVu`). The final latching regression and
the other four storage cases then passed 5/5 (`run-NKB1ef`,
`focused-test-RlLJam`). Earlier compile/fixture failures are
not success evidence. The corrected wire depth/byte arithmetic was derived
from the literal wire structure, not copied from an output measurement.

A negative mutation drained FieldContract completely inside Fields. The two
scanning/custody fixtures failed, 1/3 passed (`run-t9h9cZ`,
`focused-test-cwMPC7`). The mutation was removed before public preparation.

```sh
moon info --target js,wasm,native src/value_contract src/managed_record_storage
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  adapters/host-node/public-pool-key-retention.test.mjs
```

The intentionally added interface was regenerated with no reported backend
divergence. This is compilation/interface evidence, not Wasm/native test
execution. The selected runtime build passed, including wrapper freshness;
compiled bundles remain ignored. Public Host cases passed 4/4 (`run-XQYFyk`,
`focused-test-SdM4TG`): three explicit ordered Named Results, real Store,
request reuse, cancellation before physical stop, nonpublication and final
snapshot reclamation. These use checkout exports, not packed distribution.
That four-case run preceded the pending-field latching change; the PR must
identify later consuming checks separately, not relabel this run.

The focused Pool resource/evidence and operation-inventory consumers passed
6/6 (`run-fUWHSN`, `focused-test-zXlr5h`). Required new contract evidence roles
are removed individually by mutation tests and must fail the gate. The actual
resource checker also passed; it explicitly does not assert full boundary
completion. Declared three-target evidence connections are not three-target
execution results.

## Remaining work

Carrier schema lookup, record actual-field Map hashing/name matching, runtime
Object-name validation and legacy synchronous drains remain distinct work.
Relation Pool's concatenated member-identity construction is not changed.
The public recursive-contract cancellation boundary, whole-Run exact Ledger
limits, physical heap/latency, new Store failure campaigns, packed/HTTP,
Wasm/native execution and final CI remain unverified. No new Run, cancellation,
cleanup, retry or authority owner is introduced.
