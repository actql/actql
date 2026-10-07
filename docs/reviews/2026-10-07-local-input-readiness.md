# Incremental managed input readiness

Implementation and verified source:
`735d4690608fac12fc847f68acfcec3a9cfd8b12`.
Parent: `5c58a26542327dddde9c971545bfb3c32bb0e766` (#812, still open).
The parent's adopted main is `148723200139ced6605223cc703275c0fa71f3a0`.

## Boundary and change

`start_local_managed_dispatch` previously scanned every Relation input before
every provider resume. It only checked whether each required imported read
was present; it did not perform availability or authorization verification.
The scan was uncharged bookkeeping outside the provider quantum. This is a
source-level linear-walk finding, not a measured public stop-delay failure.

The existing binding pass now counts missing required reads once. Accessible
ordinary inputs are already ready; supplied inputs keep their own admitted
representation and do not require a read import. A managed bridge or retained
ordinary importer installs its exact validated read at its original physical
port, then decrements the count once. Repeated or out-of-range installation
is rejected without changing the count or an existing read. Provider resumes
check the count instead of scanning all inputs.

The count is private readiness bookkeeping, not a new authority, availability
cache or ledger. Exact binding, import/rebind validation, provider input mapping,
live/disposed checks, physical stop confirmation and scratch custody remain.
An already-started cancelled provider still receives its terminal advance.
No public API, wire, identity, operation ceiling or logical work rule changes.

`managed_carrier_runtime.completed_available` still calls the retained
availability callback. This unit does not claim that every installed callback
is constant-time. Scratch release and its availability witnesses also retain
their separate collection walks.

## Executed evidence

The driver fixture covers mixed physical positions, duplicate and foreign
installation, zero required imports and 4096 unfinished reads. Its last
unfinished read remains blocking after a duplicate completion attempt. This
is a private bookkeeping fixture, not proof that a public task has 4096 ports.
The initial dirty-source selection passed 5/5 (`run-Ym2wFH`,
`focused-test-sILIBt`).

At the clean implementation SHA:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/connectors/local/driver/managed_dispatch_wbtest.mbt \
  src/query_integration/local_managed_values_wbtest.mbt \
  src/query_integration/local_managed_cross_join_wbtest.mbt \
  src/query_integration/local_managed_unary_wbtest.mbt
```

This passed 56/61, with five failures (`run-trL0WU`,
`focused-test-ZMVBem`). The driver and Cross Join selections passed. The
failing caller expectations were not changed:

- Values advance count: 58 versus expected 21.
- Keyed COUNT chain work: 199 versus expected 91.
- Exact COUNT chain work completion at 91 fails.
- Exact COUNT chain workspace fixture also uses work 91 and cannot complete.
- Overlapping chain capacity: 42398080 versus expected 42397568.

A separate unchanged-parent comparison ran only the two failing source files:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js --jobs 2 \
  src/query_integration/local_managed_values_wbtest.mbt \
  src/query_integration/local_managed_unary_wbtest.mbt
```

At parent `5c58a26542327dddde9c971545bfb3c32bb0e766`, it passed 42/47
with the same five failures and values (`run-QsHGud`,
`focused-test-Yak5n0`). This isolates them from the readiness change; it does
not resolve the accounting inconsistency or prove all work boundaries. The
existing [accounting issue #498](https://github.com/actql/actql/issues/498)
requires independent charge breakdowns, but names different fixtures.

Only two consuming roots were rebuilt (`run-8r68T3`):

```sh
node scripts/local-checks.mjs build moon --timeout-seconds 120 -- \
  --target js --release --jobs 2 src/client_values_host_abi src/connectors_builtin_node
node scripts/build-local-node-assets.mjs
node scripts/build-local-node-assets.mjs --check
node scripts/build-run-host-core-package.mjs --runtime-only
node scripts/build-run-host-core-package.mjs --check
```

The clean implementation SHA passed the actual retained-Store public Host
selection 3/3 (`run-62Ibgl`, `focused-test-AezIEZ`):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  --test-name-pattern 'public retained Values completion names|public retained Append completion names|public retained Cross Join completion names' \
  adapters/host-node/public-property-name-retention.test.mjs
```

These normal Programs use the installed managed driver and real Store. Each
checks exactly three Named Results, independent ordered rows/schema, producer
and two consumers, request reuse without extra dispatch, delivered cancellation
after positive work, custody before physical stop and final snapshot release.
They do not establish a public many-port latency bound or a new Store-fault
matrix. Other runtime roots retain their existing artifacts; this is not a
pristine packed acceptance campaign.

Generated consuming asset SHA-256 values:

- Local provider: `31423efc5e139c916b48e5c9f8a670fd5cec56d466e27c17383094fff2f0ef93`.
- Run Host ABI: `226557953b53c84cbf9076f090075d02ecd02199b42dd1307eaf22f90ee85aba`.

The existing `checkDriverRetirementSource` read-only check passed against this
source: reviewed stop/cleanup/work/root ordering, scratch witness and common
reservation retirement were unchanged. Formatting and whitespace checks passed.
Receipts are retained under `_build/local-checks/attempts/` and
`_build/focused-evidence/`.

## Remaining work

The five baseline caller failures need independent work/capacity explanations;
observed totals are not approved replacement expectations. Installed callback
walks, other scratch collections and Native allocation/reclamation
correspondence remain separate boundaries. Wasm/Native execution, full Core,
proof, packed/HTTPS and performance were not run. No CI success or completion
of the full Local retained goal is claimed.
