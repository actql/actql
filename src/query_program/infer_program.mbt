///|
// A source projection, not a checked ModelTask or permission to call a model.
// The shared checker must resolve the contract, prove the complete key tuple,
// and bind captured outcomes and their provenance before executing this graph.
fn lower_infer_steps(
  construction : Construction,
  clause : @query.InferClause,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  physical : Array[String],
  initial : Array[(String, @builder.Node)],
  index : Int,
  input_name : String,
  max_work : Int,
) -> (Array[Array[(String, @builder.Node)]], Array[String]) raise Abort {
  if clause.contract.value == "" || clause.name.value == "" {
    raise Abort(UnsupportedInfer)
  }
  let keys : Array[(String, String)] = []
  for path in clause.keys {
    let slot = match pipe_slot(path, visible, ranges) {
      Some(slot) => slot
      None => raise Abort(UnknownColumn)
    }
    let name = path.last().unwrap().value
    if ["OUTCOME", "VALUE"].contains(ascii_upper(name)) ||
      keys.any(key => key.1 == slot || ascii_upper(key.0) == ascii_upper(name)) {
      raise Abort(UnsupportedInfer)
    }
    keys.push((name, slot))
  }
  if keys.is_empty() {
    raise Abort(UnsupportedInfer)
  }
  let retained : Array[(String, String)] = []
  for item in clause.keep {
    let expanded : Array[(String, String)] = []
    if item.wildcard {
      if item.path.is_empty() {
        expanded.append(visible)
      } else if item.path.length() == 1 {
        let matches = ranges.filter(range => same_name(range.0, item.path[0]))
        if matches.length() != 1 {
          raise Abort(UnknownColumn)
        }
        expanded.append(matches[0].1)
      } else {
        raise Abort(UnknownColumn)
      }
    } else {
      let slot = match pipe_slot(item.path, visible, ranges) {
        Some(slot) => slot
        None => raise Abort(UnknownColumn)
      }
      expanded.push(
        (item.name.unwrap_or(item.path.last().unwrap()).value, slot),
      )
    }
    for entry in expanded {
      let name : @query.NamePart = { value: entry.0, quoted: false, }
      if pipe_name_exists(retained, name) || same_name(name, clause.name) {
        raise Abort(DuplicateOutput)
      }
      retained.push(entry)
    }
  }
  let input_names = infer_input_names(
    clause,
    construction.model_tasks,
    max_work,
  )
  let reserved = physical.copy()
  let input_fields : Array[(String, @builder.Node)] = []
  let mappings : Array[(String, @builder.Node)] = []
  for argument_index, argument in clause.inputs {
    if mappings.any(entry => {
        ascii_upper(entry.0) == ascii_upper(argument.0.value)
      }) {
      raise Abort(DuplicateOutput)
    }
    let expression = argument.1
    let direct = match
      @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind {
      Reference(path) => pipe_slot(path, visible, ranges)
      _ => None
    }
    let slot = match direct {
      Some(slot) => slot
      None => {
        let slot = pipe_physical_name(reserved, "aql_infer_argument_")
        reserved.push(slot)
        input_fields.push(
          (
            slot,
            append_pipe_expression(
              construction, expression, visible, ranges, max_work,
            ),
          ),
        )
        slot
      }
    }
    // The mapping value denotes this authored input occurrence, including a
    // same-name shorthand. Retain its range through common contract typing.
    let argument_construction = {
      ..construction,
      generated: @query.expression_origin(
        expression,
        @query.expression_root(expression),
      ).unwrap_or(construction.generated),
    }
    mappings.push(
      (
        input_names[argument_index],
        argument_construction.object([
          ("field", argument_construction.text(slot)),
        ]),
      ),
    )
  }
  let steps : Array[Array[(String, @builder.Node)]] = []
  let prefix = initial.copy()
  if !input_fields.is_empty() {
    prefix.push(("derive", construction.object(input_fields)))
    // The next step reuses this scratch array. Retain the emitted derive
    // before clearing it; otherwise both steps become the later projection.
    steps.push(prefix.copy())
    prefix.clear()
  }
  // Reuse one producer. KEEP never copies the source or dispatches it again.
  let mut snapshot = "aql_infer_input_" + index.to_string()
  while snapshot == input_name {
    snapshot += "_"
  }
  prefix.push(
    (
      "select",
      construction.array(reserved.map(field => construction.text(field))),
    ),
  )
  prefix.push(("as", construction.text(snapshot)))
  steps.push(prefix)
  let mut captured = "aql_infer_outcome_" + index.to_string()
  while captured == input_name || captured == snapshot {
    captured += "_"
  }
  steps.push([
    ("from", construction.text(snapshot)),
    (
      "infer",
      construction.object([
        ("contract", construction.text(clause.contract.value)),
        (
          "key",
          if keys.length() == 1 {
            construction.text(keys[0].1)
          } else {
            construction.array(keys.map(key => construction.text(key.1)))
          },
        ),
        ("input", construction.object(mappings)),
      ]),
    ),
    ("as", construction.text(captured)),
  ])
  let key_fields : Array[(String, @builder.Node)] = []
  let role_slots : Array[String] = []
  if !retained.is_empty() {
    let join_fields : Array[(String, @builder.Node)] = []
    let join_reserved = retained.map(entry => entry.0) + [clause.name.value]
    for entry in retained {
      join_fields.push(
        (entry.0, infer_join_field(construction, "right", entry.1)),
      )
    }
    for key in keys {
      let slot = pipe_physical_name(join_reserved, "aql_infer_key_")
      join_reserved.push(slot)
      join_fields.push((slot, infer_join_field(construction, "left", key.1)))
      key_fields.push((key.0, infer_field(construction, slot)))
    }
    for role in ["outcome", "value"] {
      let slot = pipe_physical_name(join_reserved, "aql_infer_role_")
      join_reserved.push(slot)
      join_fields.push((slot, infer_join_field(construction, "left", role)))
      role_slots.push(slot)
    }
    steps.push([
      (
        "join",
        construction.object([
          ("with", construction.text(snapshot)),
          ("kind", construction.text("inner")),
          ("cardinality", construction.text("one_to_one")),
          (
            "on",
            construction.array(
              keys.map(key => {
                construction.object([
                  ("left", construction.text(key.1)),
                  ("right", construction.text(key.1)),
                ])
              }),
            ),
          ),
          ("select", construction.object(join_fields)),
        ]),
      ),
    ])
  } else {
    for key in keys {
      key_fields.push((key.0, infer_field(construction, key.1)))
    }
    role_slots.append(["outcome", "value"])
  }
  let result = construction.object([
    (
      "object",
      construction.object([
        (
          "input_key",
          construction.object([("object", construction.object(key_fields))]),
        ),
        ("outcome", infer_field(construction, role_slots[0])),
        ("value", infer_field(construction, role_slots[1])),
      ]),
    ),
  ])
  // Avoid collisions with flat keys and KEEP columns before the final projection.
  let result_slot = pipe_physical_name(
    reserved + retained.map(entry => entry.0) + role_slots,
    "aql_infer_result_",
  )
  steps.push([("derive", construction.object([(result_slot, result)]))])
  let selected = retained.map(entry => construction.text(entry.0))
  selected.push(
    construction.object([(clause.name.value, construction.text(result_slot))]),
  )
  steps.push([("select", construction.array(selected))])
  (steps, retained.map(entry => entry.0) + [clause.name.value])
}

