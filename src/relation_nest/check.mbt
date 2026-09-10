///|
fn index_schema(
  b : Budget,
  s : @decode.Cursor,
  schema : @schema.Schema,
) -> Map[String, @schema.Field] raise Stop {
  let fields : Map[String, @schema.Field] = Map([])
  let count = @schema.field_count(schema)
  spend(b, s, n=count)
  for i in 0..<count {
    let f = @schema.field_at(schema, i).unwrap()
    let name = @schema.reference_name(f.name)
    charge(b, s, name)
    contract_preflight(b, s, f.contract, depth=1)
    fields[name] = f
  }
  fields
}

///|
fn reference(
  b : Budget,
  s : @decode.Cursor,
  side : @schema.Side,
  fields : Map[String, @schema.Field],
) -> @schema.Field raise Stop {
  spend(b, s)
  let name = decoded(@decode.text(s), s)
  charge(b, s, name)
  match fields.get(name) {
    Some(f) => f
    None => fail(s, UnknownField(side, name))
  }
}

///|
fn constructible(
  b : Budget,
  s : @decode.Cursor,
  root : @contract.Contract,
  name : String,
) -> Unit raise Stop {
  let work = [root]
  while work.pop() is Some(c) {
    spend(b, s)
    match c.shape {
      @contract.Json | @contract.ResourceRef(..) | @contract.ArtifactRef(..) =>
        fail(s, NotConstructible(name))
      @contract.Array(item, ..) => work.push(item)
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        spend(b, s, n=count)
        for i in 0..<count {
          work.push(@contract.field_at(fields, i).unwrap().contract)
        }
      }
      _ => ()
    }
  }
}

