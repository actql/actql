///|
// An explicit ON list retains strict BY NAME matching and determines output
// spelling and order. Schema/type compatibility stays with the common checker.
fn set_output_fields(
  left_fields : Array[String],
  part : @query.SetPart,
  right_fields? : Array[String] = [],
) -> Array[String] raise Abort {
  if part.inner_by_name {
    return set_inner_fields(left_fields, [right_fields], part)
  }
  match part.by_name_columns {
    None => left_fields
    Some(columns) => {
      if !part.by_name || columns.length() != left_fields.length() {
        raise Abort(UnsupportedSet)
      }
      let fields : Array[String] = []
      for name in columns {
        if fields.any(field => same_name(name, { value: field, quoted: false, })) {
          raise Abort(UnsupportedSet)
        }
        fields.push(name.value)
      }
      // Also rejects missing or ambiguous input columns under field-name rules.
      ignore(set_alignment_fields(fields, left_fields, true))
      fields
    }
  }
}

///|
fn set_select_fields(
  construction : Construction,
  fields : Array[String],
  matched : Array[String],
) -> @builder.Node raise Abort {
  construction.array(
    fields.mapi((index, field) => {
      let source = construction.text(matched[index])
      if field == matched[index] {
        source
      } else {
        construction.object([(field, source)])
      }
    }),
  )
}

