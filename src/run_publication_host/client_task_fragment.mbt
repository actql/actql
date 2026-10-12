///|
/// One checked Carrier task projected as an AoA Plan node. The input
/// contracts identify ports; the Plan graph must still bind their producers.
pub struct ClientTaskFragmentNode {
  wire : String
  node_id : String
  output_port : String
  logical_cid : String
  output_contract_cid : String
  output_carrier : String
}

///|
pub(all) enum ClientTaskFragmentIssue {
  InvalidLimits
  Pipeline(ClientTaskPipelineIssue)
  MissingTask
  MissingOutput
  UnsupportedCarrier
  UnrepresentableContract
  Encoding
}

///|
pub(all) enum ClientTaskFragmentAdmissionIssue {
  Issue(ClientTaskFragmentIssue)
  MismatchedNode
}

///|
pub fn client_task_fragment_wire(value : ClientTaskFragmentNode) -> String {
  value.wire
}

///|
pub fn client_task_fragment_node_id(value : ClientTaskFragmentNode) -> String {
  value.node_id
}

///|
pub fn client_task_fragment_output_port(
  value : ClientTaskFragmentNode,
) -> String {
  value.output_port
}

///|
pub fn client_task_fragment_logical_cid(
  value : ClientTaskFragmentNode,
) -> String {
  value.logical_cid
}

///|
pub fn client_task_fragment_output_contract_cid(
  value : ClientTaskFragmentNode,
) -> String {
  value.output_contract_cid
}

///|
fn client_task_carrier_sort(carrier : @carrier.Carrier) -> String {
  match @carrier.kind(carrier) {
    RelationKind => "relation"
    GraphKind => "graph"
    EventsKind => "events"
    VectorsKind => "vectors"
  }
}

///|
fn client_task_carrier_kind(sort : String) -> @carrier.Kind? {
  match sort {
    "relation" => Some(RelationKind)
    "graph" => Some(GraphKind)
    "events" => Some(EventsKind)
    "vectors" => Some(VectorsKind)
    _ => None
  }
}

///|
fn client_task_record_role(name : @schema.FieldName) -> String? {
  match name {
    @schema.Unqualified(value) => Some(value)
    @schema.Qualified(_, _) => None
  }
}

