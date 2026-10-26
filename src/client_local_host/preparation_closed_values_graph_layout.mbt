///|
/// Graph-control ownership only. Wire witnesses, Values proof metadata,
/// LimitClaims/CandidateMinimum and their strings remain separate owners.
/// The exact narrow closure has four leaf-only arithmetic graphs of sizes
/// 0,1,1,2 (evidence, Values, byte publication, row publication), no edges.
priv struct ClosedValuesGraphControlLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
fn closed_values_leaf_graph_layout(
  nodes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if nodes < 0 || nodes > 2 {
    return None
  }
  let n = nodes.to_int64()
  let cap = closed_values_append_capacity(nodes).unwrap()
  // ArithmeticClaims, LinkedArithmetic, CheckedArithmetic; witness copy,
  // identities, checked values/units/leaves; boxed arithmetic.Value per node;
  // linked index Map (constructor growth bound deliberately retained here).
  let map = closed_values_map_constructor_layout(nodes).unwrap()
  @execution.compose_preparation_representation([
    {
      record_headers: 13L + n,
      reference_slots: 13L + 2L * cap + n,
      scalar_words: 12L + 2L * cap + n,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    map,
  ])
}

///|
fn closed_values_graph_control_layout() -> ClosedValuesGraphControlLayout? {
  let zero = closed_values_leaf_graph_layout(0).unwrap()
  let one = closed_values_leaf_graph_layout(1).unwrap()
  let two = closed_values_leaf_graph_layout(2).unwrap()
  // Remaining retained family table (H,R,W):
  // two MixedClaims +empty limit arrays +bound[0/1]:       10,10,15
  // two ProgramClaims +proof arrays +mixed/proof Some:     9,12, 9
  // two HostSources +source/dependency arrays, oneOrigin: 11,13,19
  // two Program Applications +two indexed Some:           12,14,18
  // one GraphInputs +three empty arrays:                   7, 9, 9
  // empty Sequence/Join/Traversal application containers
  //   still own one None step slot, no limit slots:       17,27,23
  // Source/Consumer/ApplicationCoverage +two Some:          5,10, 5
  // ApplicationClosure, GuardApplications, two arrays,
  //   proof-ownerMap1/input-ownerMap0, tuple key:          17,62,25
  // BoundGuardClosure/BoundAuthorGuards, arrays, Some:       7,16, 9
  // Both application tables conservatively keep one step/proof slot and
  // Some carrier even if the initial evidence collection is empty.
  // Original ContextualClosure, author guards, parameters, policy and Values
  // StepBound are borrowed. These counts do not duplicate their payloads.
  let wrappers : @execution.PreparationRepresentationUnits = {
    record_headers: 95L,
    reference_slots: 173L,
    scalar_words: 132L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      zero, one, one, two, wrappers,
    ])
    is Some(retained) else {
    return None
  }
  // Reference resolution scratch for all four graphs: referenced+resolved
  // node arrays/records, dependents+empty per-node arrays, indegrees/ready,
  // limits and Result carriers. All leaf graph scans are iterative.
  let arithmetic : @execution.PreparationRepresentationUnits = {
    record_headers: 68L,
    reference_slots: 92L,
    scalar_words: 128L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Four mixed/program cycle checks own successors/indegrees/ready arrays;
  // two nonempty checks add one empty child each, and the one Values witness
  // adds empty operand/name map arrays: sixteen arrays, each <=one element.
  // Cap-eight slots are charged as references conservatively for scalar slots.
  let cycle_arrays : @execution.PreparationRepresentationUnits = {
    record_headers: 32L,
    reference_slots: 144L,
    scalar_words: 32L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let empty = closed_values_map_constructor_layout(0).unwrap()
  let policy = closed_values_map_constructor_layout(1).unwrap()
  // The non-arithmetic constructors' limits/usage/Result packets: mixed2,
  // program2, Host1, graph1, sequence/join/traversal3, coverage3, guards1.
  // At most five scalar fields per packet; no fixed VM frame is charged.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 13L,
    reference_slots: 0L,
    scalar_words: 65L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // An additional complete wrapper inventory bounds old/new immutable
  // collection copies, input occurrence arrays and accessor Option/Result
  // carriers across collection/coverage/guard binding. This is intentionally
  // additive even where constructor scopes do not overlap; payloads excluded.
  // Quote own unit/Option/output/array objects remain a small explicit packet.
  let proof : @execution.PreparationRepresentationUnits = {
    record_headers: 24L,
    reference_slots: 27L,
    scalar_words: 68L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      wrappers, arithmetic, cycle_arrays, empty, empty, empty, policy, controls,
      proof,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}
