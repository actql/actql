///|
fn expression(
  b : Budget,
  source : @decode.Cursor,
  name : String?,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  parameters : @parameter.Declarations?,
  argument_domain? : @typing.ArgumentDomain? = None,
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
  for i in 0..<@syntax.relation_reference_count(admitted) {
    let occurrence = @syntax.relation_reference_at(admitted, i).unwrap()
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
  let environment : @typing.Environment = {
    fields: Some(scope),
    left,
    right,
    parameters,
  }
  let limits : @typing.Limits = {
    max_nodes: b.nodes.min(b.work),
    max_depth: b.limits.max_depth,
    max_work: b.work,
    max_text_bytes: b.text,
  }
  let result = match argument_domain {
    Some(domain) =>
      @typing.check_argument(admitted, environment, domain, limits)
    None => @typing.check(admitted, environment, limits)
  }
  let typed = match result {
    Ok(value) => value
    Err(issue) =>
      raise Stop({
        kind: Expression(issue.kind),
        source: issue.location.source,
        path: @syntax.location_path(issue.location),
        span: @syntax.location_span(issue.location),
        range: issue.location.range,
      })
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
  group_prefix? : Array[@schema.FieldName] = [],
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
  let parameter_types : Map[String, @contract.Contract] = Map([])
  if parameters is Some(params) {
    let count = @parameter.declaration_count(params)
    spend(b, body, count~)
    for i in 0..<count {
      let p = @parameter.declaration_at(params, i).unwrap()
      charge(b, body, p.name)
      preflight(b, body, p.parameter_type.contract)
      parameter_types[p.name] = p.parameter_type.contract
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
  let pending : Array[PendingValidation] = []
  let mut row_operation : RowOperation? = None
  let mut reshape : Reshape? = None
  let mut group : CheckedGroup? = None
  let mut pivot : CheckedPivot? = None
  let mut analytic : CheckedAnalytic? = None
  let mut output = input
  let form = match operation {
    TopK | TopKBy => {
      row_source(b, body)
      let obj = decoded(
        @decode.closed_object(
          body,
          if operation is TopK {
            ["k", "by"]
          } else {
            ["partition_by", "k", "by"]
          },
        ),
        body,
      )
      let partition = if operation is TopKBy {
        row_keys(
          b,
          decoded(@decode.required(obj, "partition_by"), body),
          visible,
          unique=false,
        )
      } else {
        []
      }
      let count = row_count(
        b,
        decoded(@decode.required(obj, "k"), body),
        1L,
        parameter_types,
        pending,
      )
      let source = decoded(@decode.required(obj, "by"), body)
      let order = row_order(b, source, visible)
      if order.is_empty() {
        fail(source, InvalidOrder)
      }
      row_operation = Some(
        if operation is TopKBy {
          pending.push({ kind: TopKPartitioning, source: body, })
          RowOperation::TopKBy(partition~, count~, order~)
        } else {
          RowOperation::TopK(count~, order~)
        },
      )
      pending.push({ kind: SortOrderCompletion, source, })
      pending.push({ kind: TopKSelectionEnvelope, source: body, })
      Form::RowOperation
    }
    Analytic => {
      row_source(b, body)
      let (details, fields) = check_analytic(
        b, body, input, visible, parameters, parameter_types, bindings, pending,
      )
      analytic = Some(details)
      output = schema_type(b, body, fields)
      Aggregation
    }
    Pivot => {
      row_source(b, body)
      let (details, fields) = check_pivot(
        b, body, visible, parameter_types, pending,
      )
      pivot = Some(details)
      output = schema_type(b, body, fields)
      Aggregation
    }
    Group => {
      row_source(b, body)
      let (details, fields) = check_group(
        b, body, visible, parameters, parameter_types, bindings, pending, group_prefix,
      )
      group = Some(details)
      output = schema_type(b, body, fields)
      Aggregation
    }
    Unpivot => {
      row_source(b, body)
      let (details, fields) = check_unpivot(b, body, visible)
      reshape = Some(details)
      output = schema_type(b, body, fields)
      pending.push({ kind: ValidateReshapeRows, source: body, })
      pending.push({ kind: ExpansionEnvelope, source: body, })
      Form::Reshape
    }
    AssertRows => {
      row_source(b, body)
      let obj = decoded(
        @decode.closed_object(body, ["where", "unique_by"]),
        body,
      )
      match (@decode.lookup(obj, "where"), @decode.lookup(obj, "unique_by")) {
        (Some(predicate), None) => {
          let binding = expression(b, predicate, None, visible, parameters)
          if !(@typing.result_type(binding.expression).shape
            is @contract.Boolean) {
            fail(predicate, ExpectedBoolean)
          }
          bindings.push(binding)
          row_operation = Some(AssertWhere)
        }
        (None, Some(source)) => {
          let keys = row_keys(b, source, visible, unique=true)
          if keys.is_empty() {
            fail(source, EmptyBody)
          }
          row_operation = Some(AssertUnique(keys))
        }
        _ => fail(body, InvalidBody)
      }
      pending.push({ kind: AtomicRowAssertion, source: body, })
      pending.push({ kind: AssertionConsumption, source: body, })
      Form::RowOperation
    }
    JsonPick | Unnest => {
      row_source(b, body)
      let (details, fields) = check_reshape(b, operation, body, input, visible)
      reshape = Some(details)
      output = schema_type(b, body, fields)
      pending.push({ kind: ValidateReshapeRows, source: body, })
      if operation is Unnest {
        pending.push({ kind: ExpansionEnvelope, source: body, })
      }
      Form::Reshape
    }
    Sort | Take | Distinct | DedupeRows => {
      row_source(b, body)
      row_operation = Some(
        match operation {
          Sort => {
            let terms = row_order(b, body, visible)
            if !terms.is_empty() {
              pending.push({ kind: SortOrderCompletion, source: body, })
            }
            RowOperation::Sort(terms)
          }
          Take => {
            let (count_source, offset_source) = match @decode.view(body) {
              ObjectValue(_) => {
                let names = @decode.object_field_names(body).unwrap()
                if names.length() == 1 && names[0] == "$param" {
                  (body, None)
                } else {
                  let obj = decoded(
                    @decode.closed_object(body, ["count", "offset"]),
                    body,
                  )
                  (
                    decoded(@decode.required(obj, "count"), body),
                    @decode.lookup(obj, "offset"),
                  )
                }
              }
              _ => (body, None)
            }
            let count = row_count(b, count_source, 1L, parameter_types, pending)
            let offset = match offset_source {
              Some(s) => row_count(b, s, 0L, parameter_types, pending)
              None => Literal(0L)
            }
            pending.push({ kind: StableInputOrder, source: body, })
            RowOperation::Take(count~, offset~)
          }
          Distinct =>
            match @decode.view(body) {
              BoolValue(true) => DistinctRows
              ArrayValue(_) => {
                let keys = row_keys(b, body, visible, unique=true)
                if keys.is_empty() {
                  fail(body, EmptyBody)
                }
                let fields : Array[(@schema.FieldName, @contract.Contract)] = []
                for key in keys {
                  projection.push({ output: key.field, input: key.field, })
                  fields.push(
                    (
                      key.field,
                      visible.get(@schema.reference_name(key.field)).unwrap().0,
                    ),
                  )
                }
                output = schema_type(b, body, fields)
                DistinctKeys(keys)
              }
              _ => fail(body, InvalidBody)
            }
          DedupeRows => {
            let obj = decoded(
              @decode.closed_object(body, ["by", "order_by"]),
              body,
            )
            let by = row_keys(
              b,
              decoded(@decode.required(obj, "by"), body),
              visible,
              unique=false,
            )
            let order_source = decoded(@decode.required(obj, "order_by"), body)
            let order = row_order(b, order_source, visible)
            if order.is_empty() {
              fail(order_source, EmptyBody)
            }
            pending.push({ kind: FailOnTopTie, source: order_source, })
            RowOperation::DedupeRows(by~, order~)
          }
          _ => fail(body, InvalidBody)
        },
      )
      Form::RowOperation
    }
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
    row_operation,
    reshape,
    group,
    pivot,
    analytic,
    pending,
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
