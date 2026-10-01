# Prepared INFER public acceptance

## Scope and status

Base: `373764e0bd0c100451575cdb0b1a4e90f4e8ce43` (includes #112).
The preparation also integrates main
`10231f2a9a71779bb377bbf7ed500bdd5f89aee9` (includes #116).
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

The prepared [packed controller](../../scripts/test-packed-infer-input.mjs)
produces and installs artifacts from the fixed integrated source, with prepack
enabled. It copies
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

After adopting A's fixed SHA and adding the real standalone Host setup module,
run from the committed integration worktree:

```sh
node scripts/test-packed-infer-input.mjs \
  --owner-sha <full-adopted-common-owner-sha> \
  --host-setup ./real-host-setup.mjs --first-row-only
```

The first-row profile uses a separately authored one-row source and expected
assessment object, without KEEP or an ordering declaration. It still checks
the complete Result description, one model dispatch and capture, and no new
execution on re-read, attach, lookup or identical submit. Provenance records
`acceptanceProfile: "first-row"`; success does not certify the full KEEP/AS
matrix. After that path passes, omit `--first-row-only` to run the full matrix.
Both profiles remain `not_run` until they use the adopted real common Host.

The owner SHA must be an ancestor of the committed source being packed.
The standalone setup module must import installed OSS packages, without
workspace-relative modules. Its exact bytes are copied to the installation
and their SHA-256 is retained with both source and common-owner SHAs. This
controller does not make an unimplemented owner available.

The resulting application command inside the clean installation is:

```sh
node packed-infer-client.mjs ./real-host-setup.mjs
```

Both transport runs must complete. The setup module and actual ModelTask
installation are not provided yet: missing setup or rejected execution fails
the application; there is no mock fallback or automatic skip. Use a fresh Host
Store per transport/run so request IDs cannot collide with earlier evidence.
The existing packed-evidence owner saves tarball digests, stdout/stderr,
termination and timing before checking success. Expanded installation files
are reclaimed on success or failure; `--keep-artifacts` preserves them for
diagnosis. Logs and provenance remain in the evidence directory.

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

The query bridge was rebuilt from the integrated source. The bridge, acceptance
assertions, controller prerequisites and packed-evidence tests passed 26/26.
The prepared INFER sources lower successfully; this does not establish runtime
support. An earlier uncommitted run failed the final clean-diff guard and was
not recorded as a successful gate.

The packed-controller prerequisite tests separately reject missing setup,
missing/short owner SHA and nonexistent setup before invoking build tools.
These are preparation tests, not packed execution evidence.

The first-row profile addition passed the public assertion, packed-controller
prerequisite and packed-evidence tests: 20/20. This checks profile selection,
independent one-row values, description/nullability comparisons, capture and
dispatch counts, and retained no-extra-dispatch checks. Canned assertion
controls remain distinct from real public Host execution.

Both local preparation gates subsequently passed on the unchanged committed
source `23c1dcc0eecd6a37c68491f83ac4e30a8c98359f`:

| Command | Result | Scope |
| --- | --- | --- |
| `node scripts/local-checks.mjs run spec` | Exit 0, 972.9 seconds | Full spec job, including generated artifacts, authorization vectors, metadata and the final clean-diff guard |
| `node scripts/local-checks.mjs run client` | Exit 0, 2285.8 seconds | Client/Host 321/321; packed Node/browser and Checkpoint; native mTLS; packed SQL/Pipe/SGA and Result descriptions; simulated Salesforce Site 277/277; Effect recovery and capture cleanup |

Recovery probes recorded zero Source/Compute calls on restart, and uncertain
Effects were not resent. These probes exercise existing Effect execution;
they are not INFER ModelTask evidence or real Salesforce org acceptance.
Tracked files remained unchanged throughout both jobs.

The SQL/Pipe/SGA packed regression used the following artifact SHA-256 values
from that same source. Its external installation completed Local/HTTP Named
Result acceptance and was reclaimed after evidence was saved.

| Package tarball | SHA-256 |
| --- | --- |
| `actql-client-wire-0.0.0-development.tgz` | `c9882e6300c184e7086e86a56cc70b1be3f65e059d0b97364ea49b379eac3a86` |
| `actql-sdk-0.0.0-development.tgz` | `823149a8d04223425d9752b29596b72e72d3401ef168e6d164b7ec1557b38cf3` |
| `actql-run-host-core-0.0.0-development.tgz` | `7f9b0c0d91987a45fbbdf5aa4a3f819db56e73a340d5c7297e52462e54df01a2` |
| `actql-local-node-0.0.0-development.tgz` | `5faf5e785fcac31371111e6291b7de9df35c8cebd281cfca2f9596d19c0ee1f6` |
| `actql-node-0.0.0-development.tgz` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

The native Client binary SHA-256 was
`7e83cc468cbb72e5c9c44be6ea6d50bee7cda91f46f952426e3e7bbf27968dd4`.
Local logs are retained under `_build/infer-preparation-evidence`; the packed
evidence owner retains per-command logs, termination records and provenance.

Shared Core three-target gates were not rerun for these Client-only preparation
changes. Linux CI is not yet verified for this preparation branch. Real packed
INFER execution remains `not_run`: the common owner and real Host setup remain
the dependencies for execution acceptance. The #112 Frontend completion is
unchanged and is distinct from the incomplete inference execution milestone.
