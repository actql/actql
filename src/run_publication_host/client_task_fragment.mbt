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
fn issue_client_task_record_contract(
  carrier : @carrier.Carrier,
  row : @contract.Contract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (String, String)? {
  try {
    let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth)
    if !emit_client_task_record_carrier_body(carrier, row, writer) {
      return None
    }
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
// The real hash and construction measurement use the same original roles and
// complete row contract. This codec does not create a resource/permission owner.
fn emit_client_task_record_carrier_body(
  carrier : @carrier.Carrier,
  row : @contract.Contract,
  writer : @encode.Writer,
) -> Bool raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  match carrier {
    @carrier.EventValue(events) => {
      guard client_task_record_role(@carrier.event_identity(events).name)
        is Some(id) &&
        client_task_record_role(@carrier.event_time(events).name) is Some(time) else {
        return false
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
        return false
      }
      @encode.key(writer, "components")
      @encode.string_value(writer, components)
      @encode.key(writer, "ids")
      @encode.begin_array(writer)
      for index in 0..<@carrier.vector_identity_count(vectors) {
        guard @carrier.vector_identity_at(vectors, index) is Some(field) &&
          client_task_record_role(field.name) is Some(name) else {
          return false
        }
        @encode.string_value(writer, name)
      }
      @encode.end_array(writer)
      @encode.key(writer, "records")
      @contract.emit_checked(row, writer)
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-vectors-contract/0.1")
    }
    _ => return false
  }
  @encode.end_object(writer)
  true
}

///|
fn client_task_carrier_contract(
  carrier : @carrier.Carrier,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (String, String)? {
  guard client_task_contract_source(carrier) is Some(source) else {
    return None
  }
  match source {
    ObjectRelation(row) => {
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
    PresenceRelation(schema) =>
      @execution.identify_relation_schema(schema, {
        max_fields: max_nodes,
        max_bytes: max_wire_bytes,
        max_nodes,
        max_depth,
      })
      .map(identity => ("relation", @execution.relation_schema_cid(identity)))
      .to_option()
    GraphCarrier(original) =>
      match
        @graph_contract.admit(original, {
          max_bytes: max_wire_bytes,
          max_nodes,
          max_depth,
        }) {
        Ok(contract) => Some(("graph", @graph_contract.cid(contract)))
        Err(_) => None
      }
    RecordCarrier(original, row) =>
      issue_client_task_record_contract(
        original, row, max_wire_bytes, max_nodes, max_depth,
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
  let construction = match
    construct_prepared_client_task_pipeline(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(original) => original
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
    client_compilation_task_node_id(task),
    construction,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Initial pipeline, projected pipeline upper extent and complete Task Fragment
/// upper extent. This is sizing DATA only; original contract, identity, graph
/// and reference admission still belong to the real issuer.
pub fn measure_prepared_client_task_fragment_construction(
  value : PreparedClientProgram,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentConstruction, ClientTaskFragmentIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let input = match
    prepare_prepared_client_task_pipeline_input(value, task, sequence_limits) {
    Ok(input) => input
    Err(issue) => return Err(Pipeline(issue))
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    client_task_output_target(value.graph, task) is Some(target) else {
    return Err(MissingTask)
  }
  measure_client_task_fragment_construction(
    owner,
    target,
    @strategy.graph_task_selected_step(value.graph, task),
    client_compilation_task_node_id(task),
    input,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
// Private shared measurement of the same fragment emitter. Prefix callers
// supply their original checked owner/target, not a fabricated Prepared/Graph.
fn measure_client_task_fragment_construction(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  selected : Int?,
  node_id : String,
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  serialization_input? : @lower.PreparedSerialization? = None,
) -> Result[ClientTaskFragmentConstruction, ClientTaskFragmentIssue] {
  let (initial, pipeline) = match
    measure_client_task_pipeline_construction(
      input, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(geometry) => geometry
    Err(issue) => return Err(Pipeline(issue))
  }
  guard physical_equal(input.owner, owner) &&
    client_task_target_port(@lower.bound_preparation(owner), target)
    is Some(output_port) else {
    return Err(MissingTask)
  }
  let prepared = @lower.bound_preparation(owner)
  let output_carrier = match serialization_input {
    Some(barrier) => {
      guard physical_equal(@lower.serialization_owner(barrier), owner) &&
        target == @pipeline.Step(@lower.serialization_step(barrier)) &&
        @pipeline.serialization_sort(@lower.serialization_checked(barrier))
        is Some(_) else {
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
    None => {
      guard @lower.preparation_carrier_at(prepared, target) is Some(carrier) else {
        return Err(MissingOutput)
      }
      carrier
    }
  }
  guard measure_client_task_carrier_contract(
      output_carrier, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(output_contract) else {
    return Err(UnrepresentableContract)
  }
  let input_contracts : Array[(Int, Int, Int)] = []
  try {
    let empty = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(empty)
    @encode.end_object(empty)
    let empty_pipeline = @encode.finish_measurement_usage(empty)
    let header_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    match
      emit_client_task_fragment_body(
        owner,
        selected,
        node_id,
        output_port,
        empty_pipeline,
        (),
        (),
        emit_client_task_pipeline_measurement,
        measure_client_fragment_cid,
        (carrier, b, n, d) => {
          measure_client_task_carrier_contract(carrier, b, n, d).map(measurement => {
            input_contracts.push(measurement)
            ()
          })
        },
        max_wire_bytes,
        max_nodes,
        max_depth,
        header_writer,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let header = @encode.finish_measurement_usage(header_writer)
    let room = max_wire_bytes.to_int64() -
      header.0.to_int64() +
      empty_pipeline.0.to_int64()
    let pipeline_upper = (
      Int64::min(room, pipeline.0.to_int64()).to_int(),
      pipeline.1,
      pipeline.2,
    )
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    match
      emit_client_task_fragment_body(
        owner,
        selected,
        node_id,
        output_port,
        pipeline_upper,
        (),
        (),
        emit_client_task_pipeline_measurement,
        measure_client_fragment_cid,
        client_task_input_contract_measurement,
        max_wire_bytes,
        max_nodes,
        max_depth,
        writer,
      ) {
      Ok(_) =>
        Ok({
          pipeline_geometry: None,
          fragment_geometry: None,
          output_contract_geometry: None,
          initial_pipeline: initial,
          pipeline,
          fragment: @encode.finish_measurement_usage(writer),
          input_contracts,
          output_contract,
          output_carrier: client_task_carrier_sort(output_carrier),
          node_id,
          output_port,
        })
      Err(issue) => Err(issue)
    }
  } catch {
    _ => Err(Encoding)
  }
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
  let construction = match
    construct_client_task_pipeline_prefix(
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
    Ok(original) => original
    Err(issue) => return Err(Pipeline(issue))
  }
  issue_client_task_fragment_body(
    owner,
    @pipeline.Step(output_step),
    None,
    node_id,
    construction,
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
  let construction = match
    construct_client_task_pipeline_prefix(
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
    Ok(original) => original
    Err(issue) => return Err(Pipeline(issue))
  }
  issue_client_task_fragment_body(
    owner,
    @pipeline.Step(step),
    Some(step),
    "task_" + task.to_string() + "_after_infer_" + step.to_string(),
    construction,
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
  let construction = match
    construct_client_task_pipeline_prefix(
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
    Ok(original) => original
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
    construction,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn client_task_input_contract_cid(
  carrier : @carrier.Carrier,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  client_task_carrier_contract(carrier, max_wire_bytes, max_nodes, max_depth).map(pair => {
      pair.1
    },
  )
}

///|
// This interpretation sizes only the existing CID representation. It does not
// issue, hash or admit an input contract, nor promise a representable Carrier.
fn client_task_input_contract_measurement(
  _carrier : @carrier.Carrier,
  _max_wire_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
) -> Unit? {
  Some(())
}

///|
fn client_task_fragment_input_count(
  owner : @lower.BoundPrepared,
  selected : Int?,
) -> Int {
  let prepared = @lower.bound_preparation(owner)
  let checked = @lower.pipeline(prepared)
  if selected is Some(step) {
    @lower.node_at(prepared, step).map(@lower.node_input_count).unwrap_or(0)
  } else {
    @pipeline.input_count(checked)
  }
}

///|
fn[P, C] emit_client_task_fragment_body(
  owner : @lower.BoundPrepared,
  selected : Int?,
  node_id : String,
  output_port : String,
  pipeline : P,
  logical_cid : C,
  output_contract_cid : C,
  emit_pipeline : (P, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  input_contract : (@carrier.Carrier, Int, Int, Int) -> C?,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  writer : @encode.Writer,
) -> Result[Unit, ClientTaskFragmentIssue] raise @encode.EncodeFailure {
  let prepared = @lower.bound_preparation(owner)
  let checked = @lower.pipeline(prepared)
  @encode.begin_object(writer)
  @encode.key(writer, "input_contracts")
  @encode.begin_object(writer)
  let input_count = client_task_fragment_input_count(owner, selected)
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
      input_contract(carrier, max_wire_bytes, max_nodes, max_depth)
      is Some(input_contract_cid) else {
      return Err(UnsupportedCarrier)
    }
    @encode.key(writer, name)
    emit_cid(input_contract_cid, writer)
  }
  @encode.end_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "aoa_fragment")
  @encode.key(writer, "logical_cid")
  emit_cid(logical_cid, writer)
  @encode.key(writer, "node_id")
  @encode.string_value(writer, node_id)
  @encode.key(writer, "output_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, output_port)
  emit_cid(output_contract_cid, writer)
  @encode.end_object(writer)
  @encode.key(writer, "pipeline")
  emit_pipeline(pipeline, writer)
  @encode.end_object(writer)
  Ok(())
}

///|
fn issue_client_task_fragment_body(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  selected : Int?,
  node_id : String,
  construction : ClientTaskPipelineConstruction,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  serialization_input? : @lower.PreparedSerialization? = None,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  let pipeline = construction.body
  let logical_cid = @canonical.cid_value(
    pipeline, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let prepared = @lower.bound_preparation(owner)
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
    match
      emit_client_task_fragment_body(
        owner,
        selected,
        node_id,
        output_port,
        pipeline,
        logical_cid,
        output_contract_cid,
        @canonical.emit_value,
        (cid, out) => @encode.string_value(out, cid),
        client_task_input_contract_cid,
        max_wire_bytes,
        max_nodes,
        max_depth,
        writer,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
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
