///|
pub(all) enum IntervalSearchIssue {
  InvalidLimits
  WorkLimit
  InvalidOperation
  ForeignOperand(Int)
  MissingOperandBound
  Overflow
} derive(Eq, Debug)

///|
/// A conditional pair-visit bound for a single-visit realization. Retains the
/// original row proofs, not a fabricated rows witness for the numeric product.
struct IntervalSearchProduct {
  pipeline : @pipeline.CheckedPipeline
  step : Int
  left : @pipeline.Target
  right : @pipeline.Target
  left_bound : TargetRows?
  right_bound : TargetRows?
  upper : Int64
}

///|
/// Does not establish application-closure membership, fulfilled producer
/// obligations or backend single-visit conformance. These remain separate.
/// Charges one step and both ordered input occurrences, including absent bounds.
pub fn check_interval_search_product(
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  left_bound : TargetRows?,
  right_bound : TargetRows?,
  max_work : Int,
) -> Result[IntervalSearchProduct, IntervalSearchIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if max_work < 3 {
    return Err(WorkLimit)
  }
  guard @pipeline.step_at(pipeline, step) is Some(operation) &&
    operation.operation is @pipeline.IntervalJoin(right~, ..) &&
    operation.input is Some(left) &&
    @pipeline.input_occurrence_count(operation) == 2 else {
    return Err(InvalidOperation)
  }
  let l = @pipeline.input_occurrence_at(operation, 0).unwrap()
  let r = @pipeline.input_occurrence_at(operation, 1).unwrap()
  if l.target != left ||
    l.role != @pipeline.Left ||
    r.target != right ||
    r.role != @pipeline.Right {
    return Err(InvalidOperation)
  }
  // Validate even an otherwise unused bound before the zero-product shortcut.
  if left_bound is Some(bound) &&
    (!physical_equal(bound.pipeline, pipeline) || bound.target != left) {
    return Err(ForeignOperand(0))
  }
  if right_bound is Some(bound) &&
    (!physical_equal(bound.pipeline, pipeline) || bound.target != right) {
    return Err(ForeignOperand(1))
  }
  let l = left_bound.map(target_rows_value)
  let r = right_bound.map(target_rows_value)
  let upper = if l == Some(0L) || r == Some(0L) {
    0L
  } else {
    guard l is Some(l) && r is Some(r) else { return Err(MissingOperandBound) }
    // TargetRows already enforces nonnegative safe-integer row witnesses.
    match
      @numeric.multiply(@numeric.read(l).unwrap(), @numeric.read(r).unwrap()) {
      Ok(n) => @numeric.value(n)
      Err(_) => return Err(Overflow)
    }
  }
  Ok({ pipeline, step, left, right, left_bound, right_bound, upper, })
}

///|
pub fn interval_search_pipeline(
  v : IntervalSearchProduct,
) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn interval_search_step(v : IntervalSearchProduct) -> Int {
  v.step
}

///|
pub fn interval_search_upper(v : IntervalSearchProduct) -> Int64 {
  v.upper
}

///|
/// Index 0 is left and 1 is right, including repeated producer occurrences.
pub fn interval_search_input_at(
  v : IntervalSearchProduct,
  index : Int,
) -> @pipeline.Target? {
  match index {
    0 => Some(v.left)
    1 => Some(v.right)
    _ => None
  }
}

///|
pub fn interval_search_bound_at(
  v : IntervalSearchProduct,
  index : Int,
) -> TargetRows? {
  match index {
    0 => v.left_bound
    1 => v.right_bound
    _ => None
  }
}

///|
pub fn interval_search_work(_v : IntervalSearchProduct) -> Int {
  3
}
