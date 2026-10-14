///|
// A temporal selector has a declared operand. Fixed left/right qualifiers and
// lexical producer qualifiers cannot silently select the other input's field.
fn script_temporal_field_name(
  construction : Construction,
  path : Array[@query.NamePart],
  left : Bool,
  query : @query.Query,
  input : Input,
  right_name : @query.NamePart,
  right : Input,
  sources : ScriptSources,
) -> String raise Abort {
  guard path.length() == 1 || path.length() == 2 else {
    raise Abort(UnknownColumn)
  }
  if path.length() == 2 {
    let qualifier = if left { query_range_name(query) } else { right_name }
    let fixed = !path[0].quoted &&
      same_name(path[0], {
        value: if left {
          "left"
        } else {
          "right"
        },
        quoted: false,
      })
    guard fixed || same_name(path[0], qualifier) else {
      raise Abort(UnknownColumn)
    }
  }
  if left {
    return script_carrier_field_name(
      construction,
      [path.last().unwrap()],
      query,
      input,
      sources,
    )
  }
  let field = path.last().unwrap()
  let names = columns(right).filter(name => {
    same_name(field, { value: name, quoted: false, })
  })
  guard names.length() == 1 else { raise Abort(UnknownColumn) }
  names[0]
}

///|
fn script_temporal_field(
  construction : Construction,
  argument : @query.SgaArgument,
  left : Bool,
  query : @query.Query,
  input : Input,
  right_name : @query.NamePart,
  right : Input,
  sources : ScriptSources,
) -> @builder.Node raise Abort {
  match argument {
    ListValue(items) =>
      construction.array(
        items.map(item => {
          script_temporal_field(
            construction, item, left, query, input, right_name, right, sources,
          )
        }),
      )
    FieldReference(path) =>
      construction.text(
        script_temporal_field_name(
          construction, path, left, query, input, right_name, right, sources,
        ),
      )
    _ => raise Abort(InvalidQuery)
  }
}

///|
// Bind a once-resolved lexical peer through the existing capture/share owner.
// Only role names are rewritten; domains, temporal laws, guards, ordering and
// pending validations remain with the common AsOf/Interval checker.
fn script_temporal_join_body(
  construction : Construction,
  call : @query.SgaCall,
  query : @query.Query,
  input : Input,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> @builder.Node raise Abort {
  let peers = call.arguments.filter(field => field.0 == "with")
  guard peers.length() == 1 && peers[0].1 is Producer(name) else {
    raise Abort(InvalidQuery)
  }
  let selected = resolve_relation_input([name], known)
  let right = bind_script_input(
    construction, selected, context, sources, steps, reserved,
  )
  construction.object(
    call.arguments.map(field => {
      let value = if field.0 == "with" {
        construction.text(right.name)
      } else if ["left_id", "left_time", "right_time", "right_tie_break"].contains(
          field.0,
        ) {
        script_temporal_field(
          construction,
          field.1,
          field.0.has_prefix("left"),
          query,
          input,
          name,
          right,
          sources,
        )
      } else if ["by", "on"].contains(field.0) {
        guard field.1 is ListValue(pairs) else { raise Abort(InvalidQuery) }
        construction.array(
          pairs.map(pair => {
            guard pair is ObjectValue(fields) else { raise Abort(InvalidQuery) }
            construction.object(
              fields.map(item => {
                guard item.0 == "left" || item.0 == "right" else {
                  raise Abort(InvalidQuery)
                }
                (
                  item.0,
                  script_temporal_field(
                    construction,
                    item.1,
                    item.0 == "left",
                    query,
                    input,
                    name,
                    right,
                    sources,
                  ),
                )
              }),
            )
          }),
        )
      } else if field.0 == "left" || field.0 == "right" {
        guard field.1 is ObjectValue(fields) else { raise Abort(InvalidQuery) }
        construction.object(
          fields.map(item => {
            (
              item.0,
              script_temporal_field(
                construction,
                item.1,
                field.0 == "left",
                query,
                input,
                name,
                right,
                sources,
              ),
            )
          }),
        )
      } else if field.0 == "select" {
        guard field.1 is ObjectValue(fields) else { raise Abort(InvalidQuery) }
        construction.object(
          fields.map(item => {
            guard item.1 is FieldReference(path) && path.length() == 2 else {
              raise Abort(InvalidQuery)
            }
            let left = !path[0].quoted &&
              same_name(path[0], { value: "left", quoted: false, })
            let is_right = !path[0].quoted &&
              same_name(path[0], { value: "right", quoted: false, })
            guard left || is_right else { raise Abort(InvalidQuery) }
            let selected = script_temporal_field_name(
              construction, path, left, query, input, name, right, sources,
            )
            (
              item.0,
              construction.text(
                (if left { "left." } else { "right." }) + selected,
              ),
            )
          }),
        )
      } else {
        script_traversal_argument(construction, field.1, known, limits)
      }
      (field.0, value)
    }),
  )
}
