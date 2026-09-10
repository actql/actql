///|
pub enum Endpoint {
  Literal(String)
  Parameter(String)
}

///|
pub(all) enum Obligation {
  BindTimestamp(String)
  BindStep(String)
  ValidateRange
  CheckedArithmetic
  ResolveRowBound
  ResolveResources
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  Decode(@decode.IssueKind)
  InvalidTimestamp
  UnknownParameter(String)
  IncompatibleParameter(String)
  ReversedRange
  Temporal(@temporal.IssueKind)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) struct Limits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
}

///|
struct CheckedSeries {
  output : @carrier.Carrier
  row_count : Int64?
  source : @decode.Cursor
  start : Endpoint
  end : Endpoint
  step : @temporal.Milliseconds
  usage : Usage
}

///|
fn endpoint(
  b : Budget,
  c : @decode.Cursor,
  params : Map[String, @contract.ParameterType],
) -> Endpoint raise Stop {
  spend(b, c, 1)
  if @decode.view(c) is TextValue(text) {
    let checked = @value.admit(
      @contract.primitive(TimestampType, nullable=false),
      c,
      { max_nodes: 1, max_depth: 0, max_text_bytes: 24, },
    )
    if checked is Err(_) {
      fail(c, InvalidTimestamp)
    }
    return Literal(text)
  }
  let object = decoded(@decode.closed_object(c, ["$param"]))
  let name = decoded(@decode.text(decoded(@decode.required(object, "$param"))))
  let ty = match params.get(name) {
    Some(t) => t
    None => fail(c, UnknownParameter(name))
  }
  if ty.contract.nullable || !(ty.contract.shape is @contract.Timestamp) {
    fail(c, IncompatibleParameter(name))
  }
  Parameter(name)
}

///|
pub fn check(
  source : @decode.Cursor,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedSeries, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let params : Map[String, @contract.ParameterType] = Map([])
    if parameters is Some(ds) {
      let n = @parameter.declaration_count(ds)
      spend(b, source, n)
      for i in 0..<n {
        let d = @parameter.declaration_at(ds, i).unwrap()
        charge(b, source, d.name)
        params[d.name] = d.parameter_type
      }
    }
    let object = decoded(
      @decode.closed_object(source, ["start", "end", "step"]),
    )
    let start = endpoint(b, decoded(@decode.required(object, "start")), params)
    let end_source = decoded(@decode.required(object, "end"))
    let end = endpoint(b, end_source, params)
    if start is Literal(a) &&
      end is Literal(z) &&
      @canonical.compare_utf16(a, z) > 0 {
      fail(end_source, ReversedRange)
    }
    let step = match
      @temporal.read_milliseconds(
        decoded(@decode.required(object, "step")),
        PositiveMilliseconds,
        parameters,
        {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        },
      ) {
      Ok(v) => v
      Err(e) =>
        raise Stop({
          kind: Temporal(e.kind),
          path: e.path.copy(),
          span: e.span,
        })
    }
    let u = @temporal.milliseconds_usage(step)
    b.work -= u.work
    b.nodes -= u.nodes
    b.text -= u.text_bytes
    spend(b, source, 2)
    charge(b, source, "time")
    if b.nodes < 1 {
      fail(source, BudgetExceeded)
    }
    b.nodes -= 1
    let output = output_contract()
    Ok({
      output,
      row_count: known_count(start, end, @temporal.milliseconds_value(step)),
      source,
      start,
      end,
      step: @temporal.milliseconds_value(step),
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn start(v : CheckedSeries) -> Endpoint {
  v.start
}

///|
pub fn end(v : CheckedSeries) -> Endpoint {
  v.end
}

///|
pub fn step(v : CheckedSeries) -> @temporal.Milliseconds {
  v.step
}

///|
pub fn source(v : CheckedSeries) -> @decode.Cursor {
  v.source
}

///|
pub fn usage(v : CheckedSeries) -> Usage {
  v.usage
}

///|
fn output_contract() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("time"),
          Some(@contract.primitive(TimestampType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=4,
    ).unwrap(),
  )
}

///|
pub fn output(v : CheckedSeries) -> @carrier.Carrier {
  v.output
}

///|
pub fn pending_validations(v : CheckedSeries) -> Array[Obligation] {
  let pending : Array[Obligation] = [
    ValidateRange,
    CheckedArithmetic,
    ResolveResources,
  ]
  if v.row_count is None {
    pending.push(ResolveRowBound)
  }
  for value in [v.start, v.end] {
    if value is Parameter(name) {
      pending.push(BindTimestamp(name))
    }
  }
  if v.step is @temporal.Parameter(name, ..) {
    pending.push(BindStep(name))
  }
  pending
}
