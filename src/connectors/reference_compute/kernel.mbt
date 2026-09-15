///|
/// Pure bounded kernel output: row positions and projection positions only.
/// This cannot bind a consumer or claim guard/evidence completion. The caller
/// must hold common execution admission and validate the resulting output.
pub fn select_numeric_rows(
  plan : NumericPlan,
  input : @execution.ProducerRead,
  max_work : Int,
) -> Result[(Array[Int], Array[Int]), PlanIssue] {
  select_numeric_rows_with_work(plan, input, Ref(max_work), None)
}

///|
fn select_numeric_rows_with_work(
  plan : NumericPlan,
  input : @execution.ProducerRead,
  work : Ref[Int],
  roots : ((Int, @execution.Value, @execution.Value, @execution.Value) -> Result[
    Unit,
    PlanIssue,
  ])?,
) -> Result[(Array[Int], Array[Int]), PlanIssue] {
  if work.val < 0 {
    return Err(Limit)
  }
  if !@execution.producer_read_available(input) ||
    !physical_equal(plan.owner, @execution.producer_read_receiver(input)) ||
    @execution.producer_read_input_index(input) != 0 {
    return Err(Unsupported)
  }
  let schema = @execution.producer_read_schema(input)
  let mut predicate_column = None
  let projection = []
  for column in 0..<@schema.field_count(schema) {
    if work.val == 0 {
      return Err(Limit)
    }
    work.val -= 1
    if @schema.reference_name(@schema.field_at(schema, column).unwrap().name) ==
      plan.predicate_field {
      predicate_column = Some(column)
    }
  }
  guard predicate_column is Some(predicate_column) else {
    return Err(Unsupported)
  }
  for field in plan.fields {
    let mut found = None
    for column in 0..<@schema.field_count(schema) {
      if work.val == 0 {
        return Err(Limit)
      }
      work.val -= 1
      if @schema.field_at(schema, column).unwrap().name == field.input {
        found = Some(column)
        break
      }
    }
    guard found is Some(column) else { return Err(Unsupported) }
    projection.push(column)
  }
  let selected = []
  for row in 0..<@execution.producer_read_row_count(input) {
    if work.val == 0 {
      return Err(Limit)
    }
    work.val -= 1
    let value : @execution.Value = match
      @execution.producer_read_cell(input, row, predicate_column) {
      Some(Number(value)) | Some(Captured(@admitted.Number(value))) =>
        Number(value)
      Some(Null) | Some(Captured(@admitted.Null)) => Null
      _ => return Err(Unsupported)
    }
    let result : @execution.Value = match value {
      Number(value) => Boolean(value > plan.threshold)
      _ => Null
    }
    if roots is Some(check) {
      match check(row, value, @execution.Number(plan.threshold), result) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    let keep = result is @execution.Boolean(true)
    if keep {
      selected.push(row)
    }
  }
  Ok((selected, projection))
}
