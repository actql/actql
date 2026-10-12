# F04: ordinary Pipe and set continuation

Parent: #1688, fixed `bf4f18784d1a912224dcb716f06fd163aa971b8a`.
This unit retains the original F04 contracts; it does not add a language profile.

The baseline `5fd5345be0299ffb41380aedf7c19b7db0e302f1` contains two independent
positive counterexamples. Both returned `InvalidQuery` in `run-96C4zF` (0/2):
an explicit query Relation WHERE/LIMIT before an intrinsic candidate Vectors,
and a typed NEAREST set head sharing both original inputs across two terms.

Candidate metadata now comes from the admitted prefix through the existing
common checker and passes to the ordinary `compile_steps`. That compiler retains
its original ranges, predicates, projections and integer limits. No second
scope interpreter, identity adapter, evaluator or Source acquisition is added.

The existing set owner delegates its left head to the unified script dispatcher.
The same `set_head` fact is carried through Graph rows and Carrier continuations;
right operands and final operations remain exclusively with the outer set owner.
The first working attempt missed those two facts and regressed the existing
Graph set controls (`run-Gdgt23`, 19/23). The controls and expectations were kept.

After that correction, `run-PBsE2A` passed 22/23. The typed set's fully retained
Program had 28 steps against the existing 20-step checker limit. Its four typed
operand occurrences each emitted two unused record-bridge/projection steps
despite having no KEEP. Removing only those eight steps makes the same authored
set fit the original cap. Role evidence and native Vector identities stay intact.
No limit, K, predicate, rows, ordering or operator count is weakened. The working
source passed 23/23 in `run-wS5QP2`, including the three original Graph set controls.
`run-JLBKO1` is a compilation failure from an unavailable Array method (execution
0); it remains a failure. The LIMIT wire assertion was corrected before a
successful product run using the existing machine `take {count, offset}` contract.

The composite Vectors white-box control now locates operations by their ordinary
names rather than relying on incidental step indices. It retains the independent
ordered tuple expectation, original producer references, and no `to_vectors`;
it additionally requires no unused `vectors` bridge for omitted KEEP.

The parent source grammar, rules, manifest and complete Values identity preimages
are frozen separately. Current query rules are resealed using the independent
oracle and existing generators; old CIDs are not reinterpreted under new bytes.

Fixed-HEAD validation is reported separately from these working-source runs.
Public Local/HTTPS, Native/Wasm execution and Hosted CI remain unexecuted here;
new installed E2E is 0. The original finite F01–03/F04 public matrix remains
required. JOIN-tail binding and composite Relation conversion remain connection
gaps. No full Core, new producer, Heavy reservation or additional global gate is
introduced by this change.