///|
fn set_alignment_fields(
  left_fields : Array[String],
  right_fields : Array[String],
  by_name : Bool,
  allow_subset? : Bool = false,
) -> (Array[String], Bool) raise Abort {
  if right_fields.length() < left_fields.length() ||
    (!allow_subset && right_fields.length() != left_fields.length()) {
    raise Abort(UnsupportedSet)
  }
  let mut alignment_needed = right_fields.length() != left_fields.length()
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
  if !allow_subset && matched.length() != right_fields.length() {
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
  let order_windows : Array[(String, String)] = []
  for index in 0..<@query.final_operation_count(query) {
    let operation = @query.final_operation_at(query, index).unwrap()
    let final_name = prefix + "aql_set_final_" + index.to_string()
    match operation {
      OrderAnalytic(projections, false) => {
        let reserved = left_fields.copy()
        let groups : Array[Array[@query.Projection]] = []
        for projection in projections {
          let name = projection.name.unwrap().value
          let slot = if reserved.contains(name) {
            pipe_physical_name(reserved, "aql_set_window_")
          } else {
            name
          }
          reserved.push(slot)
          order_windows.push((name, slot))
          let projected = {
            ..projection,
            name: Some({ value: slot, quoted: false, }),
          }
          let mut found = false
          for group in groups {
            if same_analytic_window(
                group[0].analytic.unwrap().window,
                projected.analytic.unwrap().window,
              ) {
              group.push(projected)
              found = true
              break
            }
          }
          if !found {
            groups.push([projected])
          }
        }
        let derives : Array[(String, @builder.Node)] = []
        let evaluated : Array[(@query.Expression, String)] = []
        let visible = left_fields.map(field => (field, field))
        let bodies = groups.map(group => {
          lower_analytic(
            construction,
            group,
            path => pipe_slot(path, visible, []),
            limits.max_expression_work,
            limits.max_collection_bytes,
            reserved,
            evaluated,
            derives,
          )
        })
        if !derives.is_empty() {
          let derived = prefix + "aql_set_window_input_" + index.to_string()
          steps.push(
            construction.object([
              ("from", construction.text(current)),
              ("derive", construction.object(derives)),
              ("as", construction.text(derived)),
            ]),
          )
          current = derived
        }
        for group_index in 0..<bodies.length() {
          let next = if group_index + 1 == bodies.length() {
            final_name
          } else {
            prefix +
            "aql_set_window_" +
            index.to_string() +
            "_" +
            group_index.to_string()
          }
          steps.push(
            construction.object([
              ("from", construction.text(current)),
              ("analytic", bodies[group_index]),
              ("as", construction.text(next)),
            ]),
          )
          current = next
        }
      }
      Order(terms) => {
        let sort : Array[@builder.Node] = []
        let hidden : Array[(@query.Expression, String)] = []
        let derives : Array[(String, @builder.Node)] = []
        let reserved = left_fields + order_windows.map(pair => pair.1)
        let visible = order_windows + left_fields.map(field => (field, field))
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
        let sort_output = if derives.is_empty() && order_windows.is_empty() {
          final_name
        } else {
          let derived = prefix + "aql_set_order_input_" + index.to_string()
          if !derives.is_empty() {
            steps.push(
              construction.object([
                ("from", construction.text(current)),
                ("derive", construction.object(derives)),
                ("as", construction.text(derived)),
              ]),
            )
            sort_from = derived
          }
          prefix + "aql_set_ordered_" + index.to_string()
        }
        steps.push(
          construction.object([
            ("from", construction.text(sort_from)),
            ("sort", construction.array(sort)),
            ("as", construction.text(sort_output)),
          ]),
        )
        if !derives.is_empty() || !order_windows.is_empty() {
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
        order_windows.clear()
      }
      Limit(count, offset) =>
        steps.push(
          construction.object([
            ("from", construction.text(current)),
            (
              "take",
              construction.object([
                ("count", lower_query_integer(construction, count)),
                ("offset", lower_query_integer(construction, offset)),
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

///|
fn set_alignment_stage(
  construction : Construction,
  source : String,
  name : String,
  fields : Array[String],
  matched : Array[String],
) -> @builder.Node raise Abort {
  construction.object([
    ("id", construction.text(name)),
    (
      "inputs",
      construction.object([
        (
          "r",
          construction.object([
            (
              "result",
              construction.object([
                ("stage", construction.text(source)),
                ("result", construction.text(source)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    (
      "steps",
      construction.array([
        construction.object([
          ("from", construction.text("r")),
          ("select", set_select_fields(construction, fields, matched)),
          ("as", construction.text("aligned_rows")),
        ]),
      ]),
    ),
    (
      "results",
      construction.object([
        (
          name,
          construction.object([
            ("from", construction.text("aligned_rows")),
            (
              "fields",
              construction.array(fields.map(field => construction.text(field))),
            ),
          ]),
        ),
      ]),
    ),
  ])
}

///|
fn set_inner_chain_length(query : @query.Query) -> Int {
  let mut count = 0
  for index in 0..<@query.set_part_count(query) {
    let part = @query.set_part_at(query, index).unwrap()
    if !part.sql_chain || !part.inner_by_name {
      break
    }
    count = count + 1
  }
  count
}

///|
// SQL chains choose their complete output-name intersection before type
// checking intermediate sets. Pipe operators consume their current row scope.
fn set_inner_fields(
  left : Array[String],
  rights : Array[Array[String]],
  part : @query.SetPart,
) -> Array[String] raise Abort {
  let inputs = [left] + rights
  for fields in inputs {
    for index in 0..<fields.length() {
      for other in (index + 1)..<fields.length() {
        if same_name({ value: fields[index], quoted: false, }, {
            value: fields[other],
            quoted: false,
          }) {
          raise Abort(UnsupportedSet)
        }
      }
    }
  }
  let fields = match part.by_name_columns {
    Some(columns) => columns.map(name => name.value)
    None =>
      left.filter(field => {
        rights.all(right => {
          right.any(candidate => {
            same_name({ value: field, quoted: false, }, {
              value: candidate,
              quoted: false,
            })
          })
        })
      })
  }
  if fields.is_empty() {
    raise Abort(UnsupportedSet)
  }
  for index in 0..<fields.length() {
    for other in (index + 1)..<fields.length() {
      if same_name({ value: fields[index], quoted: false, }, {
          value: fields[other],
          quoted: false,
        }) {
        raise Abort(UnsupportedSet)
      }
    }
  }
  for input in inputs {
    ignore(set_alignment_fields(fields, input, true, allow_subset=true))
  }
  fields
}

///|
fn set_term_stage(
  construction : Construction,
  name : String,
  input : String,
  seed_stage : String,
  seed_result : String,
  steps : Array[@builder.Node],
  result : String,
  fields : Array[String],
) -> @builder.Node raise Abort {
  construction.object([
    ("id", construction.text(name)),
    (
      "inputs",
      construction.object([
        (
          input,
          construction.object([
            (
              "result",
              construction.object([
                ("stage", construction.text(seed_stage)),
                ("result", construction.text(seed_result)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    ("steps", construction.array(steps)),
    (
      "results",
      construction.object([
        (
          name,
          construction.object([
            ("from", construction.text(result)),
            (
              "fields",
              construction.array(fields.map(field => construction.text(field))),
            ),
          ]),
        ),
      ]),
    ),
  ])
}
