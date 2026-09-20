///|
/// Evidence produced by the bounded Graph builder for one exact output.
/// It is neither a content identity nor a physical storage estimate.
struct Evidence {
  mode : @storage.Mode
  input_rows : Int
  measured_value_bytes : Int
  retained_value_bytes : Int
  construction_work : Int
  workspace_slots : Int
}

///|
/// A Graph output builder whose retention verifier is installed before any
/// values are accepted. No partial Graph can escape this value.
struct OutputBuilder {
  graph : @storage.Builder
  retention : @lifecycle.RetentionPort[
    @storage.Storage,
    Evidence,
    @storage.Storage,
  ]
  mut open : Bool
}

///|
struct Completed {
  core : @lifecycle.Completed[Evidence, @storage.Storage]
}

///|
struct CompletionReference {
  core : @lifecycle.CompletionReference
}

///|
struct ProducerRead {
  core : @lifecycle.ProducerRead[Evidence, @storage.Storage]
}

///|
pub(all) enum Issue {
  Lifecycle(@lifecycle.Issue)
  Storage(@storage.Issue)
  Producer(@lifecycle.ProducerReadIssue)
  InvalidStorageBytes
  Closed
} derive(Eq, Debug)

///|
pub fn prepare_output(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  mode : @storage.Mode,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[OutputBuilder, Issue] {
  if storage_bytes < 0L {
    return Err(InvalidStorageBytes)
  }
  let binding = match @lifecycle.prepare_binding(owner, target) {
    Ok(value) => value
    Err(issue) => return Err(Lifecycle(issue))
  }
  if @lifecycle.binding_kind(binding) != @carrier.GraphKind {
    return Err(Lifecycle(@lifecycle.WrongCarrier))
  }
  let graph = match
    @storage.prepare(@lifecycle.binding_carrier(binding), mode, limits) {
    Ok(value) => value
    Err(issue) => return Err(Storage(issue))
  }
  let retention = @lifecycle.prepare_retention_port(binding, (
    material : @storage.Storage,
  ) => {
    let receipt = match
      @lifecycle.complete_receipt(
        binding,
        @lifecycle.GraphMeasure(
          nodes=@storage.node_count(material),
          edges=@storage.edge_count(material),
        ),
      ) {
      Ok(value) => value
      Err(_) => return None
    }
    let evidence : Evidence = {
      mode: @storage.mode(material),
      input_rows: @storage.input_row_count(material),
      measured_value_bytes: @storage.measured_input_value_bytes(material),
      retained_value_bytes: @storage.retained_value_bytes(material),
      construction_work: @storage.construction_work(material),
      workspace_slots: @storage.retained_workspace_slots(material),
    }
    Some((receipt, evidence, material, storage_bytes, available))
  })
  Ok({ graph, retention, open: true, })
}

///|
pub fn append_node(
  output : OutputBuilder,
  identity : @value.CheckedValue,
  properties : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  if !output.open {
    return Err(Closed)
  }
  @storage.append_node(output.graph, identity, properties).map_err(issue => {
    output.open = false
    @lifecycle.cancel_retention_port(output.retention) |> ignore
    Storage(issue)
  })
}

///|
pub fn append_edge(
  output : OutputBuilder,
  source : @value.CheckedValue,
  target : @value.CheckedValue,
  label : @value.CheckedValue?,
  properties : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  if !output.open {
    return Err(Closed)
  }
  @storage.append_edge(output.graph, source, target, label, properties).map_err(issue => {
      output.open = false
      @lifecycle.cancel_retention_port(output.retention) |> ignore
      Storage(issue)
    },
  )
}

///|
pub fn contains_declared_node(
  output : OutputBuilder,
  identity : @value.CheckedValue,
) -> Result[Bool, Issue] {
  if !output.open {
    return Err(Closed)
  }
  @storage.contains_declared_node(output.graph, identity).map_err(issue => {
    Storage(issue)
  })
}

///|
pub fn cancel_output(output : OutputBuilder) -> Bool {
  output.open = false
  let storage = @storage.cancel(output.graph)
  let retention = @lifecycle.cancel_retention_port(output.retention)
  storage || retention
}

///|
pub fn finish_output(output : OutputBuilder) -> Result[Completed, Issue] {
  if !output.open {
    return Err(Closed)
  }
  output.open = false
  let graph = match @storage.finish(output.graph) {
    Ok(value) => value
    Err(issue) => {
      @lifecycle.cancel_retention_port(output.retention) |> ignore
      return Err(Storage(issue))
    }
  }
  let retained = match @lifecycle.retain(output.retention, graph) {
    Ok(value) => value
    Err(issue) => return Err(Lifecycle(issue))
  }
  match @lifecycle.complete(retained) {
    Ok(value) => Ok({ core: value, })
    Err(issue) => Err(Lifecycle(issue))
  }
}

///|
pub fn completed_available(value : Completed) -> Bool {
  @lifecycle.completed_available(value.core)
}

///|
/// Reclaim a completed generation rejected before downstream handoff.
pub fn discard_completed(value : Completed) -> Bool {
  @lifecycle.reclaim_completed(value.core, storage => {
    @storage.discard(storage)
    true
  })
}

///|
pub fn completed_measure(value : Completed) -> @lifecycle.Measure {
  @lifecycle.completed_measure(value.core)
}

///|
pub fn completed_storage(value : Completed) -> @storage.Storage? {
  if completed_available(value) {
    @lifecycle.completed_payload(value.core)
  } else {
    None
  }
}

///|
pub fn completed_storage_bytes(value : Completed) -> Int64? {
  @lifecycle.completed_storage_bytes(value.core)
}

///|
pub fn completed_evidence(value : Completed) -> Evidence? {
  if completed_available(value) {
    @lifecycle.completed_evidence(value.core)
  } else {
    None
  }
}

///|
pub fn evidence_mode(value : Evidence) -> @storage.Mode {
  value.mode
}

///|
pub fn evidence_input_rows(value : Evidence) -> Int {
  value.input_rows
}

///|
pub fn evidence_measured_value_bytes(value : Evidence) -> Int {
  value.measured_value_bytes
}

///|
pub fn evidence_retained_value_bytes(value : Evidence) -> Int {
  value.retained_value_bytes
}

///|
pub fn evidence_construction_work(value : Evidence) -> Int {
  value.construction_work
}

///|
pub fn evidence_workspace_slots(value : Evidence) -> Int {
  value.workspace_slots
}

///|
pub fn completed_reference(value : Completed) -> CompletionReference {
  { core: @lifecycle.completion_reference(value.core), }
}

///|
pub fn completed_carrier_reference(
  value : Completed,
) -> @lifecycle.CompletionReference {
  @lifecycle.completion_reference(value.core)
}

///|
pub fn completed_reference_available(value : CompletionReference) -> Bool {
  @lifecycle.completion_reference_available(value.core)
}

///|
pub fn prepare_producer_read(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : Completed,
) -> Result[ProducerRead, Issue] {
  match
    @lifecycle.prepare_producer_read(
      receiver,
      input_index,
      expected_producer,
      output.core,
    ) {
    Ok(value) => Ok({ core: value, })
    Err(issue) => Err(Producer(issue))
  }
}

///|
/// Bind a completed Graph generation to one exact downstream step edge in
/// the same checked sequence.
pub fn prepare_step_read(
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
  output : Completed,
) -> Result[ProducerRead, Issue] {
  match
    @lifecycle.prepare_step_producer_read(
      receiver,
      consumer_step,
      input_index,
      output.core,
    ) {
    Ok(value) => Ok({ core: value, })
    Err(issue) => Err(Producer(issue))
  }
}

///|
pub fn producer_read_available(value : ProducerRead) -> Bool {
  @lifecycle.producer_read_available(value.core)
}

///|
pub fn producer_read_receiver(value : ProducerRead) -> @lower.BoundPrepared {
  @lifecycle.producer_read_receiver(value.core)
}

///|
pub fn producer_read_input_index(value : ProducerRead) -> Int {
  @lifecycle.producer_read_input_index(value.core)
}

///|
pub fn producer_read_same(left : ProducerRead, right : ProducerRead) -> Bool {
  @lifecycle.producer_read_same(left.core, right.core)
}

///|
pub fn producer_read_storage(value : ProducerRead) -> @storage.Storage? {
  @lifecycle.producer_read_payload(value.core)
}

///|
pub fn producer_read_matches_reference(
  value : ProducerRead,
  reference : CompletionReference,
) -> Bool {
  @lifecycle.producer_read_matches_reference(value.core, reference.core)
}

///|
pub fn producer_read_carrier_reference(
  value : ProducerRead,
) -> @lifecycle.ProducerReadReference {
  @lifecycle.producer_read_reference(value.core)
}

///|
/// Expose the exact Graph read as a common structural view. The view keeps the
/// producer occurrence and availability checks without exporting Storage.
pub fn producer_read_view(
  value : ProducerRead,
) -> Result[@lifecycle.ProducerView, Issue] {
  guard producer_read_storage(value) is Some(storage) &&
    @storage.carrier(storage) is @carrier.GraphValue(graph) else {
    return Err(Producer(@lifecycle.ProducerUnavailable))
  }
  @lifecycle.prepare_graph_producer_view(
    producer_read_carrier_reference(value),
    @storage.node_count(storage),
    @storage.edge_count(storage),
    @carrier.field_count(@carrier.graph_node_properties(graph)),
    @carrier.field_count(@carrier.graph_edge_properties(graph)),
    node => @storage.node_identity(storage, node),
    (node, property) => @storage.node_property(storage, node, property),
    edge => @storage.edge_endpoints(storage, edge),
    edge => @storage.edge_label(storage, edge),
    (edge, property) => @storage.edge_property(storage, edge, property),
  ).map_err(issue => {
    Lifecycle(
      match issue {
        @lifecycle.WrongCarrier => @lifecycle.WrongCarrier
        @lifecycle.InvalidExtent => @lifecycle.InvalidMeasure
        @lifecycle.Unavailable => @lifecycle.Unavailable
        @lifecycle.InvalidRecord | @lifecycle.InvalidField =>
          @lifecycle.Unverified
      },
    )
  })
}

///|
/// Match a Graph read to the exact checked occurrence edge it supplies.
pub fn producer_read_matches_operation_input(
  value : ProducerRead,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  edge_index : Int,
) -> Bool {
  @lifecycle.producer_read_reference_matches_operation_input(
    producer_read_carrier_reference(value),
    receiver,
    consumer_step,
    edge_index,
  )
}
