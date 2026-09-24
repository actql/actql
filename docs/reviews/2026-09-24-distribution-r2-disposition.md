# Distribution R2 review disposition

Review input: `/Users/t14i/Downloads/03-distribution-client-cloud.md`,
written against `92dd4410ea9eadf278b312ec6020564883f0ec9a`.
This disposition compares that snapshot with the current distribution branch;
the review SHA is historical evidence, not the implementation base.

| Review item | Current disposition | Product evidence |
| --- | --- | --- |
| DIST-R2-1, isolated Connector assembly omits Client wire | Fixed after the reviewed SHA. The assembly copies `packages/client-wire`, checks its generated closure, includes it in source cleanliness and before/after digests, and runs the standard Node Host in the isolated tree. | `scripts/check-connector-addition.mjs`, `scripts/connector-addition-wire-dependency.mjs`, `scripts/connector-addition-wire-dependency.test.mjs`, `check:connector-addition` |
| DIST-R2-V1, request and Run Definition mutual binding | Covered in the normal Node issuance path before journal admission. Independently valid changed Program, changed Parameters, and changed context Definitions are rejected; the physical journal stays empty on the foreign-Definition case. | `adapters/host-node/client-program-bridge.test.mjs`, `src/run_publication_host/client_values_run_binding.mbt` |
| DIST-R2-G1, reserved dispatch through terminal state | Open. One-time reservation and reconciliation after restart prevent an unsupported second Compute. The failure matrix from reserved-but-unstarted through publication and cleanup is not yet a complete product recovery proof. | `adapters/host-node/client-request-journal.test.mjs`; shared Run and output owner work remains |

The Local Values public path computes and reads an independently expected
Named Result. That does not prove the Cloud-owned Site output path, active Run
projection, or Linux CI at the current branch SHA.

Local verification at `edc8362e773c0bfcdc18dbfa20377a366c11cf80`:
`npm run check:connector-addition` passed. It checked the generated Client
wire dependency, both isolated all-target assemblies, the third Connector on
JS/Wasm/native, and the isolated standard Node Host. The gate retained its
report and logs under `.artifacts/connector-addition-bLW52D/`.
