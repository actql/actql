///|
/// Strict, one-stage Closed Values topology only. This is a component vector,
/// not a grant or a second tariff. The original guarded input, source trees,
/// compiler/result graph and context components remain separate dependencies.
priv struct ClosedValuesTopologyLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
/// Constructor inventory (headers, reference slots, scalar words):
/// stage_parameters.Source + retained declaration Limits,
///   Some(program) + stages.copy() (binding reader is None):      5, 8, 8
/// original empty Declarations, entries, usage:                  4, 3, 4
/// original empty BoundValues, entries, usage:                   4, 4, 4
/// CollectedStage (collection internals belong to context):      1, 2, 2
/// CollectedOperations + append stages + OperationsUsage:        4,13, 7
/// BoundOperations + append stages + copied OperationsUsage:    4,13, 7
/// StagePorts (ports graph belongs to compiler):                 1, 2, 1
/// ResultImports + empty entries:                               3, 3, 5
/// AttachedImports:                                             1, 2, 1
/// ResultExport (original borrowed name):                        1, 3, 0
/// ResultWiring, three append arrays, preparation usage/Some,
///   both alternative attachment arrays/Some (conservative):    15,56,21
/// PreparedLocalSource + final usage + context_prefix tuple:     3, 7, 8
/// stage_results.Checked + two append arrays + Usage:            6,22, 8
/// Some(original Declarations) supplied to CheckedPipeline:      1, 1, 1
///
/// No parameter_references Inventory/Index/BoundIndex, local_inputs attachment
/// internals, pipeline_parameters collection, ContextualClosure or check-only
/// topology is duplicated here. Empty parameter owners are real, not None.
fn closed_values_topology_retained_layout() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 53L,
    reference_slots: 139L,
    scalar_words: 77L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Each fixed decoder packet covers one ObjectView, four child Cursors,
/// four lookup Some carriers and four required Result carriers. Its fields
/// and names borrow the source indexed tree; its Map is priced separately.
/// Root and Stage bodies have at most four members on the exact shape guard.
fn closed_values_topology_layout() -> ClosedValuesTopologyLayout? {
  let retained = closed_values_topology_retained_layout()
  let view : @execution.PreparationRepresentationUnits = {
    record_headers: 13L,
    reference_slots: 18L,
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let map4 = closed_values_map_constructor_layout(4).unwrap()
  let known = closed_values_map_constructor_layout(1).unwrap()
  let empty = closed_values_map_constructor_layout(0).unwrap()
  // Five distinct opens: parameters.prepare root; local_program stage;
  // parameters.collect stage; bind_ports stage; collect_checked stage.
  // No per-cell traversal occurs in these topology wrappers.
  // A second topology-sized graph is a conservative staging majorant:
  // - old ProgramStage/import variant arrays and two mapped arrays;
  // - old ResultWiring record before its immutable attachment copy;
  // - finish_local_source stages/publications/table_inputs arrays;
  // - empty operation slots and binding names/missing arrays;
  // - transient Publication/Ready/Result/Option carriers and usage tuples.
  // These are single-pass constructor products, not execution-frame charges.
  // Retained cap-eight arrays dominate the at-most-one staging arrays. No
  // old copy of rows, schemas or context internals is included by this bound.
  // Additional fixed binding/control packet: empty names/missing arrays,
  // Budget, callback closure, and limits records at the eleven call seams
  // (prepare,bind,local_program,collect,imports,inventory,orders,ports,
  // wire,operations,checked). Each limit has at most eight scalar fields.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 17L,
    reference_slots: 5L,
    scalar_words: 95L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let read = @stage_results.local_program_read_control_construction_extent()
  let read_controls : @execution.PreparationRepresentationUnits = {
    record_headers: read.record_headers,
    reference_slots: read.reference_slots,
    scalar_words: read.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Output/quote construction: two original unit records, this result, Some,
  // the new original read extent/units2H8W, and16-item sum wrapper/backing.
  // The read controls are temporary: they unwind before Local/Context returns.
  let proof : @execution.PreparationRepresentationUnits = {
    record_headers: 8L,
    reference_slots: 20L,
    scalar_words: 21L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      retained, view, view, view, view, view, map4, map4, map4, map4, map4, known,
      empty, controls, read_controls, proof,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}
