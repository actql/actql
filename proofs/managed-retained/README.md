# Managed retained boundary model

This is a limited model of the managed retained execution contract, not a proof
of the executable Host, DuckDB, codecs, FFI, or physical storage. It imports only
Lean `Std`; it neither imports nor extends AoA or Smooth theorems. In particular,
it does not establish a bridge to `PosEqStrict`.

Run from the repository root with the installed, pinned Lean toolchain:

```sh
node proofs/managed-retained/check.mjs
```

## Modeled properties

- Completion requires usable material, all required evidence, and required
  identity. Unrequested identity may remain unestablished.
- Evidence issuance is scoped to the exact subject (Run, producer, attempt,
  generation, view, scope) and an admitted issuer/kind/contract triple.
- Revocation prohibits acquiring new pins and cannot be reversed by any modeled
  trace. A completed historical record does not restore live use authority.
- Reclamation requires revocation and no outstanding pins. Foreign releases
  are rejected; acquisition has a finite capacity.
- An additional identity failure does not undo historical completion or alter
  requirements.
- Selection preserves a universal numeric bound, including weakening the bound.
  A concrete counterexample distinguishes a whole-input violation from a
  selected-view violation. Maximum size is not a first-violation position.

## Trusted assumptions and exclusions

Evidence truth, identifier authenticity, correct physical execution and identity
generation are abstract inputs. The model checks scope, not whether an issuer
actually examined the data. Authorized release means access has really stopped;
the model does not prove worker termination. State transitions are atomic in the
model, not a proof that a particular concurrent implementation linearizes them.

Requirements and subjects remain fixed during a trace. `completed` means a
historical success, not permission to publish after revocation. There is no
separate publication API in this model. Physical resource accounting, expression
demand, ActQL diagnostic precedence, Effect execution, renewable leases, full
view-transform composition and all numeric domains are outside its scope.

The executable conformance tests remain necessary. These model proofs do not
establish that those implementations refine this state machine. The printed
axiom audit covers every named theorem: Lean's foundational `propext` and
`Quot.sound` are permitted; unfinished proof axioms are not.
