///|
// A Subgraph retains the admitted Graph contract. Only argument syntax and
// DATA producer references are lowered here; selection, membership, induction,
// edge predicates, identity and capacity remain with the common owner.
fn lower_script_subgraph(
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
      ("subgraph", body),
      ("as", construction.text(output)),
    ]),
  )
  output
}
