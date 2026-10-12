# Adopted two-input temporal query calls

Scope: the existing F05 `asof_join` and `interval_join` surfaces, independently
based on main `cc456bfad7e8e6aec15b92ea32a3b460360f0db4`. This unit does not
include the separate time-series primary PR or FILES postlude changes.

## Original gap and minimal connection

The independent ordinary JSON control checks, while the submitted temporal
source failed at the public frontend on `b36d67df0` (`run-ueB1xJ`, 0/1).
The initial `run-0rI1m1` is an iterator-indexing error in the new test and did
not execute a product test. Both receipts remain outside Git in the B evidence
area. No old DATA parser, fallback or common constraint was introduced.

The existing bounded query parser retains signature-specific ProducerRef,
FieldRef, OutputName, literal/enum and whole Parameter roles. Right producer
resolution uses the ordinary nearest WITH scope; current row aliases do not
become peer producers. The existing `bind_script_input` owner captures/shares
that resolved peer, and common check-only topology determines the output Carrier
and schema. The untouched Relation tail reuses the existing compiler. Common
identity, temporal tie/endpoint rules, order and resource ceilings are unchanged.

A new small lowering module translates role names only. It retains repeated
pair/tie occurrences, exact tolerance, interval output guards and Parameter
nodes. Left Events identity remains with its existing owner. It does not infer
keys, silently coerce clocks, truncate output, acquire a second source or add
an evaluator. Source/diagnostic ranges retain the authored call origin.

## Independent evidence and remaining work

Tests compare independent operation bodies after normalizing only the private
physical right producer name. They include static controls, Events, repeated
pairs, nested shadowing, same-name row alias/peer distinctions, one installed
seed reused by two operands, wrong-operand refusal and reserved/quoted outputs.
The original `check_limits()` remains unchanged, including its 20-step limit.

Grammar/spec/profile and generated pins are synchronized with the existing
writers. Complete old grammar-bound Runs remain immutable. The current main
Values preimage is rebuilt independently from selected normative contracts;
its existing Run `24f11dc7...` is checked before resealing the authored grammar
change. Product output is never an expected-CID or expected-row generator.

The ordinary packed entry registers twelve normal controls/text cases and nine
refusals, with full ordered schema, independent NULL values, exact tolerance
and output ceilings, zero source acquisition and the existing same-request,
attach/lookup, retained reread and cleanup checks. `--temporal-join-only` narrows
only the existing harness; no special Driver or runtime environment is added.
The previous full inventory is retained separately. Registration is preparation,
not public execution evidence.

`prepared-checks.mjs` uses the original 60-second/grace-5 non-Heavy guard.
`prepared-public.mjs` prepares the original same-clean-source normal five-package
producer and Local/HTTPS consumer, each 300 seconds/grace 5. Shared Heavy
allocation is required before either public command. Installed public E2E,
Native/Wasm runtime, hosted CI and provider execution are currently unverified.
Old failures are not promoted to PASS; product public completion remains pending.
