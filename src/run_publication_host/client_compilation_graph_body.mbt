///|
// One field definition for real graph construction and its geometric
// interpretation. Domain errors remain at the original edge/root operation,
// after the same preceding writer checks. These are private pure codecs,
// never caller hooks, execution delegates or resource/permission owners.
fn[E] emit_client_compilation_graph(
  writer : @encode.Writer,
  edges : (@encode.Writer) -> Result[Unit, E] raise @encode.EncodeFailure,
  nodes : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
  roots : (@encode.Writer) -> Result[Unit, E] raise @encode.EncodeFailure,
) -> Result[Unit, E] raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "data_edges")
  @encode.begin_array(writer)
  match edges(writer) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  @encode.end_array(writer)
  @encode.key(writer, "nodes")
  @encode.begin_array(writer)
  nodes(writer)
  @encode.end_array(writer)
  @encode.key(writer, "root_refs")
  @encode.begin_array(writer)
  match roots(writer) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  Ok(())
}

///|
fn[C] emit_client_compilation_data_edge(
  writer : @encode.Writer,
  carrier : String,
  contract : C,
  from_node : String,
  from_port : String,
  to_node : String,
  to_port : String,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "carrier")
  @encode.string_value(writer, carrier)
  @encode.key(writer, "contract_cid")
  emit_cid(contract, writer)
  @encode.key(writer, "from")
  emit_result_plan_ref(writer, from_node, from_port)
  @encode.key(writer, "to")
  emit_result_plan_ref(writer, to_node, to_port)
  @encode.end_object(writer)
}

///|
// Original pure compiler coordinate labels. Both the real constructor and
// its pre-entry storage observation use these exact immutable DATA values.
fn client_compilation_task_node_id(task : Int) -> String {
  "task_" + task.to_string()
}

///|
fn client_compilation_result_node_id(result : Int) -> String {
  "result_" + result.to_string()
}

///|
fn client_compilation_result_input_node_id(edge : Int) -> String {
  "result_input_" + edge.to_string()
}
