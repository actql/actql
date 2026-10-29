///|
fn client_values_fragment_output_contract(
  row : @contract.Contract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  emit? : (@contract.Contract, @encode.Writer) -> Unit raise @encode.EncodeFailure = @contract.emit_checked,
) -> (String, String) raise @encode.EncodeFailure {
  let writer = @encode.buffered_hashing_writer(
    max_wire_bytes, max_nodes, max_depth, max_wire_bytes,
  )
  emit(row, writer)
  // Text remains provisional until the same writer confirms completion.
  let wire = @encode.drain_hash_output(writer)
  let cid = "sha256:" + @encode.finish_hash(writer)
  (wire, cid)
}

///|
/// One owner-issued AoA Fragment node for a checked source-free Values task.
/// Its output contract is the complete task row type before Result projection.
pub struct ClientValuesFragmentNode {
  wire : String
  node_id : String
  logical_cid : String
  output_contract_wire : String
  output_contract_cid : String
}

///|
pub(all) enum ClientValuesFragmentIssue {
  InvalidLimits
  AoA(ClientValuesAoAIdentityIssue)
  MissingCheckedOutput
  OutputMismatch
  UnrepresentableOutput
  Encoding
}

///|
pub(all) enum ClientValuesFragmentAdmissionIssue {
  Issue(ClientValuesFragmentIssue)
  MismatchedNode
}

///|
pub fn client_values_fragment_wire(value : ClientValuesFragmentNode) -> String {
  value.wire
}

///|
pub fn client_values_fragment_node_id(
  value : ClientValuesFragmentNode,
) -> String {
  value.node_id
}

///|
pub fn client_values_fragment_logical_cid(
  value : ClientValuesFragmentNode,
) -> String {
  value.logical_cid
}

///|
pub fn client_values_fragment_output_contract_wire(
  value : ClientValuesFragmentNode,
) -> String {
  value.output_contract_wire
}

///|
pub fn client_values_fragment_output_contract_cid(
  value : ClientValuesFragmentNode,
) -> String {
  value.output_contract_cid
}

///|
/// Bind the exact AoA pipeline, checked node ID and full output row type in
/// the registered aoa_fragment node shape. Result roots, facts and policy
/// remain separate requirements before an Executable Plan can be issued.
pub fn issue_prepared_client_values_fragment(
  value : PreparedClientProgram,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesFragmentNode, ClientValuesFragmentIssue] {
  issue_client_values_fragment_graph(
    value.graph,
    task,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    preparation=Some(value),
  )
}

