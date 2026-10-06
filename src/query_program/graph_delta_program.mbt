///|
// Retain the Graph contract and lower only the existing named argument roles.
// Delta JSON, exact row count, identity/base/target and resource validation
// remain with the common checker and application owner.
fn lower_script_graph_delta(
  construction : Construction,
  query : @query.Query,
  call : @query.SgaCall,
  graph : String,
  known : Array[Input],
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> String raise Abort {
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
        script_traversal_argument(construction, argument.1, known, limits),
      )
    }),
  )
  let output = pipe_physical_name(reserved, "aql_sga_")
  reserved.push(output)
  steps.push(
    construction.object([
      ("from", construction.text(graph)),
      ("apply_graph_delta", body),
      ("as", construction.text(output)),
    ]),
  )
  output
}
