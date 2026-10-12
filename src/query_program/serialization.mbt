///|
/// Static profile data, never a row expression evaluated by the Frontend.
/// Bounds reuse the existing count/Parameter slots; the common checker owns
/// scalar domains, Required presence, profile defaults and order evidence.
fn lower_serialization_option(
  construction : Construction,
  name : String,
  expression : @query.Expression,
  max_work : Int,
) -> @builder.Node raise Abort {
  let mut index = @query.expression_root(expression)
  for _ in 0..<max_work {
    match @query.expression_node(expression, index).unwrap().kind {
      Parenthesized(child) => index = child
      StringLiteral(text) if name != "max_rows" && name != "max_bytes" =>
        return construction.text(text)
      Boolean(value) if name != "max_rows" && name != "max_bytes" =>
        return construction.add(Bool(value))
      Number(text) if name == "max_rows" || name == "max_bytes" => {
        if text.length() > max_work {
          raise Abort(
            Expression({ issue: @expression.WorkLimit, origin: None, }),
          )
        }
        let number = match @expression.numeric_literal(text) {
          Ok(value) => value
          Err(issue) =>
            raise Abort(
              Expression({
                issue,
                origin: @query.expression_origin(expression, index),
              }),
            )
        }
        return construction.add(Number(number))
      }
      ParameterReference(parameter) if name == "max_rows" || name == "max_bytes" =>
        return construction.object([
          ("$param", construction.parameter_text(parameter)),
        ])
      _ => raise Abort(UnsupportedProjection)
    }
  } nobreak {
    raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
  }
}

///|
/// Resolve against the same active Pipe scope as other consumers. Project
/// public names once before the byte barrier, retaining private sort operands
/// only as ordinary fields excluded from the emitted profile field sequence.
fn lower_serialization_steps(
  construction : Construction,
  clause : @query.SerializeClause,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  physical : Array[String],
  initial : Array[(String, @builder.Node)],
  index : Int,
  input_name : String,
  max_work : Int,
) -> (Array[Array[(String, @builder.Node)]], Array[String]) raise Abort {
  let steps : Array[Array[(String, @builder.Node)]] = []
  let prefix = initial.copy()
  let fields = visible.map(pair => pair.0)
  let reserved = physical + fields
  let selected = visible.map(pair => {
    if pair.0 == pair.1 {
      construction.text(pair.0)
    } else {
      construction.object([(pair.0, construction.text(pair.1))])
    }
  })
  let derives : Array[(String, @builder.Node)] = []
  let sort : Array[@builder.Node] = []
  for term in clause.order_by {
    let direct = match
      @query.expression_node(
        term.expression,
        @query.expression_root(term.expression),
      ).unwrap().kind {
      Reference(path) => pipe_slot(path, visible, ranges)
      _ => None
    }
    let mut logical : String? = None
    if direct is Some(slot) {
      for pair in visible {
        if pair.1 == slot {
          logical = Some(pair.0)
          break
        }
      }
    }
    let field = match logical {
      Some(name) => name
      None => {
        let name = pipe_physical_name(reserved, "aql_serialize_order_")
        reserved.push(name)
        match direct {
          Some(slot) =>
            selected.push(
              construction.object([(name, construction.text(slot))]),
            )
          None => {
            derives.push(
              (
                name,
                append_pipe_expression(
                  construction,
                  term.expression,
                  visible,
                  ranges,
                  max_work,
                ),
              ),
            )
            selected.push(construction.text(name))
          }
        }
        name
      }
    }
    sort.push(
      construction.object([
        ("field", construction.text(field)),
        ("dir", construction.text(term.direction)),
        ("nulls", construction.text(term.nulls)),
      ]),
    )
  }
  if !derives.is_empty() {
    prefix.push(("derive", construction.object(derives)))
    steps.push(prefix.copy())
    prefix.clear()
  }
  let mut input = "aql_serialize_input_" + index.to_string()
  while input == input_name {
    input += "_"
  }
  prefix.push(("select", construction.array(selected)))
  prefix.push(("as", construction.text(input)))
  steps.push(prefix)
  let options = [
    ("format", construction.text(clause.format)),
    (
      "fields",
      construction.array(fields.map(field => construction.text(field))),
    ),
  ]
  if clause.preserve_order {
    options.push(("preserve_order", construction.add(Bool(true))))
  } else {
    options.push(("order_by", construction.array(sort)))
  }
  let bounds = []
  for (name, expression) in clause.options {
    let value = lower_serialization_option(
      construction,
      name.value,
      expression,
      max_work,
    )
    if name.value == "max_rows" || name.value == "max_bytes" {
      bounds.push((name.value, value))
    } else {
      options.push((name.value, value))
    }
  }
  if !bounds.is_empty() {
    options.push(("bounds", construction.object(bounds)))
  }
  steps.push([
    ("from", construction.text(input)),
    ("serialize", construction.object(options)),
  ])
  (steps, ["name", "content", "media_type", "size_bytes", "row_count"])
}
