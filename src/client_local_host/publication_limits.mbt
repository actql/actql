///|
/// The independent Node publication schema byte ceiling, also consumed by the
/// independent retained publication quote; this does not use payload wire.
fn client_node_publication_schema_bytes() -> Int {
  100000
}

///|
priv struct ClientLocalResultPublicationPlan {
  rows : Int
  envelope : ClientLocalResultEnvelope?
  wire_bytes : Int?
  schema_bytes : Int
  order_work : Int
}

///|
fn client_local_result_publication_plan(
  graph : @strategy.CheckedDAG,
  rows : Int,
  envelope : ClientLocalResultEnvelope?,
) -> ClientLocalResultPublicationPlan {
  let schema_limits : @execution.RelationSchemaIdentityLimits = {
    max_fields: envelope.map(value => value.fields).unwrap_or(100),
    max_bytes: client_node_publication_schema_bytes(),
    max_nodes: 10000,
    max_depth: 64,
  }
  {
    rows,
    envelope,
    // Unordered Result view construction still initializes each row index.
    // Ordered comparison keeps its independent finite phase guard; metadata
    // entry capacity is a different unit and cannot replace this work budget.
    order_work: if envelope is Some(value) && value.order_terms == 0 {
      rows
    } else {
      10000
    },
    wire_bytes: client_local_result_scalar_wire_bytes(graph, rows),
    schema_bytes: client_local_result_schema_bytes(graph, schema_limits).unwrap_or(
      schema_limits.max_bytes,
    ),
  }
}

///|
fn client_node_publication_limits(
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
  original : ClientLocalCapacityPlan,
) -> @publication_host.PublicationOutputExportLimits? {
  if max_payload_bytes < 1 {
    return None
  }
  let profile_rows = @publication_host.prepared_client_values_max_rows(prepared)
  let graph = @publication_host.prepared_client_graph(prepared)
  if original.admitted_rows != profile_rows ||
    !(original.graph is Some(owner) && physical_equal(owner, graph)) {
    return None
  }
  client_node_publication_limits_original(max_payload_bytes, original)
}

///|
/// Only the existing immutable Plan has checked its graph and row domain.
fn client_node_publication_limits_original(
  max_payload_bytes : Int,
  original : ClientLocalCapacityPlan,
) -> @publication_host.PublicationOutputExportLimits? {
  if max_payload_bytes < 1 {
    return None
  }
  guard original.publication is Some(publication) else { return None }
  let rows = publication.rows
  let envelope = publication.envelope
  let exported = original.exports
  let wire_proof = publication.wire_bytes
  // Consume the SAME admitted export envelope. A second Node recipe must not
  // impose unrelated value/Text/node maxima on an already quoted Plan. The
  // caller's separate Store-object policy may still be tighter.
  let bytes = Int::min(
    max_payload_bytes,
    Int::min(
      exported.wire.max_bytes,
      wire_proof.unwrap_or(exported.wire.max_bytes),
    ),
  )
  // The Node logical Relation wrapper adds three nodes and two levels; those
  // representation offsets are not extra row/value or Resource permission.
  if exported.wire.max_nodes > 2147483644 ||
    exported.wire.max_depth > 2147483645 {
    return None
  }
  let schema_limits : @execution.RelationSchemaIdentityLimits = {
    max_fields: envelope.map(value => value.fields).unwrap_or(100),
    max_bytes: client_node_publication_schema_bytes(),
    max_nodes: 10000,
    max_depth: 64,
  }
  let schema_bytes = publication.schema_bytes
  Some({
    max_result_fields: envelope.map(value => value.fields).unwrap_or(10),
    max_result_mapping_work: envelope
    .map(value => value.mapping_work)
    .unwrap_or(1000),
    max_result_order_work: publication.order_work,
    max_result_workspace_entries: envelope
    .map(value => value.publication_workspace_entries)
    .unwrap_or(original.metadata.result_workspace_entries),
    max_rows: rows,
    // The existing Node row codec keeps its independent recursion policy.
    // A larger checked value envelope does not widen that format boundary.
    values: {
      ..exported.values,
      max_depth: Int::min(exported.values.max_depth, 64),
    },
    payload_wire: {
      ..exported.wire,
      max_bytes: bytes,
      max_depth: Int::min(exported.wire.max_depth, 64),
      max_columns: envelope
      .map(value => value.fields)
      .unwrap_or(exported.wire.max_columns),
    },
    logical_wire: {
      ..exported.wire,
      max_bytes: bytes,
      max_nodes: exported.wire.max_nodes + 3,
      max_depth: Int::min(exported.wire.max_depth, 64) + 2,
      max_columns: envelope
      .map(value => value.fields)
      .unwrap_or(exported.wire.max_columns),
    },
    schema: { ..schema_limits, max_bytes: schema_bytes, },
    max_batch_bytes: exported.max_batch_bytes,
  })
}

///|
/// Native publication projects the same checked execution plan retained by
/// its requirements owner. Decoder, schema and Store guards remain distinct
/// from the plan's value, Result and wire dimensions.
pub fn ClientLocalRequirements::publication_limits(
  self : ClientLocalRequirements,
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> (
  @execution.RetainedRowDecodeLimits,
  @publication_host.PublicationOutputExportLimits,
)? {
  if !physical_equal(self.prepared, prepared) || max_payload_bytes < 1 {
    return None
  }
  let plan = self.capacity_plan
  guard plan.graph is Some(graph) &&
    physical_equal(graph, @publication_host.prepared_client_graph(prepared)) &&
    plan.publication is Some(publication) else {
    return None
  }
  let exported = plan.exports
  let wire = @execution.RowWireLimits::{
    ..exported.wire,
    max_bytes: Int::min(max_payload_bytes, exported.wire.max_bytes),
  }
  let envelope = publication.envelope
  Some(
    (
      plan.imports.row,
      {
        max_result_fields: envelope
        .map(value => value.fields)
        .unwrap_or(exported.wire.max_columns),
        max_result_mapping_work: envelope
        .map(value => value.mapping_work)
        .unwrap_or(plan.execution.rows.metadata_entries),
        max_result_order_work: publication.order_work,
        // This is the already-quoted Named Result index workspace, not the
        // independent bridge/evidence metadata entry ceilings below.
        max_result_workspace_entries: envelope
        .map(value => value.publication_workspace_entries)
        .unwrap_or(plan.metadata.result_workspace_entries),
        max_rows: exported.max_rows,
        values: exported.values,
        payload_wire: wire,
        logical_wire: wire,
        schema: {
          max_fields: exported.wire.max_columns,
          max_bytes: Int::min(65536, max_payload_bytes),
          max_nodes: 8192,
          max_depth: 64,
        },
        max_batch_bytes: Int::min(exported.max_batch_bytes, max_payload_bytes),
      },
    ),
  )
}

///|
/// The original bridge and evidence-check entry bounds remain independent of
/// Named Result row indices. Poll quantum/rounds still bound traversal work.
/// These immutable counts supply no allocation or current authorization.
pub fn ClientLocalRequirements::publication_entry_limits(
  self : ClientLocalRequirements,
  prepared : @publication_host.PreparedClientProgram,
) -> (Int, Int)? {
  if !physical_equal(self.prepared, prepared) {
    return None
  }
  let rows = self.capacity_plan.execution.rows
  if rows.metadata_entries < 1 || rows.retained_entries < 1 {
    return None
  }
  Some((rows.metadata_entries, rows.retained_entries))
}
