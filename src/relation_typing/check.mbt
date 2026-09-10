///|
fn expression(
  b : Budget,
  source : @decode.Cursor,
  name : String?,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  parameters : @parameter.Declarations?,
) -> Binding raise Stop {
  let admitted = match
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
  let usage = @syntax.usage(admitted)
  spend(b, source, count=usage.nodes)
  b.nodes -= usage.nodes
  b.text -= usage.text_bytes
  b.tokens -= usage.tokens
  let references : Array[Reference] = []
  let fields : Array[(String, @contract.Contract)] = []
  let left : Array[(String, @contract.Contract)] = []
  let right : Array[(String, @contract.Contract)] = []
  let seen : Map[String, Bool] = Map([])
  for occurrence in @syntax.relation_references(admitted) {
    spend(b, source)
    match visible.get(occurrence.name) {
      None => unknown_reference(source, occurrence)
      Some((contract, target)) => {
        references.push({ occurrence, target, })
        if !seen.contains(occurrence.name) {
          seen[occurrence.name] = true
          match reference_target(occurrence.name, target) {
            @schema.Unqualified(name) => fields.push((name, contract))
            @schema.Qualified(Left, name) => left.push((name, contract))
            @schema.Qualified(Right, name) => right.push((name, contract))
          }
        }
      }
    }
  }
  let scope = object_type(b, source, fields)
  let left = if left.is_empty() {
    None
  } else {
    Some(object_type(b, source, left))
  }
  let right = if right.is_empty() {
    None
  } else {
    Some(object_type(b, source, right))
  }
  let typed = match
    @typing.check(admitted, { fields: Some(scope), left, right, parameters, }, {
      max_nodes: b.nodes.min(b.work),
      max_depth: b.limits.max_depth,
      max_work: b.work,
      max_text_bytes: b.text,
    }) {
    Ok(value) => value
    Err(issue) => fail(issue.source, Expression(issue.kind))
  }
  let usage = @typing.usage(typed)
  spend(b, source, count=usage.work)
  b.nodes -= usage.nodes
  b.text -= usage.text_bytes
  { name, source, expression: typed, references, }
}

