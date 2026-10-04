///|
fn set_alignment_fields(
  left_fields : Array[String],
  right_fields : Array[String],
  by_name : Bool,
) -> (Array[String], Bool) raise Abort {
  if right_fields.length() != left_fields.length() {
    raise Abort(UnsupportedSet)
  }
  let mut alignment_needed = false
  let matched : Array[String] = []
  for field in left_fields {
    let index = matched.length()
    let source = if by_name {
      let mut selected : String? = None
      for candidate in right_fields {
        if same_name({ value: field, quoted: false, }, {
            value: candidate,
            quoted: false,
          }) {
          if selected is Some(_) {
            raise Abort(UnsupportedSet)
          }
          selected = Some(candidate)
        }
      }
      match selected {
        Some(name) => name
        None => raise Abort(UnsupportedSet)
      }
    } else {
      right_fields[index]
    }
    matched.push(source)
    if source != field || right_fields[index] != field {
      alignment_needed = true
    }
  }
  if matched.length() != right_fields.length() {
    raise Abort(UnsupportedSet)
  }
  (matched, alignment_needed)
}

///|
fn set_operation_body(
  construction : Construction,
  part : @query.SetPart,
  right : String,
) -> (String, @builder.Node) raise Abort {
  let operation = match part.kind {
    "union" => "append"
    "intersect" => "intersect"
    "except" => "except"
    _ => raise Abort(UnsupportedSet)
  }
  let body = if part.kind == "union" {
    construction.object([("with", construction.text(right))])
  } else {
    construction.object([
      ("with", construction.text(right)),
      ("duplicates", construction.text(part.duplicates)),
    ])
  }
  (operation, body)
}

///|
// Root sets, CTE bodies and logical DATA sets use the same output scope,
// evaluated-slot reuse, hidden sort projection and bounded expression owner.
fn append_set_final_steps(
  construction : Construction,
  query : @query.Query,
  limits : Limits,
  input : String,
  left_fields : Array[String],
  steps : Array[@builder.Node],
  prefix : String,
) -> String raise Abort {
  let mut current = input
  for index in 0..<@query.final_operation_count(query) {
    let operation = @query.final_operation_at(query, index).unwrap()
    let final_name = prefix + "aql_set_final_" + index.to_string()
    match operation {
      Order(terms) => {
        let sort : Array[@builder.Node] = []
        let hidden : Array[(@query.Expression, String)] = []
        let derives : Array[(String, @builder.Node)] = []
        let reserved = left_fields.copy()
        let visible = left_fields.map(field => (field, field))
        for term in terms {
          let mut root = @query.expression_node(
            term.expression,
            @query.expression_root(term.expression),
          ).unwrap()
          while root.kind is Parenthesized(child) {
            root = @query.expression_node(term.expression, child).unwrap()
          }
          let ordinal = order_ordinal_column(term.expression, left_fields)
          let direct = if ordinal is Some(_) {
            ordinal
          } else {
            match root.kind {
              Reference(path) => pipe_slot(path, visible, [])
              _ => None
            }
          }
          let field = match direct {
            Some(field) => field
            None => {
              let mut reused : String? = None
              for pair in hidden {
                if same_expression(term.expression, pair.0) {
                  reused = Some(pair.1)
                }
              }
              match reused {
                Some(field) => field
                None => {
                  let field = pipe_physical_name(reserved, "aql_set_sort_")
                  reserved.push(field)
                  // Only the combined output scope is visible. Reuse its
                  // evaluated slots; never expand an operand's SELECT.
                  let value = append_pipe_expression(
                    construction,
                    term.expression,
                    visible,
                    [],
                    limits.max_expression_work,
                  )
                  derives.push((field, value))
                  hidden.push((term.expression, field))
                  field
                }
              }
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
        let mut sort_from = current
        let sort_output = if derives.is_empty() {
          final_name
        } else {
          let derived = prefix + "aql_set_order_input_" + index.to_string()
          steps.push(
            construction.object([
              ("from", construction.text(current)),
              ("derive", construction.object(derives)),
              ("as", construction.text(derived)),
            ]),
          )
          sort_from = derived
          prefix + "aql_set_ordered_" + index.to_string()
        }
        steps.push(
          construction.object([
            ("from", construction.text(sort_from)),
            ("sort", construction.array(sort)),
            ("as", construction.text(sort_output)),
          ]),
        )
        if !derives.is_empty() {
          steps.push(
            construction.object([
              ("from", construction.text(sort_output)),
              (
                "select",
                construction.array(
                  left_fields.map(field => construction.text(field)),
                ),
              ),
              ("as", construction.text(final_name)),
            ]),
          )
        }
      }
      Limit(count, offset) =>
        steps.push(
          construction.object([
            ("from", construction.text(current)),
            (
              "take",
              construction.object([
                ("count", construction.add(Number(count.to_double()))),
                ("offset", construction.add(Number(offset.to_double()))),
              ]),
            ),
            ("as", construction.text(final_name)),
          ]),
        )
      _ => raise Abort(UnsupportedSet)
    }
    current = final_name
  }
  current
}
