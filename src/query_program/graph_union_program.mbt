///|
// Preserve every peer occurrence in the adopted union fold. A reference is a
// previously bound Graph producer; strings never become producer names.
fn script_graph_union_peer(
  construction : Construction,
  argument : @query.SgaArgument,
  graphs : Array[ScriptGraph],
) -> @builder.Node raise Abort {
  guard argument is Producer(name) else { raise Abort(UnsupportedGraph) }
  guard script_graph_named_input(name, graphs) is Some(graph) else {
    raise Abort(UnknownRelation)
  }
  construction.text(graph.producer)
}

///|
// Compatibility, identity, property strategies, fold arithmetic and capacity
// belong to the existing common union owner. Only names and syntax are lowered.
fn lower_script_graph_union(
  construction : Construction,
  query : @query.Query,
  call : @query.SgaCall,
  left : String,
  graphs : Array[ScriptGraph],
  known : Array[Input],
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> String raise Abort {
  guard call.operation == "union_graphs" &&
    call.arguments.filter(argument => argument.0 == "with").length() == 1 &&
    call.arguments.all(argument => argument.0 == "with" || argument.0 == "merge") else {
    raise Abort(UnsupportedGraph)
  }
  let origin = match
    @origin.range(@query.query_document(query), call.start, call.end) {
    Ok(origin) => origin
    Err(_) => raise Abort(InvalidContext)
  }
  let construction = { ..construction, generated: origin, }
  let body = construction.object(
    call.arguments.map(argument => {
      let value = if argument.0 == "with" {
        match argument.1 {
          ListValue(items) => {
            guard !items.is_empty() else { raise Abort(UnsupportedGraph) }
            construction.array(
              items.map(item => {
                script_graph_union_peer(construction, item, graphs)
              }),
            )
          }
          peer => script_graph_union_peer(construction, peer, graphs)
        }
      } else {
        script_traversal_argument(construction, argument.1, known, limits)
      }
      (argument.0, value)
    }),
  )
  let output = pipe_physical_name(reserved, "aql_sga_")
  reserved.push(output)
  steps.push(
    construction.object([
      ("from", construction.text(left)),
      ("union_graphs", body),
      ("as", construction.text(output)),
    ]),
  )
  output
}
