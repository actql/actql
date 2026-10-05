///|
fn script_graph_diagnostic_fields(operation : String) -> Array[String]? {
  match operation {
    "degree" => Some(["node", "degree"])
    "graph_bounds" => Some(["kind", "node_id", "actual", "max"])
    "components" => Some(["node_id", "component_id", "component_size"])
    _ => None
  }
}

///|
// Preserve authored diagnostic bodies, including zero thresholds and typed
// parameters. The existing checker owns direction, kind, range and closed-body
// validation; the Graph owner owns identities, output order and resource scopes.
fn lower_script_graph_diagnostic(
  construction : Construction,
  query : @query.Query,
  call : @query.SgaCall,
  graph : String,
  fields : Array[String],
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> Input raise Abort {
  let origin = match
    @origin.range(@query.query_document(query), call.start, call.end) {
    Ok(origin) => origin
    Err(_) => raise Abort(InvalidContext)
  }
  let construction = { ..construction, generated: origin, }
  let body = construction.object(
    call.arguments.map(argument => {
      (
        argument.0,
        script_traversal_argument(construction, argument.1, [], limits),
      )
    }),
  )
  let output = pipe_physical_name(reserved, "aql_sga_")
  reserved.push(output)
  steps.push(
    construction.object([
      ("from", construction.text(graph)),
      (call.operation, body),
      ("as", construction.text(output)),
    ]),
  )
  {
    relation: @query.relation(query),
    name: output,
    source: StepReference,
    visible_fields: fields,
    graph_bindings: [],
  }
}
