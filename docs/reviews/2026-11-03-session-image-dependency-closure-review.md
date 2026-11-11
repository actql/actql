# Session image dependency closure review

The existing Session image utilities evaluate the complete reviewed inventory
module and its `proof-runner-extension.mjs` dependency. Both were already bound
by the existing action inputs, but only the inventory was physically staged.
The staging list now consumes that same reviewed descriptor and its explicit
dependency list. It does not discover arbitrary imports, scan another directory
or admit a new effect. Missing, linked or unsupported entries remain refused.

The ordinary compiled JS path also captures the existing
`adapters/host-node/ordinary-node-resource-runtime.cjs`. The exact unchanged
module now belongs to both existing independent sets: `mutationSnapshotExtras`
for keyed/staged inputs and the mutation executor's restoration snapshot. The
actual source-stage regression checks matching Git digests, loads the original
declarations in a separate Node process, rejects altered copied bytes and
restores those bytes. It invokes no CJS operation or resource supplier.

Only one path is added to the snapshot implementation. All scientific mutation
definitions, thirteen required cases, executed-assertion requirements,
restoration procedure, target/compiler flags, limits, child timeouts, image
environment and authority checks are unchanged. No current source is presented
as an old experiment and no compiler failure counts as a mutation kill.

The snapshot module is itself a finite-experiment input. Changing its bytes
therefore changes the current experiment digest. The historical
`isolatedContract`, review revision, experiment digest, platform/toolchain pins
and original evidence remain unchanged. The existing equality test consequently
does not qualify this new experiment for that historical reuse contract; its
residual remains explicit. Fresh execution stays available under the original
rules. This review does not refresh a deterministic runtime contract or claim
new reuse eligibility.

This is physical source/module/key/restoration coverage only. It establishes no
image execution, successful mutation campaign, normal Host operation, actual
funding or complete CI result. Root's separate independent pipeline adapter
membership correction is still required for that distinct caller.
