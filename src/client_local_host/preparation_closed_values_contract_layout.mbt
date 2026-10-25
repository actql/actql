///|
/// Inventory construction for the guarded one-stage Number Values closure:
/// fifteen roots, thirty-two unique bodies, twenty-four traversed edges,
/// twenty-two unique edges in eight nonempty adjacency owners. The shape and
/// pinned operation/catalog closure must be checked by the original driver;
/// these constants do not admit an arbitrary caller-supplied contract graph.
priv struct ClosedValuesContractLayout {
  retained : PreparationRepresentationUnits
  temporary : PreparationRepresentationUnits
}

///|
fn closed_values_contract_layout() -> ClosedValuesContractLayout? {
  // Four arrays: roots(cap16), bodies(cap32), stage bodies(cap32), outer
  // stages(cap8): (8,92,8). Inventory (1,10,4), four optional profile/numeric
  // carriers (4,4,4), fifteen roots (15,30,0), fifteen sites (15,15,90).
  // Each of roots+traversed edges may construct a distinct body payload even
  // if its CID is later deduplicated:39. At most three nested enum payloads
  // (CoreContractBody, CatalogGrammar/ExpressionContractBody, Inherited).
  // Charge all three even where actual zero-payload variants are inline.
  // Payload CIDs and dependency pointers borrow pinned static strings.
  let retained : PreparationRepresentationUnits = {
    record_headers: 160L,
    reference_slots: 268L,
    scalar_words: 223L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Builder seen32, adjacency-owner map8 and one stage seen32. Map helper
  // includes temporary old backing and Some wrappers during rehash.
  let seen = closed_values_map_constructor_layout(32).unwrap()
  let owners = closed_values_map_constructor_layout(8).unwrap()
  // Eight adjacency maps share22 entries, not eight copies of22. Each map
  // capacity <=8+4*n at the pinned13/16 threshold, so sum capacity <=152.
  // Aggregate map formula: (3K+4E,2K+2capacity+6E,5K+6E).
  let adjacency_maps : PreparationRepresentationUnits = {
    record_headers: 112L,
    reference_slots: 452L,
    scalar_words: 172L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Eight Dependencies records+target arrays. Sum append capacity <=8K+2E
  // =108, including conservative spare slots for all eight owners.
  let adjacency : PreparationRepresentationUnits = {
    record_headers: 24L,
    reference_slots: 132L,
    scalar_words: 16L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Old backings for roots,bodies,stage-targets and eight adjacency targets:
  //11 headers, no larger than16+32+32+108 retained reference backing slots.
  let growth : PreparationRepresentationUnits = {
    record_headers: 11L,
    reference_slots: 188L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Builder(1,6,4), CoreContractLimits+hash limits(2,0,7), stage temporary
  // Dependencies+stage array(3,11,2), source/incoming limits(2,0,6), and
  // semantic-rule/local-snapshot inline arrays(4,8,4).
  let controls : PreparationRepresentationUnits = {
    record_headers: 12L,
    reference_slots: 25L,
    scalar_words: 23L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Only one edge is visited at a time, but allow both underlying expression
  // and mapped catalog dependency records/Options/closure plus nested enums,
  // the active seen/dependency get Options, and outer Result/Stop carriers.
  // No recursion or per-edge retained stack exists in either while traversal.
  let edge : PreparationRepresentationUnits = {
    record_headers: 12L,
    reference_slots: 16L,
    scalar_words: 20L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Quote construction: ten unit records including the sum, two Map helper
  // Some results, sum/output Some, output record, nine-slot sum array/backing,
  // and current checked-arithmetic carriers: envelope22H,23R,58W.
  let proof : PreparationRepresentationUnits = {
    record_headers: 22L,
    reference_slots: 23L,
    scalar_words: 58L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([
      seen, owners, seen, adjacency_maps, adjacency, growth, controls, edge, proof,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}