///|
fn infer_field(
  construction : Construction,
  field : String,
) -> @builder.Node raise Abort {
  construction.object([("field", construction.text(field))])
}

///|
// INPUT names select fields of the admitted ModelTask input contract. They are
// identifiers, unlike literal object keys or the opaque contract selector.
// Missing owners/selectors retain the ordinary checker's existing refusal.
fn infer_input_names(
  clause : @query.InferClause,
  model_tasks : @environment.ModelTasks?,
  max_work : Int,
) -> Array[String] raise Abort {
  let authored = clause.inputs.map(argument => argument.0.value)
  guard model_tasks is Some(tasks) else { return authored }
  let task = match
    @environment.resolve_model_task(tasks, clause.contract.value) {
    Ok(task) => task
    Err(_) => return authored
  }
  guard @environment.model_task_input(task).shape is @contract.Object(fields) else {
    return authored
  }
  resolve_infer_input_names(clause, fields, max_work)
}

///|
fn resolve_infer_input_names(
  clause : @query.InferClause,
  fields : @contract.Fields,
  max_work : Int,
) -> Array[String] raise Abort {
  let authored = clause.inputs.map(argument => argument.0.value)
  let mut remaining = max_work
  let resolved : Array[String] = []
  for argument_index, name in authored {
    let mut found : String? = None
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      let cost = 1L + name.length().to_int64() + field.name.length().to_int64()
      if cost > remaining.to_int64() {
        let expression = clause.inputs[argument_index].1
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @query.expression_origin(
              expression,
              @query.expression_root(expression),
            ),
          }),
        )
      }
      remaining -= cost.to_int()
      if ascii_upper(name) == ascii_upper(field.name) {
        if found is Some(_) {
          raise Abort(AmbiguousColumn)
        }
        found = Some(field.name)
      }
    }
    // An unknown field stays unknown to common input-contract checking.
    resolved.push(found.unwrap_or(name))
  }
  resolved
}

///|
fn infer_join_field(
  construction : Construction,
  side : String,
  field : String,
) -> @builder.Node raise Abort {
  // Join selections use the existing qualified field-reference contract.
  // Keep/AS lowering must not introduce a second join-field wire shape.
  construction.text(side + "." + field)
}
