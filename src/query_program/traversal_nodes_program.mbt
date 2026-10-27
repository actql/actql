///|
// Lower only syntax roles. Membership, predicates, path mode, hop bounds,
// typed identities, output schema and resource evidence belong to the common
// traversal checker and owner. A WITH selector reuses its emitted producer.
fn script_traversal_argument(
  construction : Construction,
  argument : @query.SgaArgument,
  known : Array[Input],
  limits : Limits,
) -> @builder.Node raise Abort {
  match argument {
    Producer(name) => {
      let input = resolve_relation_input([name], known)
      // This first connection consumes earlier WITH producers. Installed
      // selector Sources need the existing capture/share boundary, not an
      // undeclared producer or a new acquisition path in this lowerer.
      guard input.source is StepReference else { raise Abort(UnsupportedGraph) }
      construction.text(input.name)
    }
    FieldReference(path) => {
      guard path.length() == 1 else { raise Abort(InvalidQuery) }
      construction.text(path[0].value)
    }
    FieldMapValue(_) | ExpressionValue(_) => raise Abort(InvalidQuery)
    OutputName(name) => construction.text(name.value)
    TextValue(value) => construction.text(value)
    NumberValue(text) =>
      // Unary plus has no value effect. The existing numeric-literal owner
      // preserves precision and finite/hex admission, normalizing signed source
      // zero. Canonical JSON Number and Parameter values still reject negative zero.
      match
        @expression.numeric_literal(
          if text.has_prefix("+") {
            text[1:].to_owned()
          } else {
            text
          },
        ) {
        Ok(value) => construction.add(Number(value))
        Err(issue) =>
          raise Abort(
            Expression({ issue, origin: Some(construction.generated), }),
          )
      }
    BooleanValue(value) => construction.add(Bool(value))
    NullValue => construction.add(Null)
    ParameterValue(name) =>
      construction.object([("$param", construction.parameter_text(name))])
    ObjectValue(fields) => {
      if fields.length() == 1 &&
        fields[0].0 == "field" &&
        fields[0].1 is FieldReference(path) {
        return script_sga_expression_field(construction, path)
      }
      // A Relation selector's field belongs to its declared operand, not the
      // current Graph or the global producer scope. The common selector still
      // checks identity/type/presence after ordinary source name resolution.
      let operand = fields.filter(field => field.0 == "from")
      let selector_input = if operand.length() == 1 &&
        operand[0].1 is Producer(name) {
        Some((name, resolve_relation_input([name], known)))
      } else {
        None
      }
      construction.object(
        fields.map(field => {
          let value = if field.0 == "id" &&
            field.1 is FieldReference(path) &&
            selector_input is Some((name, input)) {
            script_sga_selector_field(construction, path, name, input)
          } else {
            script_traversal_argument(construction, field.1, known, limits)
          }
          (field.0, value)
        }),
      )
    }
    ListValue(items) =>
      construction.array(
        items.map(item => {
          script_traversal_argument(construction, item, known, limits)
        }),
      )
  }
}

///|
fn lower_script_traversal_rows(
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
  let emissions = call.arguments.filter(argument => argument.0 == "emit")
  let fields = if call.operation == "reach" {
    ["start_id", "node_id", "depth"]
  } else if call.operation == "shortest_path" {
    [
      "source_id", "target_id", "total_cost", "hop_count", "node_ids", "edge_ids",
    ]
  } else {
    guard emissions.length() == 1 else { raise Abort(UnsupportedGraph) }
    match emissions[0].1 {
      @query.TextValue("nodes") => ["start_id", "node_id", "depth"]
      @query.TextValue("paths") =>
        ["start_id", "end_id", "hop_count", "node_ids", "edge_ids"]
      _ => raise Abort(UnsupportedGraph)
    }
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

///|
// Preserve a genuine property path as ordinary common expression nodes. A
// quoted dotted identifier remains one field; no sampled value or new evaluator.
fn script_sga_expression_field(
  construction : Construction,
  path : Array[@query.NamePart],
) -> @builder.Node raise Abort {
  guard !path.is_empty() else { raise Abort(InvalidQuery) }
  let mut value = construction.object([
    ("field", construction.text(path[0].value)),
  ])
  for index = 1; index < path.length(); index = index + 1 {
    value = construction.object([
      (
        "property",
        construction.object([
          ("value", value),
          ("name", construction.text(path[index].value)),
        ]),
      ),
    ])
  }
  value
}

///|
fn script_sga_selector_field(
  construction : Construction,
  path : Array[@query.NamePart],
  operand : @query.NamePart,
  input : Input,
) -> @builder.Node raise Abort {
  guard path.length() == 1 ||
    (path.length() == 2 && same_name(path[0], operand)) else {
    raise Abort(UnknownColumn)
  }
  let selected = columns(input).filter(field => {
    same_name(path.last().unwrap(), { value: field, quoted: false, })
  })
  guard selected.length() == 1 else { raise Abort(UnknownColumn) }
  construction.text(selected[0])
}