///|
fn check_impl(
  operation : Operation,
  body : @decode.Cursor,
  input : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> CheckedOperation raise Stop {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_tokens < 0 {
    fail(body, InvalidLimits)
  }
  let b : Budget = {
    work: limits.max_work,
    text: limits.max_text_bytes,
    nodes: limits.max_nodes,
    tokens: limits.max_tokens,
    limits,
  }
  schema_preflight(b, body, input)
  if parameters is Some(params) {
    let count = @parameter.declaration_count(params)
    spend(b, body, count~)
    for i in 0..<count {
      let p = @parameter.declaration_at(params, i).unwrap()
      charge(b, body, p.name)
      preflight(b, body, p.parameter_type.contract)
    }
  }
  let visible : Map[String, (@contract.Contract, ReferenceTarget)] = Map([])
  let count = @schema.field_count(input)
  spend(b, body, count~)
  for i in 0..<count {
    let field = @schema.field_at(input, i).unwrap()
    visible[@schema.reference_name(field.name)] = (
      field.contract,
      InputField(field.name),
    )
  }
  let bindings : Array[Binding] = []
  let projection : Array[ProjectionField] = []
  let mut output = input
  let form = match operation {
    Filter => {
      let binding = expression(b, body, None, visible, parameters)
      if !(@typing.result_type(binding.expression).shape is @contract.Boolean) {
        fail(body, ExpectedBoolean)
      }
      bindings.push(binding)
      Predicate
    }
    Derive => {
      let slots : Array[(String, @decode.Cursor)] = []
      let sequential = match @decode.view(body) {
        @decode.ObjectValue(object) => {
          let names = decoded(@decode.object_field_names(body), body)
          spend(b, body, count=names.length())
          names.sort_by(@canonical.compare_utf16)
          for name in names {
            slots.push((name, @decode.lookup(object, name).unwrap()))
          }
          false
        }
        @decode.ArrayValue(items) => {
          spend(b, body, count=items.length())
          for item in items {
            let names = decoded(@decode.object_field_names(item), item)
            if names.length() != 1 {
              fail(item, InvalidBody)
            }
            let obj = decoded(@decode.open_object(item), item)
            slots.push((names[0], @decode.lookup(obj, names[0]).unwrap()))
          }
          true
        }
        _ => fail(body, InvalidBody)
      }
      if sequential && slots.is_empty() {
        fail(body, EmptyBody)
      }
      let seen : Map[String, Bool] = Map([])
      for i in 0..<slots.length() {
        let (name, source) = slots[i]
        field_name(b, source, name)
        if seen.contains(name) {
          fail(source, DuplicateOutput(name))
        }
        seen[name] = true
        if !sequential && visible.contains(name) {
          fail(source, InputCollision(name))
        }
        let checked = expression(b, source, Some(name), visible, parameters)
        if sequential {
          visible[name] = (
            @typing.result_type(checked.expression),
            PriorSlot(i),
          )
        }
        bindings.push(checked)
      }
      if !sequential {
        for i in 0..<bindings.length() {
          let binding = bindings[i]
          visible[binding.name.unwrap()] = (
            @typing.result_type(binding.expression),
            PriorSlot(i),
          )
        }
      }
      let fields : Array[(@schema.FieldName, @contract.Contract)] = []
      spend(b, body, count=visible.length())
      for name, value in visible {
        fields.push((reference_target(name, value.1), value.0))
      }
      output = schema_type(b, body, fields)
      if sequential {
        DeriveArray
      } else {
        DeriveMap
      }
    }
    Select | Rename | Drop => {
      let selected : Map[String, Bool] = Map([])
      match operation {
        Select => {
          let items = decoded(@decode.elements(body), body)
          spend(b, body, count=items.length())
          for item in items {
            let (output, input) = match @decode.view(item) {
              @decode.TextValue(name) => {
                let field = input_reference(b, item, name, visible)
                (field, field)
              }
              @decode.ObjectValue(obj) => {
                let names = decoded(@decode.object_field_names(item), item)
                if names.length() != 1 {
                  fail(item, InvalidBody)
                }
                let name = names[0]
                field_name(b, item, name)
                let reference = decoded(
                  @decode.text(@decode.lookup(obj, name).unwrap()),
                  item,
                )
                (
                  @schema.Unqualified(name),
                  input_reference(b, item, reference, visible),
                )
              }
              _ => fail(item, InvalidBody)
            }
            let output_name = @schema.reference_name(output)
            if selected.contains(output_name) {
              fail(item, DuplicateOutput(output_name))
            }
            selected[output_name] = true
            projection.push({ output, input, })
          }
        }
        Rename => {
          let object = decoded(@decode.open_object(body), body)
          let names = decoded(@decode.object_field_names(body), body)
          let renamed : Map[String, String] = Map([])
          spend(b, body, count=names.length())
          for name in names {
            let source = @decode.lookup(object, name).unwrap()
            ignore(input_reference(b, source, name, visible))
            let target = decoded(@decode.text(source), source)
            field_name(b, source, target)
            renamed[name] = target
          }
          for i in 0..<count {
            spend(b, body)
            let input = @schema.field_at(input, i).unwrap().name
            let output = match renamed.get(@schema.reference_name(input)) {
              Some(name) => @schema.Unqualified(name)
              None => input
            }
            let output_name = @schema.reference_name(output)
            if selected.contains(output_name) {
              fail(body, DuplicateOutput(output_name))
            }
            selected[output_name] = true
            projection.push({ output, input, })
          }
        }
        Drop => {
          let items = decoded(@decode.elements(body), body)
          spend(b, body, count=items.length())
          for item in items {
            let name = decoded(@decode.text(item), item)
            ignore(input_reference(b, item, name, visible))
            selected[name] = true
          }
          for i in 0..<count {
            spend(b, body)
            let name = @schema.field_at(input, i).unwrap().name
            if !selected.contains(@schema.reference_name(name)) {
              projection.push({ output: name, input: name, })
            }
          }
        }
        _ => fail(body, InvalidBody)
      }
      if projection.is_empty() && (operation is Select || count > 0) {
        fail(body, EmptyBody)
      }
      let fields : Array[(@schema.FieldName, @contract.Contract)] = []
      spend(b, body, count=projection.length())
      for p in projection {
        fields.push(
          (p.output, visible.get(@schema.reference_name(p.input)).unwrap().0),
        )
      }
      output = schema_type(b, body, fields)
      Projection
    }
  }
  schema_preflight(b, body, output)
  {
    operation,
    form,
    source: body,
    input,
    output,
    parameters,
    bindings,
    projection,
    work_used: limits.max_work - b.work,
    text_bytes_used: limits.max_text_bytes - b.text,
    nodes_used: limits.max_nodes - b.nodes,
    tokens_used: limits.max_tokens - b.tokens,
  }
}

///|
/// Check an operation body, not a step envelope. from/as/meta and stage naming
/// are outside this boundary. Success is not permission to execute a Relation.
pub fn check(
  operation : Operation,
  body : @decode.Cursor,
  input : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedOperation, Issue] {
  Ok(check_impl(operation, body, input, parameters, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
