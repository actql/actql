///|
// Resolve the existing producer argument, not a string-valued Graph name.
// Admission, identity/domain compatibility and bounded comparison remain
// obligations of the common Graph equality checker and execution owner.
fn lower_script_graph_equality(
  construction : Construction,
  query : @query.Query,
  call : @query.SgaCall,
  left : String,
  graphs : Array[ScriptGraph],
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> Input raise Abort {
  guard call.arguments is [("with", Producer(name))] else {
    raise Abort(UnsupportedGraph)
  }
  guard script_graph_named_input(name, graphs) is Some(right) else {
    raise Abort(UnknownRelation)
  }
  let origin = match
    @origin.range(@query.query_document(query), call.start, call.end) {
    Ok(origin) => origin
    Err(_) => raise Abort(InvalidContext)
  }
  let construction = { ..construction, generated: origin, }
  let output = pipe_physical_name(reserved, "aql_sga_")
  reserved.push(output)
  steps.push(
    construction.object([
      ("from", construction.text(left)),
      (
        "graphs_equal",
        construction.object([("with", construction.text(right.producer))]),
      ),
      ("as", construction.text(output)),
    ]),
  )
  {
    relation: @query.relation(query),
    name: output,
    source: StepReference,
    visible_fields: ["equal"],
    graph_bindings: [],
  }
}
