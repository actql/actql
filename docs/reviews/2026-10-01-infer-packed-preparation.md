# Prepared INFER public acceptance

## Scope and status

Base: `373764e0bd0c100451575cdb0b1a4e90f4e8ce43` (includes #112).
The Frontend source/lowering unit in #112 is complete. Common infer execution
and nullable object/property execution have no adoptable public SHA yet.
This change prepares the public acceptance application and independent data;
it does not supply either executor or claim successful packed INFER execution.
The fixture's `execution_status` remains `not_run`.

The [existing handoff](2026-10-01-infer-keep-handoff.md) identifies A's checked
owner, captured execution and expression boundaries. Its independent complete
Programs and the ordinary nullable-object reproducer remain authoritative.
No compiler, checker, ModelTask owner, retry loop or ledger is added here.

## Authored expectations

[packed-acceptance.json](../../spec/frontend/fixtures/infer-keep/packed-acceptance.json)
contains physical source rows, the required published source schema/key,
deterministic model responses, ordered column contracts, and expected rows.
These are test inputs/expectations, not an admitted ModelTask contract or a
Client-supplied Catalog. The real Host must publish the alias and obtain its
checked environment through the normal configuration and authorization path.

| Case | Required public evidence |
| --- | --- |
| KEEP/AS | Only `id`, nullable `note`, and the closed `assessment` object; declaration order matches `describe()` |
| Omitted KEEP | Only the assessment object; input keys are inside its explicit `input_key` field |
| Nested filter | Outcome refinement and nullable property evaluation yield the authored `id/risk` row |
| Empty input | Zero model dispatch/capture; full Result type is still described |
| Dropped column/old alias/name collision | Typed preparation refusal, no new Run acceptance or physical I/O |
| Missing/duplicate/nullable/unproven key declaration | Typed preparation refusal before source/model I/O |
| Duplicate acquired key values | Accepted Run fails preflight before any model dispatch/capture; no model failure outcome is invented |
| Re-read/attach/lookup/identical submit | Original Run and Result retained; no additional source I/O or model dispatch/capture |
| Different source under the same request ID | Intent conflict with no execution or I/O |

The success value is a non-null closed object. The failed item has typed NULL
as the whole value. The success object's `reason` remains nullable. The model
adapter must return the authored responses through the common execution owner;
it must not inject completed Result rows or bypass preflight and capture.

## Packed connection procedure after A's adoption

Use the existing packed installation controller to produce/install artifacts
from the fixed integrated source, with prepack enabled. Copy
[packed-infer-client.mjs](../../scripts/fixtures/packed-infer-client.mjs),
[public-infer-input.mjs](../../scripts/fixtures/public-infer-input.mjs), and
the fixture as `infer-acceptance.json` into the external application directory.
The application imports the installed `@actql/node`; it uses only existing
`connect`, `aql`, `wait`, `result`, `describe`, `all`, `attach`, and request lookup.

The test Host setup module, still to be connected after A's fixed SHA, exports
`openInferTestHost({mode, fixture})`. This is a test-controller interface, not a
new public product API. It returns:

- `options`: normal installed Embedded Local or real HTTP Client options.
- `prepareCase(rows)`: replace the physical test source's rows before a new
  request, preserving its published schema, key and alias generation.
- `observe()`: cumulative `acceptedRuns`, `sourceIo`, `modelDispatches`, and
  `capturedSlots`, obtained from real admission, physical I/O and common-owner
  records. Counters cannot reset between cases or fabricate missing evidence.
- `close()`: close the real Host and its physical test resources.

Run inside the clean installation:

```sh
node packed-infer-client.mjs ./real-host-setup.mjs
```

Both transport runs must complete. The setup module and actual ModelTask
installation are not provided yet: missing setup or rejected execution fails
the application; there is no mock fallback or automatic skip. Use a fresh Host
Store per transport/run so request IDs cannot collide with earlier evidence.

B will connect this test setup using the adopted common owner, then record A/B
source SHAs, package digests, real counters and successful Local/HTTP results.
Evidence-slot provenance and remaining invalid-key variants also require the
common owner's admission/execution tests; these prepared cases do not prove
those obligations independently.

## Verification categories

`node --test scripts/public-infer-input.test.mjs` checks independent fixture
consistency and the acceptance assertions themselves. Canned Client responses
test that wrong NULL, nested nullability, dispatch counts and replay are caught.
They are assertion tests, not model execution, packed acceptance or a substitute
for A's implementation.

The query bridge was rebuilt from this base and the prepared sources lower
successfully. The combined bridge/assertion tests passed 14/14; `test:docs`
passed 52/52. The spec job's `check:spec`, strict resource boundary check,
authorization vectors and metadata check passed. Its final clean-diff guard
initially failed because this preparation was still uncommitted, with no
additional generated/metadata changes. That guard must be checked again after
committing. This is not recorded as a successful end-to-end wrapper run.

Client/Core execution gates, Linux CI and real packed INFER execution have not
been run for this preparation unit. The common owner and real Host setup remain
the dependencies for execution acceptance; the #112 source-only completion is
unchanged.
