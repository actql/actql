///|
struct CheckedCrossJoin {
  source : @decode.Cursor
  left : @schema.Schema
  right : @schema.Schema
  output : @schema.Schema
  projection : Array[Projection]?
  singleton_right : Bool
  output_guard : Guard?
  pending : Array[Obligation]
  usage : Usage
}

///|
/// Cross join has no equality keys, null-key mode or implicit singleton selection.
pub fn check_cross(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedCrossJoin, Issue] {
  try {
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
        "with", "select", "right_rows", "max_output_rows",
      ]),
      body,
    )
    ignore(dataflow_name(decoded(@decode.required(obj, "with"), body)))
    let singleton_right = match @decode.lookup(obj, "right_rows") {
      None => false
      Some(s) => {
        if decoded(@decode.text(s), s) != "one" {
          fail(s, InvalidBody)
        }
        true
      }
    }
    let pending : Array[Obligation] = [
      ResolveProductBound,
      ResolveOutputLimit,
      PreserveLeftMajorProductOrder,
      StableIdentity(@schema.Left),
      StableIdentity(@schema.Right),
    ]
    if singleton_right {
      pending.push(ValidateExactlyOneRightRow)
    }
    let output_guard = read_guard(
      @decode.lookup(obj, "max_output_rows"),
      params,
      pending,
    )
    let (output, projection) = join_output(
      b,
      body,
      @decode.lookup(obj, "select"),
      left,
      right,
      Inner,
    )
    Ok({
      source: body,
      left,
      right,
      output,
      projection,
      singleton_right,
      output_guard,
      pending,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
        nodes: limits.max_nodes - b.nodes,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn cross_source(value : CheckedCrossJoin) -> @decode.Cursor {
  value.source
}

///|
pub fn cross_input_schema(
  value : CheckedCrossJoin,
  side : @schema.Side,
) -> @schema.Schema {
  if side == Left {
    value.left
  } else {
    value.right
  }
}

///|
pub fn cross_output_schema(value : CheckedCrossJoin) -> @schema.Schema {
  value.output
}

///|
pub fn cross_projection(value : CheckedCrossJoin) -> Array[Projection]? {
  value.projection.map(p => p.copy())
}

///|
pub fn cross_requires_one_right_row(value : CheckedCrossJoin) -> Bool {
  value.singleton_right
}

///|
pub fn cross_output_guard(value : CheckedCrossJoin) -> Guard? {
  value.output_guard
}

///|
pub fn cross_pending_validations(value : CheckedCrossJoin) -> Array[Obligation] {
  value.pending.copy()
}

///|
pub fn cross_usage(value : CheckedCrossJoin) -> Usage {
  value.usage
}
