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
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let aoa = match
    issue_prepared_client_values_aoa_identity(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(AoA(issue))
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    @lower.node_at(
      @lower.bound_preparation(owner),
      @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) - 1,
    )
    is Some(node) else {
    return Err(MissingCheckedOutput)
  }
  let node_id = @lower.node_id(node)
  guard parse_plan_identity_value(
      client_values_aoa_identity_wire(aoa),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(pipeline) &&
    @canonical.object_field(pipeline, "output")
    is Some(@canonical.String(output)) &&
    output == node_id else {
    return Err(OutputMismatch)
  }
  guard @schema.as_object(@lower.node_output_schema(node)) is Some(row) else {
    return Err(UnrepresentableOutput)
  }
  try {
    let output_hash = @encode.hashing_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    let output_text = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @contract.emit_checked(row, output_hash)
    @contract.emit_checked(row, output_text)
    let output_contract_cid = "sha256:" + @encode.finish_hash(output_hash)
    let output_contract_wire = @encode.finish(output_text)
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "input_contracts")
    @encode.begin_object(writer)
    @encode.end_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "aoa_fragment")
    @encode.key(writer, "logical_cid")
    @encode.string_value(writer, client_values_aoa_identity_cid(aoa))
    @encode.key(writer, "node_id")
    @encode.string_value(writer, node_id)
    @encode.key(writer, "output_contracts")
    @encode.begin_object(writer)
    @encode.key(writer, node_id)
    @encode.string_value(writer, output_contract_cid)
    @encode.end_object(writer)
    @encode.key(writer, "pipeline")
    @canonical.emit_value(pipeline, writer)
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    Ok({
      wire,
      node_id,
      logical_cid: client_values_aoa_identity_cid(aoa),
      output_contract_wire,
      output_contract_cid,
    })
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
