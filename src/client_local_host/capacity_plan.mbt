///|
/// Immutable policy snapshot derived from the exact original sequences. It is
/// shared by the pre-admission quote and the configured Local task consumers.
priv struct ClientLocalCapacityPlan {
  sequences : Array[@execution.GeneratedSequence]
  admitted_rows : Int
  resource_policy : ClientLocalResourcePolicy
  dispatch_entries : Int
  dispatch_name_bytes : Int
  graph : @strategy.CheckedDAG?
  result_envelope : ClientLocalResultEnvelope?
  publication : ClientLocalResultPublicationPlan?
  schema_inventory : ClientLocalSchemaProofInventory?
  values : @execution.ValueLimits
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  imports : @local.LocalImportLimits
  exports : @local.LocalExportLimits
  metadata : @local_driver.LocalManagedMetadataLimits
  metadata_retained_bytes : Int64
}

///|
fn client_local_capacity_plan(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
  scalar_values? : Bool = false,
  graph? : @strategy.CheckedDAG? = None,
) -> ClientLocalCapacityPlan {
  let inventory = if scalar_values {
    client_local_schema_proof_inventory(sequences, graph~)
  } else {
    None
  }
  let dispatch_inventory = match inventory {
    Some(value) => Some(value)
    None =>
      client_local_schema_proof_inventory(sequences, graph~, scalar_only=false)
  }
  let dispatch_bounds = client_local_dispatch_bounds(dispatch_inventory, graph)
  let admitted_rows = max_rows
  let max_rows = match inventory {
    Some({ closed_rows: Some(bound), .. }) =>
      Int::min(max_rows, Int::max(1, bound))
    _ => max_rows
  }
  let (values, execution, measurement) = client_local_execution_limits(
    max_rows~,
    scalar_inventory=inventory,
  )
  // IO observes scalar cells plus row field names, not evaluator intermediates.
  // Keep expression text independent unless every original typed child and
  // generated step has a separate text-free proof.
  let io_text = match inventory {
    Some(value) => client_local_inventory_names(value, max_rows)
    None => None
  }
  let values = match io_text {
    Some(bytes) => { ..values, max_text_bytes: bytes, }
    None => values
  }
  let execution = if io_text is Some(bytes) &&
    client_local_text_free_scalar_sequences(sequences) {
    {
      ..execution,
      rows: {
        ..execution.rows,
        input_values: { ..execution.rows.input_values, max_text_bytes: bytes, },
        output_values: {
          ..execution.rows.output_values,
          max_text_bytes: bytes,
        },
      },
    }
  } else {
    execution
  }
  let original_imports = client_local_import_limits_for_rows(max_rows, values)
  let original_exports = client_local_export_limits(max_rows, values)
  let fields = dispatch_inventory.map(value => value.fields)
  let imports = {
    ..original_imports,
    wire: {
      ..original_imports.wire,
      max_columns: fields.unwrap_or(original_imports.wire.max_columns),
    },
  }
  let exports = {
    ..original_exports,
    wire: {
      ..original_exports.wire,
      max_columns: fields.unwrap_or(original_exports.wire.max_columns),
    },
  }
  // Snapshot metadata before any independently proved wire specialization.
  let metadata : @local_driver.LocalManagedMetadataLimits = {
    name_bytes: imports.wire.max_bytes,
    bridge_entries: imports.wire.max_nodes,
    completion_entries: imports.wire.max_nodes,
    schema: {
      max_fields: imports.wire.max_columns,
      max_bytes: imports.wire.max_bytes,
      max_nodes: imports.wire.max_nodes,
      max_depth: imports.wire.max_depth,
    },
    result_workspace_entries: imports.max_rows,
    retained_bytes: 0L,
  }
  let result_envelope = match graph {
    Some(original) => client_local_result_envelope(original, max_rows)
    None => None
  }
  let publication = match graph {
    Some(original) =>
      Some(
        client_local_result_publication_plan(
          original, max_rows, result_envelope,
        ),
      )
    None => None
  }
  let scalar_metadata = if scalar_values &&
    graph is Some(original) &&
    result_envelope is Some(envelope) &&
    inventory is Some(proof) &&
    client_local_inventory_nodes(proof, max_rows) is Some(_) {
    client_local_scalar_metadata_envelope(proof, original, max_rows, envelope)
  } else {
    None
  }
  let result_metadata = if scalar_values && result_envelope is Some(envelope) {
    client_local_result_metadata_retained(
      envelope,
      max_rows,
      client_node_publication_schema_bytes(),
    ).unwrap_or(0L)
  } else {
    0L
  }
  match scalar_metadata {
    None =>
      {
        sequences: sequences.copy(),
        admitted_rows,
        resource_policy: client_local_resource_policy(),
        dispatch_entries: dispatch_bounds.0,
        dispatch_name_bytes: dispatch_bounds.1,
        graph,
        result_envelope,
        publication,
        schema_inventory: inventory,
        values,
        execution,
        measurement,
        imports,
        exports,
        metadata: {
          ..metadata,
          retained_bytes: result_metadata,
          result_workspace_entries: if result_metadata > 0L {
            result_envelope.unwrap().workspace_entries
          } else {
            metadata.result_workspace_entries
          },
        },
        metadata_retained_bytes: result_metadata,
      }
    Some((extra, result_workspace)) => {
      // One outer row array, plus the two nodes of the logical Relation wrapper.
      // The metadata admission ceilings remain independent and unchanged.
      let wire_nodes = values.max_nodes + 3
      let wire_bytes = match inventory {
        Some(proof) =>
          client_local_scalar_wire_byte_bound(
            proof.fields,
            proof.names,
            max_rows,
          ).unwrap_or(imports.wire.max_bytes)
        None => imports.wire.max_bytes
      }
      {
        sequences: sequences.copy(),
        admitted_rows,
        resource_policy: client_local_resource_policy(),
        dispatch_entries: dispatch_bounds.0,
        dispatch_name_bytes: dispatch_bounds.1,
        graph,
        result_envelope,
        publication,
        schema_inventory: inventory,
        values,
        execution,
        measurement,
        imports: {
          ..imports,
          wire: {
            ..imports.wire,
            max_nodes: wire_nodes,
            max_bytes: wire_bytes,
          },
        },
        exports: {
          ..exports,
          wire: {
            ..exports.wire,
            max_nodes: wire_nodes,
            max_bytes: wire_bytes,
          },
        },
        metadata: {
          ..metadata,
          retained_bytes: extra,
          result_workspace_entries: result_workspace,
        },
        metadata_retained_bytes: extra,
      }
    }
  }
}

///|
fn client_local_capacity_plan_matches(
  plan : ClientLocalCapacityPlan,
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Bool {
  if !physical_equal(plan.resource_policy, client_local_resource_policy()) ||
    plan.admitted_rows != max_rows ||
    plan.sequences.length() != sequences.length() {
    return false
  }
  for index, sequence in sequences {
    if !physical_equal(plan.sequences[index], sequence) {
      return false
    }
  }
  true
}
