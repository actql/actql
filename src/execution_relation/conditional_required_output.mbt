///|
priv struct RequiredRowSource {
  mut index : Int
  mut row : ConditionalRow?
}

///|
/// A narrow adapter to the existing bounded dense-output preparation. It does
/// not issue completion evidence or allow a conditional field to become NULL.
struct ConditionalRequiredOutputPreparation {
  source : RequiredRowSource
  inner : AdmittedOutputPreparation
}

///|
/// The caller retains the immutable conditional rows and their source custody
/// until stop and cleanup. One row is pinned across its incremental cell reads;
/// nested values are rechecked and charged by the existing bounded owner.
pub fn start_conditional_required_output_preparation(
  output : AdmittedOutput,
  schema : @schema.ConditionalSchema,
  count : Int,
  max_step_work : Int,
  max_workspace_slots : Int,
  read : (Int) -> ConditionalRow?,
) -> Result[ConditionalRequiredOutputPreparation, CaptureIssue] {
  let required = @schema.required_projection_schema(schema)
  if @schema.field_count(required) != @schema.field_count(output.buffer.schema) ||
    (count > 0 && @schema.field_count(required) == 0) {
    return Err(InvalidCheckedRow)
  }
  let source : RequiredRowSource = { index: -1, row: None, }
  let inner = match
    start_admitted_output_preparation(
      output,
      count,
      max_step_work,
      max_workspace_slots,
      (row, column) => {
        if source.index != row {
          source.row = read(row)
          source.index = row
        }
        guard source.row is Some(current) else { return None }
        guard physical_equal(current.schema, schema) &&
          @schema.field_at(required, column) is Some(field) &&
          @schema.field_at(output.buffer.schema, column) is Some(target) &&
          field.name == target.name &&
          physical_equal(field.contract, target.contract) &&
          conditional_required_cell(current, column) is Some(checked) &&
          physical_equal(checked.contract, target.contract) else {
          return None
        }
        Some(checked.value)
      },
      validate_field=Some(column => {
        guard @schema.field_at(required, column) is Some(field) &&
          @schema.field_at(output.buffer.schema, column) is Some(target) else {
          return false
        }
        field.name == target.name &&
        physical_equal(field.contract, target.contract)
      }),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ source, inner, })
}

///|
pub fn advance_conditional_required_output_preparation(
  value : ConditionalRequiredOutputPreparation,
  quantum : Int,
) -> Result[AdmittedOutputPoll, @bounded.Issue] {
  advance_admitted_output_preparation(value.inner, quantum)
}

///|
pub fn cancel_conditional_required_output_preparation(
  value : ConditionalRequiredOutputPreparation,
) -> Bool {
  cancel_admitted_output_preparation(value.inner)
}

///|
pub fn conditional_required_output_rows(
  value : ConditionalRequiredOutputPreparation,
) -> AdmittedOutputRows? {
  admitted_output_preparation_rows(value.inner)
}

///|
pub fn cleanup_conditional_required_output_preparation(
  value : ConditionalRequiredOutputPreparation,
) -> Result[Bool, @bounded.Issue] {
  let result = cleanup_admitted_output_preparation(value.inner)
  if result is Ok(true) {
    value.source.row = None
    value.source.index = -1
  }
  result
}
