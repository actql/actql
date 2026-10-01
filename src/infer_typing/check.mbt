///|
fn model_input_preflight(
  b : Budget,
  source : @decode.Cursor,
  root : @contract.Contract,
) -> Unit raise Stop {
  let work = [(root, 0)]
  while work.pop() is Some((c, depth)) {
    spend(b, source)
    if depth > b.limits.max_depth {
      fail(source, BudgetExceeded)
    }
    match c.shape {
      @contract.ResourceRef(..) => fail(source, ForbiddenModelInput)
      @contract.Array(item, ..) => work.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, source, count~)
        for i in 0..<count {
          let field = @contract.field_at(fields, i).unwrap()
          charge(b, source, field.name)
          work.push((field.contract, depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn expression_scope(
  b : Budget,
  source : @decode.Cursor,
  schema : @schema.Schema,
  parameters : @parameter.Declarations?,
) -> @expression.Environment raise Stop {
  if @schema.as_object(schema) is Some(row) {
    return { fields: Some(row), left: None, right: None, parameters, }
  }
  let count = @schema.field_count(schema)
  spend(b, source, count~)
  let fields = []
  let left = []
  let right = []
  let bytes = b.text
  for i in 0..<count {
    let field = @schema.field_at(schema, i).unwrap()
    let (target, name) = match field.name {
      @schema.Unqualified(name) => (fields, name)
      @schema.Qualified(Left, name) => (left, name)
      @schema.Qualified(Right, name) => (right, name)
    }
    charge(b, source, name)
    target.push((name, field.contract))
  }
  let scope = (items : Array[(String, @contract.Contract)]) => {
    match
      @contract.object_contract(
        items,
        nullable=false,
        max_fields=count,
        max_name_bytes=bytes,
      ) {
      Ok(value) => value
      Err(_) => fail(source, InvalidBody)
    }
  }
  {
    fields: Some(scope(fields)),
    left: Some(scope(left)),
    right: Some(scope(right)),
    parameters,
  }
}

///|
fn input_expression(
  b : Budget,
  source : @decode.Cursor,
  env : @expression.Environment,
  role : String,
  expected : @contract.Contract,
) -> @expression.TypedExpression raise Stop {
  let syntax = match
    @syntax.admit(source, {
      max_nodes: b.nodes.min(b.work),
      max_depth: b.limits.max_depth,
      max_text_bytes: b.text,
      max_tokens: b.tokens,
      tree: {
        max_nodes: b.nodes.min(b.work),
        max_depth: b.limits.max_depth,
        max_string_bytes: b.text,
        max_total_string_bytes: b.text,
      },
    }) {
    Ok(value) => value
    Err(issue) => fail(source, Syntax(issue))
  }
  let used = @syntax.usage(syntax)
  spend(b, source, count=used.nodes)
  b.nodes -= used.nodes
  b.text -= used.text_bytes
  b.tokens -= used.tokens
  let limits : @expression.Limits = {
    max_nodes: b.nodes.min(b.work),
    max_depth: b.limits.max_depth,
    max_work: b.work,
    max_text_bytes: b.text,
  }
  let result = match expected.shape {
    @contract.Text(_) =>
      @expression.check_argument(syntax, env, StringArgument, limits)
    @contract.Number =>
      @expression.check_argument(syntax, env, NumberArgument, limits)
    @contract.Boolean =>
      @expression.check_argument(syntax, env, BooleanArgument, limits)
    _ => @expression.check(syntax, env, limits)
  }
  let expression = match result {
    Ok(value) => value
    Err(issue) => fail(issue.location.source, Expression(issue.kind))
  }
  let used = @expression.usage(expression)
  spend(b, source, count=used.work)
  b.nodes -= used.nodes
  b.text -= used.text_bytes
  let actual = @expression.result_type(expression)
  model_input_preflight(b, source, actual)
  let (compatible, count) = @contract.assignable_usage(actual, expected, b.work) catch {
    _ => fail(source, BudgetExceeded)
  }
  spend(b, source, count~)
  if !compatible {
    fail(source, InputTypeMismatch(role))
  }
  expression
}

///|
/// Resolves acquisition typing only. No adapter plan, authority or call slot is
/// admitted here, and the pure Relation evaluator cannot execute this owner.
pub fn check(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  keys : @evidence.KeySet?,
  tasks : @environment.ModelTasks,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedInfer, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_tokens < 0 ||
      limits.max_key_fields < 0 ||
      limits.max_input_roles < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      tokens: limits.max_tokens,
    }
    spend(b, source)
    let body = decoded(
      source,
      @decode.closed_object(source, [
        "contract", "key", "input", "max_items", "on_non_success", "minimum_classification",
      ]),
    )
    let selector_source = decoded(source, @decode.required(body, "contract"))
    let selector = decoded(selector_source, @decode.text(selector_source))
    charge(b, selector_source, selector)
    let task = match @environment.resolve_model_task(tasks, selector) {
      Ok(value) => value
      Err(issue) => fail(selector_source, Task(issue.kind))
    }
    let records = match @carrier.relation_rows(input) {
      Some(value) => value
      None => fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let schema = match @carrier.complete_schema(records) {
      Some(value) => value
      None => fail(source, IncompleteInputContract)
    }
    let (witness, key_fields) = resolve_key(
      b,
      source,
      @decode.lookup(body, "key"),
      records,
      schema,
      keys,
    )
    let task_input = @environment.model_task_input(task)
    model_input_preflight(b, source, task_input)
    guard task_input.shape is @contract.Object(input_fields) else {
      fail(source, InvalidBody)
    }
    let mapping_source = decoded(source, @decode.required(body, "input"))
    ignore(decoded(mapping_source, @decode.open_object(mapping_source)))
    let role_count = @contract.field_count(input_fields)
    let mapping_count = @decode.object_length(mapping_source).unwrap()
    if role_count > limits.max_input_roles ||
      mapping_count > limits.max_input_roles {
      fail(mapping_source, BudgetExceeded)
    }
    spend(b, mapping_source, count=mapping_count)
    let mapping = decoded(mapping_source, @decode.open_object(mapping_source))
    for i in 0..<mapping_count {
      let (name, at) = @decode.field_at(mapping_source, i).unwrap()
      charge(b, at, name)
      let mut known = false
      for j in 0..<role_count {
        spend(b, at)
        if @contract.field_at(input_fields, j).unwrap().name == name {
          known = true
          break
        }
      }
      if !known {
        fail(at, UnknownInputRole(name))
      }
    }
    spend(b, mapping_source, count=role_count)
    let bindings : Array[InputBinding] = []
    let env = expression_scope(b, source, schema, parameters)
    for i in 0..<role_count {
      let role = @contract.field_at(input_fields, i).unwrap()
      charge(b, mapping_source, role.name)
      let at = match @decode.lookup(mapping, role.name) {
        Some(value) => value
        None => fail(mapping_source, MissingInputRole(role.name))
      }
      let expression = input_expression(b, at, env, role.name, role.contract)
      bindings.push({ role: role.name, source: at, expression, })
    }
    let mode = match @decode.lookup(body, "on_non_success") {
      None => Outcomes
      Some(at) =>
        match decoded(at, @decode.text(at)) {
          "outcomes" => Outcomes
          "fail" => Fail
          _ => fail(at, InvalidBody)
        }
    }
    let minimum_classification = match
      @decode.lookup(body, "minimum_classification") {
      None => None
      Some(at) =>
        Some(
          match decoded(at, @decode.text(at)) {
            "public" => @environment.Public
            "internal" => Internal
            "confidential" => Confidential
            "restricted" => Restricted
            _ => fail(at, InvalidBody)
          },
        )
    }
    let max_items = match @decode.lookup(body, "max_items") {
      None => None
      Some(at) => {
        let checked_guard = match
          @relation.check_count_value(at, 1L, parameters, {
            max_work: b.work,
            max_text_bytes: b.text,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_tokens: b.tokens,
          }) {
          Ok(value) => value
          Err(issue) => fail(issue.source, Guard(issue.kind))
        }
        let (work, text) = @relation.count_value_usage(checked_guard)
        spend(b, at, count=work)
        b.text -= text
        Some(checked_guard)
      }
    }
    let count = key_fields.length() + 2
    spend(b, source, count~)
    let entries : Array[(@schema.FieldName, @contract.Contract)] = []
    let name_budget = b.text
    for field in key_fields {
      let name = @schema.reference_name(field.field)
      charge(b, source, name)
      entries.push((field.field, field.contract))
    }
    charge(b, source, "outcome")
    charge(b, source, "value")
    entries.push(
      (
        @schema.Unqualified("outcome"),
        @contract.primitive(StringType, nullable=false),
      ),
    )
    entries.push(
      (
        @schema.Unqualified("value"),
        @contract.with_nullability(@environment.model_task_output(task), true),
      ),
    )
    let output = match
      @schema.from_fields(entries, max_fields=count, max_name_bytes=name_budget) {
      Ok(value) => value
      Err(_) => fail(source, InvalidBody)
    }
    Ok({
      source,
      input: records,
      schema,
      task,
      parameters,
      key_witness: witness,
      keys: key_fields,
      bindings,
      output,
      mode,
      minimum_classification,
      max_items,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: limits.max_tokens - b.tokens,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}
