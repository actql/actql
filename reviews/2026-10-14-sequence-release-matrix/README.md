# Sequence through the normal installed release entry

This F05 preparation connects the existing Sequence fixture to the normal four
release packages (`client-wire`, `sdk`, `local-node`, `node`). The consumer's
closed `--sequence-only` option uses the existing source-free worker, public
Client factories, transport, authorization, durable Store and cleanup Owners.
The default IN/UNNEST selection remains four normal cases and six refusals.

The original `scripts/fixtures/sequence-source-input.mjs` is unchanged: eighteen
normal cases and nine refusals, including JSON/SQL/AQL-text controls, parameters,
nullable predicates and adjacent/subsequence gaps. Independent rows, ordered
schemas, Expression AST predicates and limits are retained. All cases require
zero Source reads and sessions. No Source engine, Calendar implementation,
adapter overlay or checkout runtime is supplied to the installed consumer.

The exact seven-module relative-import closure is delivered as test code outside
`node_modules`. Missing delivery is a tested counterexample. Completed normal
cases retain actual Run/Result references, rows, full schemas and replay
observations. Completed refusals retain their actual outcome and observations;
partial failures preserve completed work without inventing unexecuted cases.

## Limited checks and prepared public commands

From a clean checkout at the exact submitted source, using pinned Node:

```sh
node reviews/2026-10-14-sequence-release-matrix/prepared-checks.mjs <source-sha>
```

This is Node-only, non-Heavy, sixty seconds with five seconds TERM grace. The
focused test child has a thirty-second timeout. It checks fifteen Node cases;
worker syntax checks do not execute a product or establish public E2E success.

Only after allocation of each shared public window:

```sh
node reviews/2026-10-14-sequence-release-matrix/prepared-release-public.mjs --producer <source-sha> <new-absolute-RC>
node reviews/2026-10-14-sequence-release-matrix/prepared-release-public.mjs --consumer <source-sha> <same-RC> <new-absolute-receipt.json>
```

Each phase preserves the original three-hundred-second/five-second grace limit.
Consumer preparation requires the same source and verified release manifest.
Do not start the consumer after a failed producer or reuse a partial cohort.
Public completion requires all eighteen normal and nine refusal cases on both
Local and HTTPS, actual full values/schemas, same-request/replay observations,
quiet Source/Provider observations and real cleanup/Owner/lock closure.

Producer, installed worker, Local/HTTPS execution and new public E2E are
unverified in this submission. Calendar's existing runtime/selected-artifact
gap remains separate; this recipe does not substitute fixed milliseconds.
