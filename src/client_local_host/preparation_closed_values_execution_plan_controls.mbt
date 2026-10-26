///|
/// Fixed control owners for one installed source-free numeric Values task.
/// The installed four-wire contract original is borrowed (cold admission is
/// forbidden on this route). Checked rows/schemas/graph are borrowed unchanged.
/// Schema inventory, Result envelope/publication plan and their field-dependent
/// constructors/Some carriers are separately owned by the proof component.
priv struct ClosedValuesExecutionPlanControlsLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
fn closed_values_execution_plan_controls_layout() -> ClosedValuesExecutionPlanControlsLayout? {
  // Fixed policy/cache records (H,R,W):
  // ClientInstalledManagedSourceFreePreparation including contracts:1,9,3
  // Pure owner and Some installed contracts:                         2,2,2
  // ClientLocalCapacityPlan16 fields +Some original graph:            2,13,5
  // LedgerLimits:                                                   1,0,6
  // Three ValueLimits (IO,input/output text-specialized):             3,0,12
  // SequenceExecutionLimits and SequenceRunLimits:                   2,3,6
  // FixedInputGuardMeasureLimits:                                   1,0,4
  // Import+wire+retained-row-decode:                                 3,3,11
  // Export+wire:                                                    2,2,7
  // LocalManagedMetadataLimits+schema limits:                        2,1,9
  // Scalar demand(original +four scalar dimensions), Some, added plan ref:2,3,5.
  // Leaf node demand(original +two scalar dimensions), Some and two plan refs:
  //                                                               2,4,3
  // Retained demand-inventory Some (underlying schema owner borrowed):1,1,1
  // The absent actual-module choice is an inline scalar tag, not a module.
  // Sum24,41,74. ResourcePolicy and exact contract bodies remain borrowed.
  let records : @execution.PreparationRepresentationUnits = {
    record_headers: 24L,
    reference_slots: 41L,
    scalar_words: 74L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // GeneratedSequence21 fields:17 references/four inline absent selections;
  // contexts0,retained IDs1,13 empty ceiling arrays. Conservatively also own
  // selected-step Array1/Some and selected-prefix Some even if only one is used.
  let generated : @execution.PreparationRepresentationUnits = {
    record_headers: 35L,
    reference_slots: 35L,
    scalar_words: 40L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // PreparedSequence+steps(cap8)+ValuesStep+PreparedValues. Literal rows are
  // checked originals, not re-created CanonicalValue or row object matrices.
  let sequence : @execution.PreparationRepresentationUnits = {
    record_headers: 5L,
    reference_slots: 15L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // ClientFullSequence(task,limits,sequence), SequenceLimits, ExpressionLimits,
  // full_sequences cap8 array. Charging its whole wrapper conservatively
  // overlaps the already-owned empty cache wrapper, not its payloads.
  let cache : @execution.PreparationRepresentationUnits = {
    record_headers: 5L,
    reference_slots: 12L,
    scalar_words: 13L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Generated outer append array(cap8) and plan's exact one-element copy.
  let copies : @execution.PreparationRepresentationUnits = {
    record_headers: 4L,
    reference_slots: 11L,
    scalar_words: 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      records, generated, sequence, cache, copies,
    ])
    is Some(retained) else {
    return None
  }
  // prepare_wiring: Wiring +ids/last_use/retained/routes append arrays;
  // one empty route and detached empty input refs, ControlBudget/RowWorkspace;
  // positions Map1, attach_fragment_budgets Map0. No fragment context exists.
  let wiring : @execution.PreparationRepresentationUnits = {
    record_headers: 15L,
    reference_slots: 27L,
    scalar_words: 34L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let positions = closed_values_map_constructor_layout(1).unwrap()
  let fragments = closed_values_map_constructor_layout(0).unwrap()
  // Existing generated contexts/retained-id input arrays, empty composed and
  // serialization inventories and their filtered views, input-count array,
  // unwrap fallback: eight arrays each length<=one, cap8 is conservative.
  let arguments : @execution.PreparationRepresentationUnits = {
    record_headers: 16L,
    reference_slots: 72L,
    scalar_words: 16L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Original GeneratedSequence before immutable selection; two old sequence
  // limits/ExpressionLimits pairs; old full-cache backing(cap8).
  let replaced : @execution.PreparationRepresentationUnits = {
    record_headers: 6L,
    reference_slots: 27L,
    scalar_words: 24L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // generated_sequence_capacity now constructs three typed inventory lists
  // (4/10/2 entries), not the former scalar arrays (3/7/3). Each list owns
  // an Array/backing pair:6H/19R/6W. Its16 ExecutionCapacityItem records own
  //16H/0R/48W (unit,count,copies); scalar enum tags do not own payload trees.
  // The shared inventory fold returns16 per-item and3 final scalar Options:
  //19H/0R/38W. The one Values sequence has no fragment contexts, so the
  // per-fragment list is never constructed. This is preparation of the quote,
  // not backing for any executor value-node allowance.
  // Keep the original non-list controls separately: ExecutionCapacity+Some,
  // ClientLocalSequenceCapacity, two result tuples and two Some carriers:
  //7H/5R/12W. Source rows, policies and plan bodies remain original aliases.
  let quote : @execution.PreparationRepresentationUnits = {
    record_headers: 6L + 16L + 19L + 7L,
    reference_slots: 19L + 5L,
    scalar_words: 6L + 48L + 38L + 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Two result/projection carriers at17 constructor seams: shape,sequence,
  // node,taskoutput,generated,selection,inventory,execution limits,dispatch,
  // IO names,Result envelope,publication plan,metadata,capacity,import/export
  // retention and Store inventory. Twelve accessor Options are separate.
  let outcomes : @execution.PreparationRepresentationUnits = {
    record_headers: 51L,
    reference_slots: 80L,
    scalar_words: 85L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // The five extra scalar outcomes conservatively cover two demand products,
  // its wire projection and IO/measurement maps; no duplicate body storage.
  // The leaf inventory's intermediate Some adds (1,1,1), and its checked
  // node-product Some adds (1,0,2); no additional body/row array is copied.
  // Inventory construction: up to15unit records, two sum arrays/backings,
  // output and Option/arithmetic carriers; no fixed nonrecursive VM frames.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 30L,
    reference_slots: 31L,
    scalar_words: 93L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Two old policy-record inventories cover original -> width-specialized ->
  // scalar-wire-specialized immutable copies. Shared schemas/rows are excluded.
  guard @execution.compose_preparation_representation([
      records, records, wiring, positions, fragments, arguments, replaced, quote,
      outcomes, controls,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}
