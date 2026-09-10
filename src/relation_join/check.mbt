///|
fn check_impl(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> CheckedJoin raise Stop {
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
  source_preflight(b, body)
  for (side, schema) in [(@schema.Left, left), (@schema.Right, right)] {
    let row = match @schema.as_object(schema) {
      Some(c) => c
      None => fail(body, QualifiedInput(side))
    }
    contract_preflight(b, body, row)
  }
  let params : Map[String, @contract.ParameterType] = Map([])
  if parameters is Some(p) {
    let n = @parameter.declaration_count(p)
    spend(b, body, n~)
    for i in 0..<n {
      let d = @parameter.declaration_at(p, i).unwrap()
      charge(b, body, d.name)
      contract_preflight(b, body, d.parameter_type.contract)
      params[d.name] = d.parameter_type
    }
  }
  let obj = decoded(
    @decode.closed_object(body, [
      "with", "left", "kind", "on", "cardinality", "null_key", "select", "max_output_rows",
    ]),
    body,
  )
  ignore(dataflow_name(decoded(@decode.required(obj, "with"), body)))
  if @decode.lookup(obj, "left") is Some(s) {
    ignore(dataflow_name(s))
  }
  let kind_source = decoded(@decode.required(obj, "kind"), body)
  let kind = match decoded(@decode.text(kind_source), kind_source) {
    "inner" => Inner
    "left" => Left
    "full" => Full
    "semi" => Semi
    "anti" => Anti
    _ => fail(kind_source, InvalidBody)
  }
  let null_key = match @decode.lookup(obj, "null_key") {
    None => NoMatch
    Some(s) =>
      match decoded(@decode.text(s), s) {
        "no_match" => NoMatch
        "fail" => Fail
        _ => fail(s, InvalidBody)
      }
  }
  let assertion = match @decode.lookup(obj, "cardinality") {
    None => None
    Some(s) =>
      Some(
        match decoded(@decode.text(s), s) {
          "one_to_one" => OneToOne
          "many_to_one" => ManyToOne
          "one_to_many" => OneToMany
          _ => fail(s, InvalidBody)
        },
      )
  }
  let on = decoded(@decode.required(obj, "on"), body)
  let pairs = match @decode.view(on) {
    ArrayValue(v) => v
    _ => [on]
  }
  if pairs.is_empty() {
    fail(on, EmptyBody)
  }
  spend(b, on, n=pairs.length())
  let keys : Array[KeyPair] = []
  for pair in pairs {
    let (ln, rn, ls, rs) = match @decode.view(pair) {
      TextValue(s) => (s, s, pair, pair)
      _ => {
        let obj = decoded(@decode.closed_object(pair, ["left", "right"]), pair)
        let ls = decoded(@decode.required(obj, "left"), pair)
        let rs = decoded(@decode.required(obj, "right"), pair)
        (decoded(@decode.text(ls), ls), decoded(@decode.text(rs), rs), ls, rs)
      }
    }
    field_name(b, ls, ln)
    field_name(b, rs, rn)
    let lc = match @schema.lookup(left, Unqualified(ln)) {
      Some(c) => c
      None => fail(ls, UnknownField(@schema.Left, ln))
    }
    let rc = match @schema.lookup(right, Unqualified(rn)) {
      Some(c) => c
      None => fail(rs, UnknownField(@schema.Right, rn))
    }
    if !@contract.key_comparable(lc, rc) {
      fail(pair, IncomparableKeys(ln, rn))
    }
    keys.push({ left: Unqualified(ln), right: Unqualified(rn), source: pair, })
  }
  let pending : Array[Obligation] = [
    ResolveCardinality,
    ResolveOutputLimit,
    PreserveRowOrder,
  ]
  if kind == Full {
    pending.push(StableIdentity(@schema.Left))
    pending.push(StableIdentity(@schema.Right))
  }
  if assertion is Some(a) {
    pending.push(ValidateCardinality(a))
  }
  if null_key == Fail {
    pending.push(RejectNullKeys)
  }
  let output_guard = match @decode.lookup(obj, "max_output_rows") {
    None => None
    Some(s) =>
      Some(
        match @decode.view(s) {
          NumberValue(n) => {
            let v = match @scalar.read_safe_integer(n) {
              Some(v) => v
              None => fail(s, InvalidGuard)
            }
            if v <= 0L {
              fail(s, InvalidGuard)
            }
            Literal(v)
          }
          ObjectValue(_) => {
            let o = decoded(@decode.closed_object(s, ["$param"]), s)
            let slot = decoded(@decode.required(o, "$param"), s)
            let name = decoded(@decode.text(slot), slot)
            let p = match params.get(name) {
              Some(p) => p
              None => fail(slot, UnknownParameter(name))
            }
            if !(p.contract.shape is @contract.Number) {
              fail(slot, InvalidGuard)
            }
            pending.push(BindGuard(name))
            Parameter(name)
          }
          _ => fail(s, InvalidGuard)
        },
      )
  }
  let raw : Array[(@schema.FieldName, @contract.Contract)] = []
  for (side, schema) in [(@schema.Left, left), (@schema.Right, right)] {
    if side == @schema.Right && (kind == Semi || kind == Anti) {
      continue
    }
    let n = @schema.field_count(schema)
    spend(b, body, n~)
    for i in 0..<n {
      let f = @schema.field_at(schema, i).unwrap()
      let name = match f.name {
        Unqualified(s) => s
        _ => fail(body, QualifiedInput(side))
      }
      let c = if kind == Full || (kind == Left && side == @schema.Right) {
        @contract.with_nullability(f.contract, true)
      } else {
        f.contract
      }
      raw.push((Qualified(side, name), c))
    }
  }
  let raw = make_schema(b, body, raw)
  let (output, projection) = match @decode.lookup(obj, "select") {
    None => (raw, None)
    Some(s) => {
      let o = decoded(@decode.open_object(s), s)
      let names = @decode.object_field_names(s).unwrap()
      if names.is_empty() {
        fail(s, EmptyBody)
      }
      spend(b, s, n=names.length())
      names.sort_by(@canonical.compare_utf16)
      let fields = []
      let projection : Array[Projection] = []
      for name in names {
        let slot = @decode.lookup(o, name).unwrap()
        field_name(b, slot, name)
        let reference = decoded(@decode.text(slot), slot)
        spend(b, slot)
        let input = match @schema.lookup_reference(raw, reference) {
          Some(f) => f
          None => fail(slot, InvalidProjection(reference))
        }
        fields.push((@schema.Unqualified(name), input.contract))
        projection.push({
          output: Unqualified(name),
          input: input.name,
          source: slot,
        })
      }
      (make_schema(b, s, fields), Some(projection))
    }
  }
  {
    source: body,
    left,
    right,
    output,
    kind,
    null_key,
    keys,
    projection,
    assertion,
    output_guard,
    pending,
    usage: {
      work: limits.max_work - b.work,
      text_bytes: limits.max_text_bytes - b.text,
      nodes: limits.max_nodes - b.nodes,
    },
  }
}

///|
fn make_schema(
  b : Budget,
  source : @decode.Cursor,
  fields : Array[(@schema.FieldName, @contract.Contract)],
) -> @schema.Schema raise Stop {
  let bytes = b.text
  spend(b, source, n=fields.length())
  for (name, _) in fields {
    charge(b, source, @schema.reference_name(name))
  }
  match
    @schema.from_fields(
      fields,
      max_fields=fields.length(),
      max_name_bytes=bytes,
    ) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
}

///|
/// Checks a local join body against already resolved complete schemas.
/// Does not resolve names, prove keys/identity/order, compute limits or execute.
pub fn check(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedJoin, Issue] {
  Ok(check_impl(body, left, right, parameters, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
