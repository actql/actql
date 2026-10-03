///|
pub(all) enum Operation {
  Events
  Vectors
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  WrongCarrier(@carrier.Kind)
  IncompleteGraph
  UnsupportedGraphOperation
  OutputCollision(@row.FieldName)
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
  max_text_bytes : Int
  max_depth : Int
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
struct CheckedProjection {
  operation : Operation
  source : @decode.Cursor
  input : @carrier.Carrier
  output : @carrier.Carrier
  usage : Usage
}

///|
fn issue(source : @decode.Cursor, kind : IssueKind) -> Issue {
  {
    kind,
    path: @decode.cursor_path(source),
    span: @decode.cursor_span(source),
  }
}

///|
/// Explicit Carrier-to-Relation projection. Preserve only admitted semantic
/// field knowledge; do not synthesize physical backend columns or proofs.
/// Limits cover this source and field inspection, not already-owned children.
pub fn check(
  operation : Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedProjection, Issue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(issue(source, InvalidLimits))
  }
  if limits.max_work == 0 || limits.max_nodes == 0 {
    return Err(issue(source, BudgetExceeded))
  }
  if @decode.boolean(source) != Ok(true) {
    return Err(issue(source, InvalidBody))
  }
  let expected = match operation {
    Events => @carrier.EventsKind
    Vectors => @carrier.VectorsKind
  }
  if @carrier.kind(input) != expected {
    return Err(issue(source, WrongCarrier(@carrier.kind(input))))
  }
  let records = match input {
    @carrier.EventValue(e) => e.records
    @carrier.VectorValue(v) => @carrier.vector_records(v)
    @carrier.Opaque(_) => @carrier.unknown_rows()
    _ => return Err(issue(source, WrongCarrier(@carrier.kind(input))))
  }
  let count = @carrier.field_count(records)
  if count > limits.max_work - 1 {
    return Err(issue(source, BudgetExceeded))
  }
  let mut text = limits.max_text_bytes
  for i in 0..<count {
    let name = @row.reference_name(@carrier.field_at(records, i).unwrap().name)
    match @scalar.admit_utf8_length(name, text) {
      Ok(size) => text -= size
      Err(_) => return Err(issue(source, BudgetExceeded))
    }
  }
  Ok({
    operation,
    source,
    input,
    output: @carrier.relation(records),
    usage: {
      work: count + 1,
      nodes: 1,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
pub fn operation(value : CheckedProjection) -> Operation {
  value.operation
}

///|
pub fn source(value : CheckedProjection) -> @decode.Cursor {
  value.source
}

///|
pub fn input(value : CheckedProjection) -> @carrier.Carrier {
  value.input
}

///|
pub fn output(value : CheckedProjection) -> @carrier.Carrier {
  value.output
}

///|
pub fn usage(value : CheckedProjection) -> Usage {
  value.usage
}
