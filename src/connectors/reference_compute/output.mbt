///|
/// Produces admitted material only, not a successful execution or consumer
/// authority. The caller must still enforce common guards and seal evidence.
pub fn materialize_numeric_output(
  plan : NumericPlan,
  input : @execution.ProducerRead,
  max_work : Int,
  max_rows : Int,
  values : @execution.ValueLimits,
) -> Result[@execution.AdmittedOutputRows, PlanIssue] {
  materialize_with_roots(plan, input, max_work, max_rows, values, None)
}

///|
fn materialize_with_roots(
  plan : NumericPlan,
  input : @execution.ProducerRead,
  max_work : Int,
  max_rows : Int,
  values : @execution.ValueLimits,
  roots : ((Int, @execution.Value, @execution.Value, @execution.Value) -> Result[
    Unit,
    PlanIssue,
  ])?,
) -> Result[@execution.AdmittedOutputRows, PlanIssue] {
  let work = Ref(max_work)
  let (selected, projection) = match
    select_numeric_rows_with_work(plan, input, work, roots) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(plan.owner)),
      Step(1),
    )
    is Some(schema) else {
    return Err(Unsupported)
  }
  let buffer = match
    @execution.prepare_admitted_output(plan.owner, Step(1), max_rows, values) {
    Ok(buffer) => buffer
    Err(issue) => return Err(Output(issue))
  }
  let result = append_selected(
    plan, input, selected, projection, schema, buffer, work,
  )
  match result {
    Err(issue) => {
      @execution.cancel_admitted_output(buffer) |> ignore
      Err(issue)
    }
    Ok(_) =>
      @execution.finish_admitted_output(buffer).map_err(issue => Output(issue))
  }
}

///|
fn append_selected(
  _plan : NumericPlan,
  input : @execution.ProducerRead,
  selected : Array[Int],
  projection : Array[Int],
  schema : @schema.Schema,
  buffer : @execution.AdmittedOutput,
  work : Ref[Int],
) -> Result[Unit, PlanIssue] {
  for row in selected {
    if work.val == 0 {
      return Err(Limit)
    }
    work.val -= 1
    let cells = []
    for index, column in projection {
      if work.val == 0 {
        return Err(Limit)
      }
      work.val -= 1
      let raw : @source.Value = match
        @execution.producer_read_cell(input, row, column) {
        Some(Number(value)) | Some(Captured(@admitted.Number(value))) =>
          Number(value)
        Some(Null) | Some(Captured(@admitted.Null)) => Null
        _ => return Err(Unsupported)
      }
      let cursor = match
        @decode.admit(
          {
            value: raw,
            span: {
              start_byte: 0,
              end_byte: 0,
              start_line: 0,
              start_column: 0,
              end_line: 0,
              end_column: 0,
              source_path: "reference-compute",
            },
          },
          {
            max_nodes: 1,
            max_depth: 1,
            max_string_bytes: 0,
            max_total_string_bytes: 0,
          },
        ) {
        Ok(cursor) => cursor
        Err(issue) => return Err(Decoding(issue))
      }
      let value = match
        @admitted.admit(
          @schema.field_at(schema, index).unwrap().contract,
          cursor,
          { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
        ) {
        Ok(value) => value
        Err(issue) => return Err(Admission(issue))
      }
      cells.push(value)
    }
    match @execution.append_admitted_output(buffer, cells) {
      Ok(_) => ()
      Err(issue) => return Err(Output(issue))
    }
  }
  Ok(())
}
