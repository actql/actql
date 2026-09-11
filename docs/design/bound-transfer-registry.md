# Bound transfer registry

The language-owned `actql-bound-transfer-laws/0.1` body is now present in
`spec/contracts/actql-bound-transfer-laws.json` and pinned as an explicit
machine contract. It covers all 72 public operation spellings, including
acquisition and serialization vocabulary outside the current pure-checker
implementation scope. Their presence is classification, not execution support.

`check:bound-transfer`, included in `check:docs`, compares the registry's exact
key set with the authoritative operation inventory and rejects missing/extra
operations and unrecognized classifications. Mutant tests exercise each of
those failures. Normative text distinguishes upper bounds from exact counts,
operation-specific reduction/Carrier laws from generic arithmetic, and an
explicit ceiling requirement from a computed data bound.

The fixed Sketch `src/actql-bounds.ts` is the reference for the classification
shape and existing categories. The current body extends its incomplete
inventory to current operations and uses `events`/`vectors`, not their obsolete
spellings. Existing meanings are retained: distinct/dedupe preserve an upper
bound, group/pivot use reduction laws with their specified empty-input cases,
and sequence still requires a finite enforced ceiling. New inventory coverage
includes generators, set operations, Calendar, additional Graph operations and
ranked acquisition. No operation is deleted or silently classified by default.

This supplies the missing **operation transfer classification** contract. It
does not yet supply the separate closed **witness-law registry** defining
allowed law IDs, source/role pairs, derivations, units and semantic subjects.
That law admission, canonical witness/source closure, enforcement binding and
whole-pipeline discharge remain required. A classification such as
`carrier_specific` cannot be passed as a substitute for those proofs.

The new machine-contract pin changes the language document/family metadata;
it does not rename an existing wire version or claim new runtime conformance.
The local numerical packages remain implementation components beneath the
future complete witness boundary.
