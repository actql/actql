# Darwin ARM64 parent Ref allocation-request correspondence

## Boundary

Adopted main: `9dff38dfdc080254fa1b648957de1ce8ce37f72f`.
Clean implementation source: `873bd8e79df2afe2855da451d4b213ed53f19497`.
This branch is independent of #909 and #912. Final merge target is main.

The existing parent constructor census declares one Int64 Ref, three Bool Refs
and one Int Ref. Linux x64 already had generated-code correspondence for those
five roles; Darwin ARM64 explicitly remained unresolved. This change extends
that existing finite component to the actual Darwin object and executed binary,
without changing product code, ABI offsets, capacity constants, owners, models,
mutation policy or workflow selection.

The restricted decoder requires typed helper call count/order and initializers,
the same returned allocation, unique aligned private frame slots, no overlapping
full/partial/SP-alias replacement, reviewed control flow and exact observer role
arguments. Actual linked helper bodies establish constant request/header/payload
store/return sequences. Object and linked observations must agree and the final
consumer regenerates them from the archived bytes with tool digests bound.

Caller-side callback retirement is separately restricted to the five distinct
malloc-return aliases handed to the existing retaining Owner, in order and after
that handoff. Substituting a primitive Ref, changed alias or duplicate/early
release rejects the correspondence. The retaining semantics of that existing
Owner remain a source/ABI trust assumption. This is not general machine-code,
callback body, arbitrary alias or lifetime verification.

The five requested extents are 16, 12, 12, 12 and 12 bytes, totaling 64. These
are generated allocation-request facts. The conditional 80-byte Ref allowance
is unchanged. Neither allocator footprint nor a whole-parent physical upper is
inferred from those values or from scalar GC descriptors.

## Focused controls and historical original

Working-diff consumer selection passed 48/48, with no skips:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  proofs/relation-pipeline/capacity/parent-control/parent-reference-arm64.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/parent-reference-sites.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/parent-capture-sites.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/provider-callback-code.test.mjs \
  proofs/relation-pipeline/capacity/backing/parent-bounds.test.mjs
```

This executes 10 ARM64, 10 x64 Ref, 10 x64 capture, 14 provider scalar-code and
4 parent-bound cases. Controlled disassembly negatives cover changed helper or
initializer, alias/role substitution, overlapping stores, frame escape, malformed
relocations, object/link mismatch, changed helper allocation/body, unknown calls,
control-flow entry and callback retirement. They are decoder controls, not new
physical mutation campaigns. Existing x64 scope and final-consumer requirements
are preserved. A supported platform cannot downgrade to unresolved admission.

Development failures are retained. The initial negative expected an object/link
mismatch but changed only the linked store, causing the earlier valid observer
role gate to reject; the fixture was corrected to alter both linked store/load.
A selected nonexistent `current-layout.test.mjs` was not discovered and is not
claimed as coverage. The corrected consumer command above names existing files.
The added retirement positive initially omitted its linked Owner/decref symbols;
only that controlled symbol fixture was corrected. These were fixture failures,
not reproduced product failures. Earlier successful 8/8 and 47/47 executions
precede the additional retirement restriction and do not replace the final 48.

The independently archived historical Native object/executable from source
`96bb2b030e5bf77749f0d50841367eee188db5c2` was read without recompilation.
It established the original five allocation requests and observer roles. That
original retains its historical execution SHA, binary/object digests and tool
identities; it is not relabeled to the submitted implementation. Early attempts
used unscoped symbols and omitted two existing calls; those rejected attempts are
retained. The successful historical inspection preceded the additional retirement
restriction. The current submitted-SHA physical diagnostic below is authoritative
for the complete new decoder.

## Actual clean-source diagnostic

At clean implementation source `873bd8e79df2afe2855da451d4b213ed53f19497`,
the existing `current-diagnostic.mjs` ran once under shared heavy guard
`run-1eVSlj`, with a 900-second budget and 5-second TERM grace. The bounded step
took 64.964 seconds; complete streams, exit 0 and released locks are recorded.

```sh
node proofs/relation-pipeline/capacity/parent-control/current-diagnostic.mjs
```

The existing pinned compiler and Node 22.22.0 were used. This runner executes
`check.mjs`, checks seven conditional Lean propositions at their explicit types
and audits their permitted axioms. It then installs the existing diagnostic
overlay, executes exactly one Native whitebox fixture and restores the submitted
source byte-for-byte in `finally`. It does not fake Actions metadata or bypass a
CI-only entry point.

The actual final consumer accepted the eleven-candidate provider construction
point, preparation storage, all seven chain phases, five primitive Ref roles and
30 receipt-substitution refusals. The latter are metadata negatives, not new
physical executions. Existing cancel/stopped and cleanup false/error/successful
retry phases retain child, completed occurrence and preparation/cursor custody
until successful cleanup. Clearing containers is not reported as physical GC.

The requested Ref component was established at 64 bytes. The final consumer
explicitly returned `payloadBytesMeasured: false`,
`completePhysicalLifetimeUpper: false` and unresolved ARM64 ordered callback
captures. Provider point bytes remain separately established at 1,504 requested
bytes, rather than promoting the conditional 2,344-byte recipe to a measured
lifetime upper. The conditional retained-core model remains unchanged.

| Bound identity | SHA-256 |
| --- | --- |
| Submitted-source snapshot | `f1399dc473fc1ca5f956bc8f6bebc70089b6936cf456ed97b0be36ab15b32c2c` |
| Diagnostic-overlay snapshot | `daa104fb7640e7398b287d05661888dc6bd6281fcc6056806b61dcc8f8130a33` |
| Compiled fixture boundary | `94df13112ff2a9f849e499eac9aa3c45c0bca96c93f166da35f0c9bbe22a905a` |
| Executed whitebox binary | `78fa45573c27f5aec36503b6bb535499b240b10b3b275a7d72be3fd609364fa6` |
| Independently inspected Native object | `6eebd2d72c3e3cab9295ca5323a62ef79744be60725ab0168567dd01817a54d1` |

Accepted original:
`.artifacts/relation-pipeline/current-chain-native/originals/b877ad495c4495292a653627cfa07fbfa4cfff370fedab250ad6109a08f8c5e6.json`.
The original report and code logs remain immutable. The source snapshot includes
the census, overlay generator and actual model/decoder inputs. A later review/
evidence-only commit does not relabel the execution revision; its complete
verification snapshot must remain byte-identical.

The additional affected overlay/disassembly consumer controls passed 11/11,
with no skips, at the same implementation HEAD after the evidence archive was
created (untracked evidence only; no code edits):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  proofs/relation-pipeline/capacity/backing/parent-overlay.test.mjs \
  proofs/relation-pipeline/capacity/parent-control/native-code-disassembly.test.mjs
```

