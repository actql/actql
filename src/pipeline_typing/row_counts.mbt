///|
/// Conditional successful-output count, not a Host ceiling or execution permit.
pub struct RowCount {
  upper : Int64
  exact : Bool
} derive(Eq, Debug)

///|
fn count(n : Int64, exact : Bool) -> RowCount {
  { upper: n, exact: exact || n == 0L, }
}

///|
fn reduce_count(input : RowCount?) -> RowCount? {
  input.map(v => count(v.upper, false))
}

///|
fn count_at(target : Target, steps : Array[RowCount?]) -> RowCount? {
  match target {
    Input(_) => None
    Step(i) => steps[i]
  }
}

///|
fn sum_counts(
  source : @decode.Cursor,
  a : RowCount?,
  z : RowCount?,
) -> RowCount? raise Stop {
  guard a is Some(a) && z is Some(z) else { return None }
  if a.upper > 9007199254740991L - z.upper {
    fail(source, RowBoundOverflow)
  }
  Some(count(a.upper + z.upper, a.exact && z.exact))
}

///|
fn product_counts(
  source : @decode.Cursor,
  a : RowCount?,
  z : RowCount?,
) -> RowCount? raise Stop {
  if a is Some({ upper: 0L, .. }) || z is Some({ upper: 0L, .. }) {
    return Some(count(0L, true))
  }
  guard a is Some(a) && z is Some(z) else { return None }
  if a.upper > 9007199254740991L / z.upper {
    fail(source, RowBoundOverflow)
  }
  Some(count(a.upper * z.upper, a.exact && z.exact))
}

///|
fn slice_count(input : RowCount?, limit : Int64?, offset : Int64?) -> RowCount? {
  let remaining = input.map(v => {
    match offset {
      Some(n) => count(if v.upper > n { v.upper - n } else { 0L }, v.exact)
      None => count(v.upper, false)
    }
  })
  match (remaining, limit) {
    (Some(v), Some(n)) =>
      Some(count(if v.upper < n { v.upper } else { n }, v.exact))
    (Some(v), None) => Some(count(v.upper, false))
    (None, Some(n)) => Some(count(n, false))
    (None, None) => None
  }
}

///|
fn unary_count(
  source : @decode.Cursor,
  input : RowCount?,
  op : @relation.CheckedOperation,
) -> RowCount? raise Stop {
  match @relation.row_count_rule(op) {
    Unknown => None
    Preserve => input
    Reduce => reduce_count(input)
    OneRow => Some(count(1L, true))
    OneExistingRow =>
      match input {
        Some(v) => Some(count(if v.upper == 0L { 0L } else { 1L }, v.exact))
        None => Some(count(1L, false))
      }
    Slice(limit~, offset~) => slice_count(input, limit, offset)
    Repeat(n) => product_counts(source, input, Some(count(n, true)))
    Expand(n) =>
      product_counts(source, reduce_count(input), n.map(v => count(v, false)))
  }
}

///|
fn window_count(
  source : @decode.Cursor,
  input : RowCount?,
  options : @window.Options,
) -> RowCount? raise Stop {
  if @window.kind(options) == Fixed {
    return input
  }
  let factor = match (@window.size(options), @window.step(options)) {
    (Literal(size), Some(Literal(step))) =>
      Some(
        count(
          size / step + (if size % step == 0L { 0L } else { 1L }),
          size % step == 0L,
        ),
      )
    _ => None
  }
  product_counts(source, input, factor)
}

///|
// Single forward pass over already checked, ordered operand occurrences.
fn derive_row_counts(
  b : Budget,
  steps : Array[CheckedStep],
) -> Array[RowCount?] raise Stop {
  let result : Array[RowCount?] = []
  for step in steps {
    spend(b, step.source, 1)
    let input = step.input.bind(t => count_at(t, result))
    let next = match step.operation {
      Values(v) => Some(count(@values.row_count(v).to_int64(), true))
      TimeSeries(v) => @series.known_row_count(v).map(n => count(n, true))
      Calendar(v) =>
        match @calendar.cardinality(v) {
          PreserveInput => input
          AtMost(n) => Some(count(n.to_int64(), false))
        }
      Unary(op) | WindowGroup(op) => unary_count(step.source, input, op)
      Vector(_) => input
      Projection(v) =>
        match @projection.operation(v) {
          Events | Vectors => input
          NodeRows | EdgeRows => None
        }
      Event(v) =>
        match @event.options(v) {
          ToEvents | Session(_) | Watermark(_, Mark) => input
          Dedupe(_) | Watermark(_, Drop) => reduce_count(input)
        }
      Window(v) => window_count(step.source, input, @window.options(v))
      Nest(_) => input
      Append(right~, ..) =>
        sum_counts(step.source, input, count_at(right, result))
      CrossJoin(right~, checked~) =>
        if @join.cross_requires_one_right_row(checked) {
          input
        } else {
          product_counts(step.source, input, count_at(right, result))
        }
      Set(right~, checked~) => {
        let left = reduce_count(input)
        if @set.operation(checked) == Except {
          left
        } else {
          let right = reduce_count(count_at(right, result))
          match (left, right) {
            (Some(a), Some(z)) =>
              Some(
                count(if a.upper < z.upper { a.upper } else { z.upper }, false),
              )
            (Some(a), None) | (None, Some(a)) => Some(a)
            _ => None
          }
        }
      }
      AsOfJoin(checked~, ..) =>
        if @join.asof_kind(checked) == Left {
          input
        } else {
          reduce_count(input)
        }
      _ => None
    }
    result.push(next)
  }
  result
}

///|
/// Scope is this pipeline and target; retain its operations and obligations.
/// Unknown input counts and unimplemented transfer rules return None, not zero.
pub fn row_count(value : CheckedPipeline, target : Target) -> RowCount? {
  match target {
    Input(_) => None
    Step(i) => value.row_counts.get(i).bind(v => v)
  }
}
