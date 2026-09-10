///|
fn metadata(b : Budget, root : @decode.Cursor) -> Unit raise Stop {
  let object = match @decode.open_object(root) {
    Ok(v) => v
    Err(_) => fail(root, InvalidMetadata)
  }
  let keys = @decode.object_field_names(root).unwrap()
  if keys.is_empty() {
    fail(root, InvalidMetadata)
  }
  spend(b, root, keys.length())
  for key in keys {
    if key.has_prefix("actql_") {
      fail(@decode.lookup(object, key).unwrap(), ReservedMetadataKey(key))
    }
  }
  let work = [(root, 0)]
  while work.pop() is Some((cursor, depth)) {
    spend(b, cursor, 1)
    if b.nodes == 0 {
      fail(cursor, BudgetExceeded)
    }
    b.nodes -= 1
    match @decode.view(cursor) {
      TextValue(v) => charge(b, cursor, v)
      ArrayValue(items) => {
        if depth >= b.limits.max_depth {
          fail(cursor, BudgetExceeded)
        }
        spend(b, cursor, items.length())
        for item in items {
          work.push((item, depth + 1))
        }
      }
      ObjectValue(obj) => {
        if depth >= b.limits.max_depth {
          fail(cursor, BudgetExceeded)
        }
        let names = @decode.object_field_names(cursor).unwrap()
        spend(b, cursor, names.length())
        for key in names {
          charge(b, cursor, key)
          work.push((@decode.lookup(obj, key).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn check_impl(
  source : @decode.Cursor,
  supplied_inputs : Array[(String, @contract.Contract)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
) -> CheckedPipeline raise Stop {
  if limits.max_steps < 0 ||
    limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_depth < 0 {
    fail(source, InvalidLimits)
  }
  let b : Budget = {
    limits,
    work: limits.max_work,
    text: limits.max_text_bytes,
    nodes: limits.max_nodes,
    tokens: limits.max_tokens,
  }
  let bodies = match @decode.elements(source) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
  if bodies.length() > limits.max_steps {
    fail(source, BudgetExceeded)
  }
  spend(b, source, supplied_inputs.length())
  let inputs = supplied_inputs.copy()
  let names : Map[String, Target] = Map([])
  for i in 0..<inputs.length() {
    let (key, contract) = inputs[i]
    name(b, source, key)
    if names.contains(key) {
      fail(source, DuplicateName(key))
    }
    if contract.nullable || !(contract.shape is @contract.Object(_)) {
      fail(source, InvalidInputSchema(key))
    }
    preflight(b, source, contract)
    names[key] = Input(i)
  }
  if parameters is Some(p) {
    let count = @parameter.declaration_count(p)
    spend(b, source, count)
    for i in 0..<count {
      let d = @parameter.declaration_at(p, i).unwrap()
      charge(b, source, d.name)
      preflight(b, source, d.parameter_type.contract)
    }
  }
  let mut current : Target? = match from {
    Some(cursor) => {
      let key = read_name(b, cursor)
      match names.get(key) {
        Some(v) => Some(v)
        None => fail(cursor, UnknownName(key))
      }
    }
    None => if inputs.length() == 1 { Some(Input(0)) } else { None }
  }
  let steps : Array[CheckedStep] = []
  for body in bodies {
    spend(b, body, 1)
    if b.nodes == 0 {
      fail(body, BudgetExceeded)
    }
    b.nodes -= 1
    let object = match @decode.open_object(body) {
      Ok(v) => v
      Err(_) => fail(body, InvalidBody)
    }
    let keys = @decode.object_field_names(body).unwrap()
    spend(b, body, keys.length())
    let mut operation_name : String? = None
    for key in keys {
      charge(b, body, key)
      if key != "from" && key != "as" && key != "meta" {
        if operation_name is Some(_) {
          fail(body, InvalidBody)
        }
        operation_name = Some(key)
      }
    }
    let key = match operation_name {
      Some(v) => v
      None => fail(body, InvalidBody)
    }
    let op : @relation.Operation = match key {
      "derive" => Derive
      "filter" => Filter
      "select" => Select
      "rename" => Rename
      "drop" => Drop
      _ => fail(@decode.lookup(object, key).unwrap(), UnsupportedOperation(key))
    }
    let input = match @decode.lookup(object, "from") {
      Some(cursor) => {
        let key = read_name(b, cursor)
        match names.get(key) {
          Some(v) => v
          None => fail(cursor, UnknownName(key))
        }
      }
      None =>
        match current {
          Some(v) => v
          None => fail(body, MissingCurrent)
        }
    }
    let binding_name = match @decode.lookup(object, "as") {
      Some(cursor) => {
        let key = read_name(b, cursor)
        if names.contains(key) {
          fail(cursor, DuplicateName(key))
        }
        Some(key)
      }
      None => None
    }
    let meta = @decode.lookup(object, "meta")
    if meta is Some(cursor) {
      metadata(b, cursor)
    }
    let checked = match
      @relation.check(
        op,
        @decode.lookup(object, key).unwrap(),
        schema(input, inputs, steps),
        parameters,
        {
          max_work: b.work,
          max_text_bytes: b.text,
          max_nodes: b.nodes,
          max_tokens: b.tokens,
          max_depth: limits.max_depth,
        },
      ) {
      Ok(v) => v
      Err(issue) =>
        raise Stop({
          kind: Operation(issue.kind),
          source: issue.source,
          path: issue.path.copy(),
          span: issue.span,
          range: issue.range,
        })
    }
    b.work -= @relation.work_used(checked)
    b.text -= @relation.text_bytes_used(checked)
    b.nodes -= @relation.nodes_used(checked)
    b.tokens -= @relation.tokens_used(checked)
    let target = Step(steps.length())
    steps.push({
      source: body,
      input,
      binding_name,
      metadata: meta,
      operation: checked,
    })
    if binding_name is Some(key) {
      names[key] = target
    }
    current = Some(target)
  }
  let current = match current {
    Some(v) => v
    None => fail(source, MissingCurrent)
  }
  {
    source,
    inputs,
    steps,
    names,
    current,
    output: schema(current, inputs, steps),
    initial_from: from,
    parameters,
    usage: {
      work: limits.max_work - b.work,
      text_bytes: limits.max_text_bytes - b.text,
      nodes: limits.max_nodes - b.nodes,
      tokens: limits.max_tokens - b.tokens,
    },
  }
}

///|
/// Inputs are resolved materialized Relations, never search-template bindings.
/// Source is the normalized steps array; from is the optional stage selector.
pub fn check(
  source : @decode.Cursor,
  inputs : Array[(String, @contract.Contract)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
) -> Result[CheckedPipeline, Issue] {
  Ok(check_impl(source, inputs, parameters, from, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
