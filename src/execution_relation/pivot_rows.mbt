///|
fn pivot_fill_value(pivot : @lower.PreparedPivot) -> Value {
  match @lower.pivot_fill(pivot) {
    None | Some(@lower.Null) => Null
    Some(@lower.Value(value)) => capture(value.value)
  }
}

///|
fn pivot_requires_numeric_observation(pivot : @lower.PreparedPivot) -> Bool {
  @lower.pivot_axis_count(pivot) > 0 &&
  (
    @lower.pivot_function(pivot) is @relation.Sum ||
    @lower.pivot_function(pivot) is @relation.Avg
  ) &&
  @lower.pivot_result_contract(pivot).shape is @contract.Number
}

///|
pub fn pivot_execution_supported(pivot : @lower.PreparedPivot) -> Bool {
  pivot_execution_supported_with_profile(pivot, false)
}

///|
pub fn pivot_execution_supported_with_numeric(
  pivot : @lower.PreparedPivot,
) -> Bool {
  pivot_execution_supported_with_profile(pivot, true)
}

///|
fn pivot_execution_supported_with_profile(
  pivot : @lower.PreparedPivot,
  numeric : Bool,
) -> Bool {
  match @lower.pivot_function(pivot) {
    @relation.Count | @relation.Min | @relation.Max | @relation.First => true
    @relation.Sum =>
      @lower.pivot_result_contract(pivot).shape
      is @contract.Decimal(precision=38, ..) ||
      (
        (numeric || @lower.pivot_axis_count(pivot) == 0) &&
        @lower.pivot_result_contract(pivot).shape is @contract.Number
      )
    @relation.Avg =>
      (numeric || @lower.pivot_axis_count(pivot) == 0) &&
      @lower.pivot_result_contract(pivot).shape is @contract.Number
    _ => false
  }
}

///|
/// Deterministic pivot lane. Binary64 sum/avg use the attempt-owned selected
/// numeric executor. Exact Decimal sum retains its checked precision-38 path.
/// Drains the resumable `PivotEvaluation` with the same charges.
fn[T : RelationRows] evaluate_pivot_rows(
  kernel : @lower.PreparedKernel,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  numeric? : NumericAggregateExecution? = None,
  step? : Int = -1,
) -> Result[Table, RowIssue] {
  let result : Array[Array[Value]] = []
  let state = match
    start_pivot_evaluation(
      kernel,
      input,
      max_rows,
      control,
      output,
      workspace,
      numeric,
      step,
      (row, _) => {
        result.push(row)
        Ok(())
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let names = while true {
    match advance_pivot_evaluation(state) {
      Ok(None) => ()
      Ok(Some(names)) => break names
      Err(issue) => return Err(issue)
    }
  } nobreak {
    return Err(InvalidRows)
  }
  Ok({
    owner: RelationRows::checked_owner(input),
    id: output_id,
    names,
    rows: result,
  })
}