None of this branch's changed files belongs to the 89 protected foundation paths.
No declaration/hash replacement or history rewrite was made. Actual retained
history was not rerun merely for reporting; this unit does not claim a new
history campaign.

## Remaining obligations

Ordered callback field/capture correspondence remains explicitly unresolved on
Darwin ARM64. Linux x64 retains its existing separate decoder. The new retirement
argument check does not close callback field offsets or semantic/lifetime proof.
Borrowed referents, construction transients, allocator rounding/fragmentation,
whole-parent overlap, Ledger generation/retirement and last-owner/GC reclamation
remain unresolved. Requested bytes, measured point bytes and a proved physical
upper are separate categories.

No full Core, Wasm, Linux physical campaign, public/packed acceptance or hosted CI
was executed in this unit. Synthetic controls do not establish those boundaries.
No authenticated Actions original, compatible subsequent-main qualification,
normal-PR `mutations-js` reuse, related-input fresh execution or authentication/
transfer-inclusive net CI savings is claimed. Those existing resumption obligations
remain deferred without polling or dispatch. This local finite component closes
an actual platform correspondence gap, not the whole project-wide goal.

## Original archive

Archive: `evidence/2026-10-08-parent-ref-arm64-873bd8e79.json.gz`.
It contains 101 original text members: working Node results including failed
controls, focused and bounded-guard records, historical reinspection attempts,
actual submitted-source Native reports and logs, model receipt/log and both
actual independently regenerated provider/Ref code observations. Each original
member retains its exact byte count and digest. Expansion and every member digest
were verified.

Expanded archive: 5,124,703 bytes; SHA-256
`3925171f77995be5f046a06db7dc8423eb3197309db657c01e1c89d0999c72b3`.
Compressed archive: 1,499,827 bytes; SHA-256
`ca5de978df819b1f6d0107c219bcac8a7091d68a87339b78ef1e04d87ea62b4e`.

The 16,392,520-byte actual Native object, 9,842,504-byte whitebox executable and
other produced binaries/debug symbols are retained in this owned worktree under
`.artifacts/relation-pipeline/current-chain-native/code` and `binaries`; they are
not embedded in this text archive. The archive names their exact locations,
bytes and digests. The final consumer regenerated observations from those actual
bytes before publication; the published disassembly/report alone is not a new
execution or a standalone replacement for the retained object/executable.
