///|
// The authored field list supplies names only. Definition/label scope, typed
// identity bindings, property presence, predicate typing and output contracts
// remain with the common Graph match checker.
fn lower_script_graph_match_rows(
  construction : Construction,
  query : @query.Query,
  call : @query.SgaCall,
  graph : String,
  known : Array[Input],
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> Input raise Abort {
  let mut fields : Array[String]? = None
  for (name, argument) in call.arguments {
    if name == "fields" {
      guard argument is ListValue(selected) && !selected.is_empty() else {
        raise Abort(UnsupportedGraph)
      }
      let names = []
      for field in selected {
        guard field is TextValue(name) else { raise Abort(UnsupportedGraph) }
        names.push(name)
      }
      fields = Some(names)
    }
  }
  guard fields is Some(visible_fields) else { raise Abort(UnsupportedGraph) }
  let origin = match
    @origin.range(@query.query_document(query), call.start, call.end) {
    Ok(origin) => origin
    Err(_) => raise Abort(InvalidContext)
  }
  let construction = { ..construction, generated: origin, }
  // Reuse the shared argument builder. Structured predicates stay expression
  // trees, and STRING values stay values; the Frontend does not parse another
  // expression dialect or infer a producer from string contents.
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
      (call.operation, body),
      ("as", construction.text(output)),
    ]),
  )
  {
    relation: @query.relation(query),
    name: output,
    source: StepReference,
    visible_fields,
    graph_bindings: [],
  }
}