///|
/// Keep the checked Effect closure while sharing the compiler's Fragment
/// issuer. This computation evidence is neither an apply permit nor a Plan.
pub fn issue_prepared_client_effect_values_fragment(
  value : PreparedClientEffectComputation,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesFragmentNode, ClientValuesFragmentIssue] {
  issue_client_values_fragment_graph(
    @strategy.checked_effect_computation_graph(value.graph),
    task,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_client_values_fragment_graph(
  graph : @strategy.CheckedDAG,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  preparation? : PreparedClientProgram? = None,
) -> Result[ClientValuesFragmentNode, ClientValuesFragmentIssue] {
  issue_client_values_fragment_parts_graph(
    graph,
    task,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    preparation~,
  ).map(parts => parts.0)
}

///|
// Compiler-local immutable parts; serialized bytes never replace this original.
fn issue_client_values_fragment_parts_graph(
  graph : @strategy.CheckedDAG,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  preparation? : PreparedClientProgram? = None,
) -> Result[
  (ClientValuesFragmentNode, ClientValuesAoAParts),
  ClientValuesFragmentIssue,
] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let aoa = match
    issue_client_values_aoa_parts_graph(
      graph,
      task,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      preparation~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(AoA(issue))
  }
  guard @strategy.graph_task_owner(graph, task) is Some(owner) &&
    @lower.node_at(
      @lower.bound_preparation(owner),
      @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) - 1,
    )
    is Some(node) else {
    return Err(MissingCheckedOutput)
  }
  let node_id = @lower.node_id(node)
  let pipeline = aoa.body
  guard @canonical.object_field(pipeline, "output")
    is Some(@canonical.String(output)) &&
    output == node_id else {
    return Err(OutputMismatch)
  }
  guard @schema.as_object(@lower.node_output_schema(node)) is Some(row) else {
    return Err(UnrepresentableOutput)
  }
  try {
    let (output_contract_wire, output_contract_cid) = client_values_fragment_output_contract(
      row, max_wire_bytes, max_nodes, max_depth,
    )
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_values_fragment_body(
      writer,
      node_id,
      pipeline,
      client_values_aoa_identity_cid(aoa.identity),
      output_contract_cid,
      @canonical.emit_value,
      (value, out) => @encode.string_value(out, value),
    )
    let wire = @encode.finish(writer)
    Ok(
      (
        {
          wire,
          node_id,
          logical_cid: client_values_aoa_identity_cid(aoa.identity),
          output_contract_wire,
          output_contract_cid,
        },
        aoa,
      ),
    )
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Replan one saved Fragment from the checked Program before use.
/// A canonical node from a different checked Values task is not admitted.
/// This is only one component of saved Executable Plan admission.
pub fn admit_prepared_client_values_fragment(
  value : PreparedClientProgram,
  task : Int,
  saved_wire : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesFragmentNode, ClientValuesFragmentAdmissionIssue] {
  let issued = match
    issue_prepared_client_values_fragment(
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

///|
pub fn admit_prepared_client_effect_values_fragment(
  value : PreparedClientEffectComputation,
  task : Int,
  saved_wire : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesFragmentNode, ClientValuesFragmentAdmissionIssue] {
  let issued = match
    issue_prepared_client_effect_values_fragment(
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

///|
// One Fragment definition for actual canonical output and text-free size
// composition. Measurement substitutes no Program, CID, Plan or authority.
fn[P, C] emit_client_values_fragment_body(
  writer : @encode.Writer,
  node_id : String,
  pipeline : P,
  logical_cid : C,
  output_contract_cid : C,
  emit_pipeline : (P, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "input_contracts")
  @encode.begin_object(writer)
  @encode.end_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "aoa_fragment")
  @encode.key(writer, "logical_cid")
  emit_cid(logical_cid, writer)
  @encode.key(writer, "node_id")
  @encode.string_value(writer, node_id)
  @encode.key(writer, "output_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, node_id)
  emit_cid(output_contract_cid, writer)
  @encode.end_object(writer)
  @encode.key(writer, "pipeline")
  emit_pipeline(pipeline, writer)
  @encode.end_object(writer)
}

///|
// Every selected identity field is a lowercase SHA-256 CID: seven ASCII
// prefix bytes, 64 hex digits and two quotes. Only a measuring sink accepts
// this extent; it never creates a representative or caller-provided identity.
fn measure_client_fragment_cid(
  _ : Unit,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.emit_measurement(writer, ("sha256:".length() + 64 + 2, 1, 0))
}

///|
/// Measure this SAME checked Values Fragment without constructing its
/// pipeline wire/tree, output-contract hash or any claimed identity. Schema
/// construction and the rest of the compiler overlap remain separate inputs
/// to the Request owner's complete preallocation quote.
pub fn measure_prepared_client_values_fragment(
  value : PreparedClientProgram,
  task : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ClientValuesFragmentIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let pipeline = match
    measure_prepared_client_values_pipeline(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(AoA(Pipeline(issue)))
    Ok(measurement) => measurement
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    @lower.node_at(
      @lower.bound_preparation(owner),
      @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) - 1,
    )
    is Some(node) else {
    return Err(MissingCheckedOutput)
  }
  guard @schema.as_object(@lower.node_output_schema(node)) is Some(_) else {
    return Err(UnrepresentableOutput)
  }
  try {
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_values_fragment_body(
      writer,
      @lower.node_id(node),
      pipeline,
      (),
      (),
      (measurement, out) => @encode.emit_measurement(out, measurement),
      measure_client_fragment_cid,
    )
    Ok(@encode.finish_measurement_usage(writer))
  } catch {
    _ => Err(Encoding)
  }
}
