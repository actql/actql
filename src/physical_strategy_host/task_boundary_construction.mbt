///|
// Actual Debug-only constructors under the existing shared H/R/W tariffs.
// The reservation controls themselves use the Ledger owner's existing
// pre-admitted original slot/constructor inventory. These costs are additional
// consumer DATA, not a substitute ledger, grant or raw VM allocation formula.
// Existing next_captured_task current check, retained at setup so even the
// pre-read absence/current check precedes its own per-borrow reservation.
// Two complete pinned ArrayView.iter/Iter states conservatively coexist:
// view, captured index cell, closure, Iter, element Some and old/new size_hint
// Some (H7/R6/W10 each). Add returned task Some, original completion closure,
// resident predicate closure and one SharedCapacityUsage scalar snapshot.
let captured_boundary_current_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 2L * 7L + 4L,
    reference_slots: 2L * 6L + 1L,
    scalar_words: 2L * 10L + 2L + 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
let captured_boundary_setup_bytes : Int64 = captured_boundary_current_bytes +
  @execution.preparation_representation_cost({
    // Hooks1, setup1, setup Some1, Observed1, pending SetupCleanup1,
    // latest before+committed and OLD+NEW write overlap3*(record+Some)6;
    // simultaneous OLD+NEW grant Some+pair4;
    // original refusal Some+variant2, cleanup Some1, result carriers3.
    record_headers: 1L + 1L + 1L + 1L + 1L + 6L + 4L + 2L + 1L + 3L,
    // Hooks(original,before,committed,grant,reads)5; setup(owner,graph,ledger,
    // reservation,refusal,cleanup)6; Some/Observed/SetupCleanup3;
    // latest/write Some references3; moved grant references2; carriers3.
    reference_slots: 5L + 6L + 3L + 3L + 2L + 3L,
    // Hooks flags2; setup generation/revision/return fence3; record+Some12;
    // option/variant tags3; OLD+NEW grant tag+pair6; refusal/cleanup/carriers8.
    scalar_words: 2L + 3L + 12L + 3L + 6L + 8L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()

///|
let captured_boundary_read_bytes : Int64 = @execution.preparation_representation_cost({
    // Read owner1, scalar-snapshot/list wrapper1, borrowed original fact1;
    // original, head, previous,
    // returned Some and Ok shells5; resource/refusal carriers2.
    record_headers: 1L + 1L + 1L + 5L + 2L,
    // Original hooks/ledger/reservation/record4; wrapper(original,previous,next)3;
    // five option/result references5 and one refusal result1.
    reference_slots: 4L + 3L + 5L + 1L,
    // Read flags2, original fact3, scalar snapshot4, five shell tags5,
    // two failure/tag carriers4. No variable spelling, row or historical array.
    scalar_words: 2L + 3L + 4L + 5L + 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()
