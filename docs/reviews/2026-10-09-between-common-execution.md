# Common BETWEEN execution repair

The checker admits the existing three-operand `between` expression, but the
relation lowerer rejected it as `ExpressionNotImplemented`. This blocks
#1081 at task compilation, before its public aggregate ordering acceptance.

The common lowerer now preserves BETWEEN as one three-operand expression.
The common execution frame evaluates search, lower and upper once, in authored
order, then uses the existing bounded binary comparisons and three-valued AND.
It does not expand the search into two evaluations or introduce frontend-only
semantics. Emission preserves the existing `between` wire operation.

Operand roots remain owned through both comparisons. Existing frame cleanup
releases roots and workspace on cancellation or failure. Logical work charges
one expression and its three operands; the two physical comparison scans use
the existing control budget without synthetic semantic expression charges.

## Limited verification

Pinned MoonBit 0.10.12+1634b282e and Node 22.22.0 were used.

- JS original expression/lowering selection: 33/33, run-sxqOdQ.
- JS final BETWEEN, Text comparison and frame selection: 16/16, run-cddXx5.
- Native final BETWEEN and lowering selection: 21/21, run-qcD67h.
- Wasm same selection: 21/21, run-m4ZnPb.
- Generated lowering interface: JS/Wasm/Native match, run-K9Tc3S.

The independent expectations cover inclusive/reversed bounds, NULL and false
precedence, eager third-operand failure, exact logical work at quanta 1/7/256,
long borrowed Text, exact live/workspace limits, and cancellation in either
physical comparison. Tests check no residual roots/workspace and no refund of
consumed work. These are focused execution results, not whole-Core or packed
Host acceptance. Source was uncommitted during these runs; this record does
not claim an already-published SHA was executed.

The #1081 Local/HTTPS cohort remains required before claiming its public
ordering path complete. Hosted CI remains stopped.
