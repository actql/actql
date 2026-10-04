///|
// Lower only syntax roles. Membership, predicates, path mode, hop bounds,
// typed identities, output schema and resource evidence belong to the common
// traversal checker and owner. A DATA selector reuses its emitted producer.
fn script_traversal_argument(
  construction : Construction,
  argument : @query.SgaArgument,
  known : Array[Input],
  limits : Limits,
) -> @builder.Node raise Abort {
  match argument {
    Producer(name) => {
      let input = resolve_relation_input([name], known)
      // This first connection consumes earlier DATA producers. Installed
      // selector Sources need the existing capture/share boundary, not an
      // undeclared producer or a new acquisition path in this lowerer.
      guard input.source is StepReference else { raise Abort(UnsupportedGraph) }
      construction.text(input.name)
    }
    TextValue(value) => construction.text(value)
    NumberValue(text) =>
      match @expression.numeric_literal(text) {
        Ok(value) => construction.add(Number(value))
        Err(issue) =>
          raise Abort(
            Expression({ issue, origin: Some(construction.generated), }),
          )
      }
    BooleanValue(value) => construction.add(Bool(value))
    NullValue => construction.add(Null)
    ParameterValue(name) =>
      construction.object([("$param", construction.text(name))])
    ObjectValue(fields) =>
      construction.object(
        fields.map(field => {
          (
            field.0,
            script_traversal_argument(construction, field.1, known, limits),
          )
        }),
      )
    ListValue(items) =>
      construction.array(
        items.map(item => {
          script_traversal_argument(construction, item, known, limits)
        }),
      )
  }
}

///|
fn lower_script_traversal_nodes(
  construction : Construction,
  query : @query.Query,
  call : @query.SgaCall,
  graph : String,
  known : Array[Input],
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> Input raise Abort {
  // Node and path emissions have different contracts. Do not borrow one
  // output schema for the other or replace an authored emission/default.
  guard call.arguments.any(argument => {
    argument.0 == "emit" && argument.1 == @query.TextValue("nodes")
  }) else {
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
      ("traverse", body),
      ("as", construction.text(output)),
    ]),
  )
  {
    relation: @query.relation(query),
    name: output,
    source: StepReference,
    visible_fields: ["start_id", "node_id", "depth"],
    graph_bindings: [],
  }
}