///|
fn check_impl(
  body : @decode.Cursor,
  parent : @schema.Schema,
  child : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> CheckedNest raise Stop {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    fail(body, InvalidLimits)
  }
  let b : Budget = {
    limits,
    work: limits.max_work,
    text: limits.max_text_bytes,
    nodes: limits.max_nodes,
  }
  let parents = index_schema(b, body, parent)
  let children = index_schema(b, body, child)
  let params : Map[String, @contract.Contract] = Map([])
  if parameters is Some(declarations) {
    let count = @parameter.declaration_count(declarations)
    spend(b, body, n=count)
    for i in 0..<count {
      let p = @parameter.declaration_at(declarations, i).unwrap()
      charge(b, body, p.name)
      contract_preflight(b, body, p.parameter_type.contract)
      params[p.name] = p.parameter_type.contract
    }
  }
  source_preflight(b, body)
  let obj = decoded(
    @decode.closed_object(body, [
      "with", "on", "into", "fields", "order_by", "max_items",
    ]),
    body,
  )
  let with_name = dataflow_name(decoded(@decode.required(obj, "with"), body))
  let on = decoded(@decode.required(obj, "on"), body)
  let pairs = decoded(@decode.elements(on), on)
  if pairs.is_empty() {
    fail(on, EmptyBody)
  }
  spend(b, on, n=pairs.length())
  let keys : Array[KeyPair] = []
  for pair in pairs {
    let p = decoded(@decode.closed_object(pair, ["left", "right"]), pair)
    let left = reference(
      b,
      decoded(@decode.required(p, "left"), pair),
      Left,
      parents,
    )
    let right = reference(
      b,
      decoded(@decode.required(p, "right"), pair),
      Right,
      children,
    )
    if !@contract.key_comparable(left.contract, right.contract) {
      fail(
        pair,
        IncomparableKeys(
          @schema.reference_name(left.name),
          @schema.reference_name(right.name),
        ),
      )
    }
    keys.push({ left: left.name, right: right.name, source: pair, })
  }
  let into_source = decoded(@decode.required(obj, "into"), body)
  let into = decoded(@decode.text(into_source), into_source)
  field_name(b, into_source, into)
  if parents.contains(into) {
    fail(into_source, InputCollision(into))
  }
  let fields_source = decoded(@decode.required(obj, "fields"), body)
  let selections = decoded(@decode.elements(fields_source), fields_source)
  if selections.is_empty() {
    fail(fields_source, EmptyBody)
  }
  spend(b, fields_source, n=selections.length())
  let projection : Array[Projection] = []
  let payload : Array[(String, @contract.Contract)] = []
  let seen : Map[String, Bool] = Map([])
  for s in selections {
    let (name, input_source) = match @decode.view(s) {
      TextValue(name) => (name, s)
      ObjectValue(o) => {
        let names = decoded(@decode.object_field_names(s), s)
        if names.length() != 1 {
          fail(s, InvalidBody)
        }
        (names[0], @decode.lookup(o, names[0]).unwrap())
      }
      _ => fail(s, InvalidBody)
    }
    field_name(b, s, name)
    if seen.contains(name) {
      fail(s, DuplicateOutput(name))
    }
    seen[name] = true
    let input = reference(b, input_source, Right, children)
    constructible(
      b,
      input_source,
      input.contract,
      @schema.reference_name(input.name),
    )
    payload.push((name, input.contract))
    projection.push({ output: name, input: input.name, source: s, })
  }
  let order = match @decode.lookup(obj, "order_by") {
    None => None
    Some(s) => {
      let items = decoded(@decode.elements(s), s)
      if items.is_empty() {
        fail(s, EmptyBody)
      }
      spend(b, s, n=items.length())
      let terms : Array[OrderTerm] = []
      for item in items {
        let key = match @order.read(item) {
          Ok(k) => k
          Err(e) => {
            if e.diagnostic is Some(d) {
              raise Stop({
                kind: InvalidOrder,
                source: e.source,
                path: d.path.copy(),
                span: d.span,
              })
            }
            fail(e.source, InvalidOrder)
          }
        }
        spend(b, item, n=key.work)
        charge(b, key.field_source, key.field)
        let f = match children.get(key.field) {
          Some(v) => v
          None => fail(key.field_source, UnknownField(Right, key.field))
        }
        if !@order.author_orderable(f.contract) {
          fail(key.field_source, NotAuthorOrderable(key.field))
        }
        terms.push({
          field: f.name,
          direction: key.direction,
          nulls: key.nulls,
          explicit_nulls: key.explicit_nulls,
          source: item,
        })
      }
      Some(terms)
    }
  }
  let pending : Array[Obligation] = [
    ResolveTotalOrder,
    ResolveItemLimit,
    ResolveNestedEnvelope,
    ValidateOutputsBeforeConsumers,
    PropagatePolicyAndCompleteness,
  ]
  let item_limit = match @decode.lookup(obj, "max_items") {
    None => None
    Some(s) =>
      match @decode.view(s) {
        NumberValue(n) => {
          let count = match @scalar.read_safe_integer(n) {
            Some(v) => v
            None => fail(s, InvalidGuard)
          }
          if count < 1L {
            fail(s, InvalidGuard)
          }
          Some(Literal(count))
        }
        _ => {
          let p = decoded(@decode.closed_object(s, ["$param"]), s)
          let ps = decoded(@decode.required(p, "$param"), s)
          let name = decoded(@decode.text(ps), ps)
          let c = match params.get(name) {
            Some(c) => c
            None => fail(ps, UnknownParameter(name))
          }
          if !(c.shape is @contract.Number) {
            fail(ps, InvalidGuard)
          }
          pending.push(BindGuard(name))
          Some(Parameter(name))
        }
      }
  }
  let bytes = b.text
  spend(b, fields_source, n=payload.length())
  for (name, _) in payload {
    charge(b, fields_source, name)
  }
  let object = match
    @contract.object_contract(
      payload,
      nullable=false,
      max_fields=payload.length(),
      max_name_bytes=bytes,
    ) {
    Ok(v) => v
    Err(_) => fail(fields_source, BudgetExceeded)
  }
  // A item_limit still needs binding/capacity validation; it is not an established
  // array bound in this static result contract.
  let array = @contract.array_contract(object, nullable=false, max_items=None).unwrap()
  let fields : Array[(@schema.FieldName, @contract.Contract)] = []
  spend(b, body, n=@schema.field_count(parent))
  for i in 0..<@schema.field_count(parent) {
    let f = @schema.field_at(parent, i).unwrap()
    fields.push((f.name, f.contract))
  }
  fields.push((@schema.Unqualified(into), array))
  let bytes = b.text
  for (name, _) in fields {
    charge(b, body, @schema.reference_name(name))
  }
  let output = match
    @schema.from_fields(
      fields,
      max_fields=fields.length(),
      max_name_bytes=bytes,
    ) {
    Ok(v) => v
    Err(_) => fail(body, BudgetExceeded)
  }
  ignore(index_schema(b, body, output))
  {
    source: body,
    parent,
    child,
    output,
    with_name,
    into,
    keys,
    projection,
    order,
    item_limit,
    pending,
    usage: {
      work: limits.max_work - b.work,
      text_bytes: limits.max_text_bytes - b.text,
      nodes: limits.max_nodes - b.nodes,
    },
  }
}

///|
/// The caller resolves `with`. Success retains obligations, not executable proof.
pub fn check(
  body : @decode.Cursor,
  parent : @schema.Schema,
  child : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedNest, Issue] {
  Ok(check_impl(body, parent, child, parameters, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
