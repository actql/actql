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
    // Read flags3 (return, delivery, fork fence), original fact3, scalar snapshot4, five shell tags5,
    // two failure/tag carriers4. No variable spelling, row or historical array.
    scalar_words: 3L + 3L + 4L + 5L + 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
// Fixed logical projection purpose, owned by this SAME task-boundary issuer.
// In addition to the fork above, the actual higher constructor retains:
// outer mutable wrapper, original context, its Some, Projected and Ok
// (H5/R9/W3). The extra wrapper reference retains ONLY the same fork token
// for retry after context disposal; it constructs no new cleanup record.
// Original facts/map/step are borrowed; no tree/string is copied.
// Lookup controls conservatively coexist by lexical constructor SITE, not by
// caller max_nodes: two complete stage/contains iterators (H16/R14/W24),
// sixteen Array.get/map/bind site envelopes incl nested graph helpers
// and their captured closures (at most H4/R4/W4 each; H64/R64/W64),
// six canonical field lookups, each complete pinned iterator plus the
// returned Some (at most H8/R7/W11 each; H48/R42/W66),
// two scalar ordinal decoders (three Some each, H6/R0/W6),
// array-at/target/owner/prefix/compare/result/error shells (H20/R8/W28).
// Sum lookup H154/R128/W188. Loop iterations retain no previous controls or
// history; field names, parameter spelling and complete facts stay upstream.
// Holding the entire peak until explicit return avoids an unproved shrink.
let captured_boundary_logical_projection_bytes : Int64 = captured_boundary_read_bytes +
  @execution.preparation_representation_cost({
    record_headers: 5L + 154L,
    reference_slots: 9L + 128L,
    scalar_words: 3L + 188L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()

///|
// One observer's actual setup and simultaneous temporary base read plus owned
// logical fork. This is sizing DATA for the existing parent, never a reserve,
// child Ledger or claim that these constructors have physical backing.
let logical_boundary_observation_bytes : Int64 = captured_boundary_setup_bytes +
  captured_boundary_read_bytes +
  captured_boundary_logical_projection_bytes

///|
pub fn captured_logical_observation_construction_bytes() -> Int64 {
  logical_boundary_observation_bytes
}