///|
/// The existing 0.1 structural body keeps roles separate from row fields.
/// It is a bare Carrier contract CID, not a Contract Envelope or data CID.
fn client_task_record_carrier_contract(
  carrier : @carrier.Carrier,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (String, String)? {
  let records = match carrier {
    @carrier.EventValue(events) => @carrier.event_records(events)
    @carrier.VectorValue(vectors) => @carrier.vector_records(vectors)
    _ => return None
  }
  guard @carrier.complete_schema(records) is Some(schema) &&
    @schema.as_object(schema) is Some(row) else {
    return None
  }
  try {
    let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    match carrier {
      @carrier.EventValue(events) => {
        guard client_task_record_role(@carrier.event_identity(events).name)
          is Some(id) &&
          client_task_record_role(@carrier.event_time(events).name)
          is Some(time) else {
          return None
        }
        @encode.key(writer, "id")
        @encode.string_value(writer, id)
        @encode.key(writer, "records")
        @contract.emit_checked(row, writer)
        @encode.key(writer, "time")
        @encode.string_value(writer, time)
        @encode.key(writer, "version")
        @encode.string_value(writer, "actql-events-contract/0.1")
      }
      @carrier.VectorValue(vectors) => {
        guard client_task_record_role(@carrier.vector_components(vectors).name)
          is Some(components) else {
          return None
        }
        @encode.key(writer, "components")
        @encode.string_value(writer, components)
        @encode.key(writer, "ids")
        @encode.begin_array(writer)
        for index in 0..<@carrier.vector_identity_count(vectors) {
          guard @carrier.vector_identity_at(vectors, index) is Some(field) &&
            client_task_record_role(field.name) is Some(name) else {
            return None
          }
          @encode.string_value(writer, name)
        }
        @encode.end_array(writer)
        @encode.key(writer, "records")
        @contract.emit_checked(row, writer)
        @encode.key(writer, "version")
        @encode.string_value(writer, "actql-vectors-contract/0.1")
      }
      _ => return None
    }
    @encode.end_object(writer)
    Some(
      (
        client_task_carrier_sort(carrier),
        "sha256:" + @encode.finish_hash(writer),
      ),
    )
  } catch {
    _ => None
  }
}

///|
fn client_task_carrier_contract(
  carrier : @carrier.Carrier,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (String, String)? {
  match @carrier.kind(carrier) {
    RelationKind => {
      guard @carrier.relation_rows(carrier) is Some(rows) &&
        @carrier.complete_schema(rows) is Some(schema) else {
        return None
      }
      // Conditional Relation fields are not optional ordinary object fields.
      // Bind the existing presence-aware schema owner at both task ports;
      // publication still requires a projection to guaranteed columns.
      if !@schema.all_fields_required(schema) {
        return @execution.identify_relation_schema(schema, {
            max_fields: max_nodes,
            max_bytes: max_wire_bytes,
            max_nodes,
            max_depth,
          })
          .map(identity => {
            ("relation", @execution.relation_schema_cid(identity))
          })
          .to_option()
      }
      guard @schema.as_object(schema) is Some(row) else { return None }
      let output_hash = @encode.hashing_writer(
        max_wire_bytes, max_nodes, max_depth,
      ) catch {
        _ => return None
      }
      @contract.emit_checked(row, output_hash) catch {
        _ => return None
      }
      let cid = @encode.finish_hash(output_hash) catch { _ => return None }
      Some(("relation", "sha256:" + cid))
    }
    GraphKind =>
      // Public task ports use the keyed contract exclusively. Old carrier
      // bodies are not an alternative admission path after a failed check.
      match
        @graph_contract.admit(carrier, {
          max_bytes: max_wire_bytes,
          max_nodes,
          max_depth,
        }) {
        Ok(contract) => Some(("graph", @graph_contract.cid(contract)))
        Err(_) => None
      }
    EventsKind | VectorsKind =>
      client_task_record_carrier_contract(
        carrier, max_wire_bytes, max_nodes, max_depth,
      )
  }
}

///|
/// Seal the checked task pipeline and complete Carrier port types together.
/// Physical source capture, producer edges, Result roots, and resource facts
/// are separate admission obligations before an Executable Plan is issued.
pub fn issue_prepared_client_task_fragment(
  value : PreparedClientProgram,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let pipeline_wire = match
    emit_prepared_client_task_pipeline(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(Pipeline(issue))
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    client_task_output_target(value.graph, task) is Some(target) else {
    return Err(MissingTask)
  }
  issue_client_task_fragment_body(
    owner,
    target,
    @strategy.graph_task_selected_step(value.graph, task),
    "task_" + task.to_string(),
    pipeline_wire,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Seal only the pure prefix that supplies an Infer acquisition. This is
/// adjacent computation, not an Infer Plan or an execution authorization.
pub fn issue_prepared_client_infer_prefix_fragment(
  value : PreparedClientProgram,
  task : Int,
  infer_step : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  guard client_infer_metadata_owner(value, task, infer_step) is Some(owner) &&
    @lower.node_at(@lower.bound_preparation(owner), infer_step - 1) is Some(_) else {
    return Err(MissingOutput)
  }
  issue_client_infer_prefix_fragment_for_owner(
    owner, task, infer_step, sequence_limits, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Both the existing component and the composed occurrence retain the original
/// bound preparation. This helper only lowers its pure pre-Model computation.
fn issue_client_infer_prefix_fragment_for_owner(
  owner : @lower.BoundPrepared,
  task : Int,
  infer_step : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  if infer_step <= 0 {
    return Err(MissingOutput)
  }
  issue_client_compute_prefix_fragment_for_owner(
    owner,
    infer_step - 1,
    infer_step - 1,
    "task_" + task.to_string() + "_before_infer_" + infer_step.to_string(),
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Seal an exact checked pure output without interpreting the acquisition that
/// consumes it. Existing Infer fragment identities and bytes stay unchanged.
fn issue_client_compute_prefix_fragment_for_owner(
  owner : @lower.BoundPrepared,
  prefix_end : Int,
  output_step : Int,
  node_id : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  guard output_step >= 0 &&
    output_step <= prefix_end &&
    @lower.node_at(@lower.bound_preparation(owner), output_step) is Some(output) else {
    return Err(MissingOutput)
  }
  let pipeline_wire = match
    emit_client_task_pipeline_prefix(
      owner,
      prefix_end,
      @lower.node_id(output),
      None,
      Some(prefix_end),
      true,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(Pipeline(issue))
  }
  issue_client_task_fragment_body(
    owner,
    @pipeline.Step(output_step),
    None,
    node_id,
    pipeline_wire,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_client_infer_compute_fragment(
  owner : @lower.BoundPrepared,
  task : Int,
  infer_step : Int,
  step : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  serialization_boundary? : Int? = None,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  guard step > infer_step &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(output) else {
    return Err(MissingOutput)
  }
  let pipeline_wire = match
    emit_client_task_pipeline_prefix(
      owner,
      step,
      @lower.node_id(output),
      Some(step),
      None,
      false,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      infer_boundary=Some(infer_step),
      serialization_boundary~,
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(Pipeline(issue))
  }
  issue_client_task_fragment_body(
    owner,
    @pipeline.Step(step),
    Some(step),
    "task_" + task.to_string() + "_after_infer_" + step.to_string(),
    pipeline_wire,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Issue a pure suffix fragment with an explicit input port for its authentic
/// Content producer. The producer's byte generation is not in the AoA body.
fn issue_client_serialized_infer_compute_fragment(
  component : ClientSerializationPlanGraph,
  infer_step : Int,
  step : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  if step >= infer_step {
    return Err(MissingOutput)
  }
  issue_client_serialized_compute_fragment(
    component,
    infer_step - 1,
    step,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// The same pure consumer fragment serves ordinary Relation and Model inputs.
/// Its producer remains the checked Content barrier, never an AoA evaluator.
fn issue_client_serialized_compute_fragment(
  component : ClientSerializationPlanGraph,
  terminal : Int,
  step : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  let owner = @lower.serialization_owner(component.barrier)
  guard component.step < step &&
    step <= terminal &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(output) else {
    return Err(MissingOutput)
  }
  let wire = match
    emit_client_task_pipeline_prefix(
      owner,
      step,
      @lower.node_id(output),
      Some(step),
      None,
      false,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      completed_serialization=Some((component.step, terminal)),
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(Pipeline(issue))
  }
  issue_client_task_fragment_body(
    owner,
    @pipeline.Step(step),
    Some(step),
    "task_" +
    component.task.to_string() +
    "_after_serialize_" +
    step.to_string(),
    wire,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_client_task_fragment_body(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  selected : Int?,
  node_id : String,
  pipeline_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  serialization_input? : @lower.PreparedSerialization? = None,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  guard parse_plan_identity_value(
      pipeline_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(pipeline) else {
    return Err(Encoding)
  }
  let logical_cid = @canonical.cid_value(
    pipeline, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let prepared = @lower.bound_preparation(owner)
  let checked = @lower.pipeline(prepared)
  guard client_task_target_port(prepared, target) is Some(output_port) &&
    @lower.preparation_carrier_at(prepared, target) is Some(output) else {
    return Err(MissingOutput)
  }
  guard @canonical.object_field(pipeline, "output")
    is Some(@canonical.String(actual_output)) &&
    actual_output == output_port else {
    return Err(Encoding)
  }
  let carrier = match serialization_input {
    Some(barrier) => {
      if !physical_equal(@lower.serialization_owner(barrier), owner) ||
        target != @pipeline.Step(@lower.serialization_step(barrier)) ||
        @pipeline.serialization_sort(@lower.serialization_checked(barrier))
        is None {
        return Err(MissingOutput)
      }
      @carrier.relation(
        @carrier.typed_rows(
          @pipeline.serialization_input_schema(
            @lower.serialization_checked(barrier),
          ),
        ),
      )
    }
    None => output
  }
  let (output_carrier, output_contract_cid) = match
    client_task_carrier_contract(carrier, max_wire_bytes, max_nodes, max_depth) {
    Some(contract) => contract
    None => return Err(UnrepresentableContract)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "input_contracts")
    @encode.begin_object(writer)
    let input_count = if selected is Some(step) {
      @lower.node_at(prepared, step).map(@lower.node_input_count).unwrap_or(0)
    } else {
      @pipeline.input_count(checked)
    }
    for index in 0..<input_count {
      let input = if selected is Some(step) {
        @lower.node_at(prepared, step)
        .bind(node => @lower.node_input_target(node, index))
        .bind(target => @lower.preparation_carrier_at(prepared, target))
        .map(carrier => ("input_" + index.to_string(), carrier))
      } else {
        @pipeline.input_at(checked, index)
      }
      guard input is Some((name, carrier)) &&
        client_task_carrier_contract(
          carrier, max_wire_bytes, max_nodes, max_depth,
        )
        is Some((_, input_contract_cid)) else {
        return Err(UnsupportedCarrier)
      }
      @encode.key(writer, name)
      @encode.string_value(writer, input_contract_cid)
    }
    @encode.end_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "aoa_fragment")
    @encode.key(writer, "logical_cid")
    @encode.string_value(writer, logical_cid)
    @encode.key(writer, "node_id")
    @encode.string_value(writer, node_id)
    @encode.key(writer, "output_contracts")
    @encode.begin_object(writer)
    @encode.key(writer, output_port)
    @encode.string_value(writer, output_contract_cid)
    @encode.end_object(writer)
    @encode.key(writer, "pipeline")
    @canonical.emit_value(pipeline, writer)
    @encode.end_object(writer)
    Ok({
      wire: @encode.finish(writer),
      node_id,
      output_port,
      logical_cid,
      output_contract_cid,
      output_carrier,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// A saved task node cannot be substituted for another checked Program.
pub fn admit_prepared_client_task_fragment(
  value : PreparedClientProgram,
  task : Int,
  saved_wire : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentAdmissionIssue] {
  let issued = match
    issue_prepared_client_task_fragment(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(node) => node
    Err(issue) => return Err(Issue(issue))
  }
  if saved_wire != issued.wire {
    return Err(MismatchedNode)
  }
  Ok(issued)
}
