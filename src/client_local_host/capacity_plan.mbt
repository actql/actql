///|
/// A failed required quote is distinct from a graph-less calculator's genuine
/// absence of metadata and from a successfully quoted amount, including zero.
priv enum ClientLocalMetadataQuote {
  MetadataNotApplicable
  MetadataQuoted(Int64)
  MetadataUnavailable
}

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
  graph_offset : Int
  _retained_result_envelope : ClientLocalResultEnvelope?
  publication : ClientLocalResultPublicationPlan?
  schema_inventory : ClientLocalSchemaProofInventory?
  demand_inventory : ClientLocalSchemaProofInventory?
  value_node_demand : ClientLocalValueNodeDemand?
  scalar_demand : ClientLocalScalarDemand?
  values : @execution.ValueLimits
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  max_value_bytes : Int
  imports : @local.LocalImportLimits
  exports : @local.LocalExportLimits
  metadata : @local_driver.LocalManagedMetadataLimits
  metadata_retained_bytes : Int64
  metadata_quote : ClientLocalMetadataQuote
}

///|
fn client_local_capacity_plan(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
  scalar_values? : Bool = false,
  graph? : @strategy.CheckedDAG? = None,
  graph_offset? : Int = 0,
  content? : ClientInstalledEffectContentPreparation? = None,
  source_free_max_work? : Int? = None,
) -> ClientLocalCapacityPlan {
  let ordinary_inventory = if scalar_values {
    client_local_schema_proof_inventory(sequences, graph~, graph_offset~)
  } else {
    None
  }
  let inventory = match ordinary_inventory {
    Some(value) => Some(value)
    None =>
      if scalar_values {
        client_local_schema_proof_inventory(
          sequences,
          graph~,
          graph_offset~,
          closed_carriers=true,
        )
      } else {
        None
      }
  }
  let ordinary_node_inventory = match inventory {
    Some(value) => Some(value)
    None =>
      if scalar_values {
        client_local_schema_proof_inventory(
          sequences,
          graph~,
          graph_offset~,
          scalar_only=false,
          leaf_only=true,
          content~,
        )
      } else {
        None
      }
  }
  let node_inventory = match ordinary_node_inventory {
    Some(value) => Some(value)
    None =>
      if scalar_values {
        client_local_schema_proof_inventory(
          sequences,
          graph~,
          graph_offset~,
          scalar_only=false,
          leaf_only=true,
          closed_carriers=true,
        )
      } else {
        None
      }
  }
  let dispatch_inventory = match node_inventory {
    Some(value) => Some(value)
    None =>
      client_local_schema_proof_inventory(
        sequences,
        graph~,
        graph_offset~,
        scalar_only=false,
      )
  }
  let dispatch_bounds = client_local_dispatch_bounds(dispatch_inventory, graph)
  let admitted_rows = max_rows
  let max_rows = match dispatch_inventory {
    Some({ closed_rows: Some(bound), .. }) =>
      Int::min(max_rows, Int::max(1, bound))
    _ => max_rows
  }
  let scalar_demand = match inventory {
    Some(proof) => client_local_scalar_demand(proof, max_rows)
    None => None
  }
  let value_node_demand = match node_inventory {
    Some(proof) => client_local_value_node_demand(proof, max_rows)
    None => None
  }
  let (values, execution, measurement) = client_local_execution_limits(
    max_rows~,
    scalar_inventory=inventory,
    scalar_demand~,
    value_node_demand~,
    source_free_max_work~,
  )
  let original_values_text = if scalar_demand is None {
    value_node_demand.bind(demand => {
      match client_local_original_values_text_bound(sequences, demand) {
        Some(value) if value.0 > values.max_text_bytes => Some(value)
        _ => None
      }
    })
  } else {
    None
  }
  let value_node_demand = if scalar_demand is None &&
    value_node_demand is Some(original) {
    Some({
      ..original,
      text_bound: match original_values_text {
        Some((bytes, _, _)) => Some(bytes)
        None =>
          match content {
            Some(selected) =>
              installed_content_text_bound(
                selected,
                sequences,
                original,
                values.max_text_bytes,
              )
            None =>
              client_local_decimal_text_bound(
                sequences,
                original,
                values.max_text_bytes,
              )
          }
      },
    })
  } else {
    value_node_demand
  }
  // The SAME contextual inventory sums every original input port and output
  // schema before taking their maximum. The physical guard shares one node
  // budget across input and final-output scans; two sides bound that budget.
  // Configure its actual constructor as well as the quote. Unknown/foreign
  // references keep the original envelope; byte/depth/work and Fragment
  // execution limits are independent and remain unchanged. Captured suffixes
  // use the same complete record proof, including Event record projections;
  // Carrier-private storage is not measured as a synthetic row here.
  let measurement = if (content is Some(_) || graph_offset > 0) &&
    value_node_demand is Some(demand) &&
    demand.nodes <= 1073741823 {
    {
      ..measurement,
      max_nodes: Int::min(measurement.max_nodes, 2 * demand.nodes),
    }
  } else {
    measurement
  }
  // IO observes scalar cells plus row field names, not evaluator intermediates.
  // Keep expression text independent unless every original typed child and
  // generated step has a separate text-free proof.
  let decimal_text = value_node_demand.bind(demand => demand.text_bound)
  let io_text = match scalar_demand {
    Some(demand) => Some(demand.name_bytes)
    None => decimal_text
  }
  let values = match io_text {
    Some(bytes) => { ..values, max_text_bytes: bytes, }
    None => values
  }
  let execution = if io_text is Some(bytes) &&
    (
      decimal_text is Some(_) ||
      client_local_text_free_scalar_sequences(sequences)
    ) {
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
  let measurement = match original_values_text {
    Some((_, wire, _)) =>
      { ..measurement, max_bytes: Int::max(measurement.max_bytes, wire), }
    None => measurement
  }
  let original_imports = client_local_import_limits_for_rows(max_rows, values)
  let original_exports = client_local_export_limits(max_rows, values)
  let fields = dispatch_inventory.map(value => value.fields)
  let imports = {
    ..original_imports,
    wire: {
      ..original_imports.wire,
      max_columns: fields.unwrap_or(original_imports.wire.max_columns),
      max_nodes: match value_node_demand {
        Some(demand) => demand.nodes + 3
        None => original_imports.wire.max_nodes
      },
    },
  }
  let exports = {
    ..original_exports,
    wire: {
      ..original_exports.wire,
      max_columns: fields.unwrap_or(original_exports.wire.max_columns),
      max_nodes: match value_node_demand {
        Some(demand) => demand.nodes + 3
        None => original_exports.wire.max_nodes
      },
    },
  }
  // Snapshot metadata before any independently proved wire specialization.
  let metadata : @local_driver.LocalManagedMetadataLimits = {
    name_bytes: imports.wire.max_bytes,
    bridge_entries: original_imports.wire.max_nodes,
    completion_entries: original_imports.wire.max_nodes,
    schema: {
      max_fields: imports.wire.max_columns,
      max_bytes: imports.wire.max_bytes,
      max_nodes: original_imports.wire.max_nodes,
      max_depth: imports.wire.max_depth,
    },
    result_workspace_entries: imports.max_rows,
    result_rows_reserved: if scalar_values {
      Some(1)
    } else {
      None
    },
    retained_bytes: 0L,
  }
  // These are working/transport extents of the SAME checked Values, not new
  // policy or capacity. Quote and provider construction consume them together;
  // the original Ledger and operator facility still admit the resulting cost.
  let imports = match original_values_text {
    Some((text, wire, row_wire)) =>
      {
        ..imports,
        wire: {
          ..imports.wire,
          max_bytes: Int::max(imports.wire.max_bytes, wire),
        },
        row: {
          ..imports.row,
          max_bytes: Int::max(
            imports.row.max_bytes,
            Int::min(row_wire, 16777216),
          ),
          max_text_bytes: Int::max(
            imports.row.max_text_bytes,
            Int::min(text, row_wire),
          ),
        },
        max_batch_bytes: Int::max(
          imports.max_batch_bytes,
          Int::min(row_wire, 16777216),
        ),
      }
    None => imports
  }
  let exports = match original_values_text {
    Some((_, wire, row_wire)) =>
      {
        ..exports,
        wire: {
          ..exports.wire,
          max_bytes: Int::max(exports.wire.max_bytes, wire),
        },
        // Keep the existing export constructor's 16MiB batch ceiling. Total
        // wire demand is distinct; oversized actual rows still refuse there.
        max_batch_bytes: Int::max(
          exports.max_batch_bytes,
          Int::min(row_wire, 16777216),
        ),
      }
    None => exports
  }
  // The same producer proof bounds every JSON node, including its opaque
  // reference envelope; arbitrary ContentRef still has no such proof. Use a
  // conservative punctuation/numeric envelope per node and escaped text.
  let content_wire = if content is Some(_) &&
    decimal_text is Some(bytes) &&
    value_node_demand is Some(demand) {
    client_local_json_leaf_wire_byte_bound(demand.nodes, 1, bytes.to_int64())
  } else {
    None
  }
  let imports = match content_wire {
    Some(bytes) =>
      {
        ..imports,
        wire: {
          ..imports.wire,
          max_bytes: Int::min(imports.wire.max_bytes, bytes),
        },
      }
    None => imports
  }
  let exports = match content_wire {
    Some(bytes) =>
      {
        ..exports,
        wire: {
          ..exports.wire,
          max_bytes: Int::min(exports.wire.max_bytes, bytes),
        },
      }
    None => exports
  }
  // Value admission follows the selected finite value/measurement policy.
  // Row framing keeps its small initial window: actual measured output grows
  // the same Task workspace before allocating a larger export batch.
  let max_value_bytes = if scalar_demand is Some(_) {
    10000
  } else {
    Int::max(
      10000,
      Int::min(
        // Total wire demand can exceed a single supported physical frame.
        // Preserve the existing Local/framer 16MiB bound for one value.
        Int::min(
          16777216,
          Int::max(imports.row.max_bytes, imports.wire.max_bytes),
        ),
        measurement.max_bytes,
      ),
    )
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
    client_local_scalar_metadata_envelope(proof, original, 1, envelope)
  } else {
    None
  }
  let metadata_quote = client_local_result_metadata_quote(
    graph, scalar_values, result_envelope, 1,
  )
  // Unavailable Plans carry no usable metadata amount and cannot pass either
  // the typed constructor refusal or the original Plan matcher below.
  let result_metadata = match metadata_quote {
    MetadataQuoted(bytes) => bytes
    MetadataNotApplicable | MetadataUnavailable => 0L
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
        graph_offset,
        _retained_result_envelope: result_envelope,
        publication,
        schema_inventory: inventory,
        demand_inventory: dispatch_inventory,
        value_node_demand,
        // A general metadata layout does not invalidate the independently
        // checked schema demand already used by this Plan's value policy.
        scalar_demand,
        values,
        execution,
        measurement,
        max_value_bytes,
        imports,
        exports,
        metadata: {
          ..metadata,
          retained_bytes: result_metadata,
          result_workspace_entries: if result_metadata > 0L {
            result_envelope
            .map(value => value.workspace_entries)
            .unwrap_or(metadata.result_workspace_entries)
          } else {
            metadata.result_workspace_entries
          },
        },
        metadata_retained_bytes: result_metadata,
        metadata_quote,
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
        graph_offset,
        _retained_result_envelope: result_envelope,
        publication,
        schema_inventory: inventory,
        demand_inventory: dispatch_inventory,
        value_node_demand,
        scalar_demand,
        values,
        execution,
        measurement,
        max_value_bytes,
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
        metadata_quote: MetadataQuoted(extra),
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
  match plan.metadata_quote {
    MetadataUnavailable => return false
    MetadataNotApplicable =>
      if plan.graph is Some(_) || plan.metadata_retained_bytes != 0L {
        return false
      }
    MetadataQuoted(bytes) =>
      if bytes != plan.metadata_retained_bytes {
        return false
      }
  }
  if plan.graph_offset < 0 {
    return false
  }
  match plan.graph {
    Some(graph) => {
      let count = @strategy.graph_task_count(graph)
      if plan.graph_offset > count ||
        sequences.length() != count - plan.graph_offset {
        return false
      }
      for index, sequence in sequences {
        guard @strategy.graph_task_owner(graph, index + plan.graph_offset)
          is Some(original) &&
          physical_equal(
            original,
            @execution.generated_sequence_owner(sequence),
          ) else {
          return false
        }
      }
    }
    None => if plan.graph_offset != 0 { return false }
  }
  if plan.metadata.retained_bytes != plan.metadata_retained_bytes ||
    (
      plan.graph is Some(_) &&
      plan.metadata_retained_bytes < client_local_cleanup_retained_bytes()
    ) ||
    (plan.schema_inventory is Some(_) && plan.scalar_demand is None) ||
    !physical_equal(plan.resource_policy, client_local_resource_policy()) ||
    plan.admitted_rows != max_rows ||
    plan.sequences.length() != sequences.length() {
    return false
  }
  if plan.scalar_demand is Some(demand) &&
    !(plan.schema_inventory is Some(original) &&
    physical_equal(original, demand.original) &&
    demand.rows == plan.execution.rows.max_rows &&
    demand.value_nodes == plan.values.max_nodes) {
    return false
  }
  if plan.value_node_demand is Some(demand) &&
    !(plan.demand_inventory is Some(original) &&
    physical_equal(original, demand.original) &&
    demand.rows == plan.execution.rows.max_rows &&
    demand.nodes == plan.values.max_nodes &&
    client_local_inventory_nodes(original, demand.rows) == Some(demand.nodes)) {
    return false
  }
  if plan.value_node_demand is Some({ text_bound: Some(bytes), .. }) &&
    (
      plan.scalar_demand is Some(_) ||
      bytes < 0 ||
      plan.values.max_text_bytes != bytes ||
      plan.execution.rows.input_values.max_text_bytes != bytes ||
      plan.execution.rows.output_values.max_text_bytes != bytes
    ) {
    return false
  }
  if plan.value_node_demand is None &&
    plan.scalar_demand is None &&
    plan.values.max_nodes != client_local_general_value_nodes() {
    return false
  }
  if plan.demand_inventory is Some({ closed_rows: Some(bound), .. }) &&
    plan.execution.rows.max_rows != Int::min(max_rows, Int::max(1, bound)) {
    return false
  }
  for index, sequence in sequences {
    if !physical_equal(plan.sequences[index], sequence) {
      return false
    }
  }
  true
}

///|
fn client_local_result_metadata_quote(
  graph : @strategy.CheckedDAG?,
  scalar_values : Bool,
  envelope : ClientLocalResultEnvelope?,
  rows : Int,
) -> ClientLocalMetadataQuote {
  guard graph is Some(original) else { return MetadataNotApplicable }
  if !scalar_values || @strategy.graph_result_count(original) == 0 {
    return MetadataQuoted(client_local_cleanup_retained_bytes())
  }
  guard envelope is Some(original_envelope) else { return MetadataUnavailable }
  match
    client_local_result_metadata_retained(
      original_envelope,
      rows,
      client_node_publication_schema_bytes(),
    ) {
    Some(bytes) => MetadataQuoted(bytes)
    None => MetadataUnavailable
  }
}
