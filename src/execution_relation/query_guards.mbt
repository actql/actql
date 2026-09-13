///|
/// Physical measurement limits, separate from the acquisition's logical guards
/// and the evaluator's existing logical work/live-root budgets.
pub(all) struct QueryGuardMeasureLimits {
  max_work : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum QueryGuardPhase {
  Scan
  Output
}

///|
pub(all) enum QueryGuardIssue {
  InvalidLimits
  ForeignReceipt
  MeasurementWork
  Measurement(QueryGuardPhase, Int, Int, @encode.EncodeFailure)
  ValueBytes(QueryGuardPhase, Int, Int)
  InvalidLayout
  Execution(QuerySequenceIssue)
  OutputRows
  MissingOutput
}

///|
priv struct QueryGuardBudget {
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  depth : Int
}

///|
fn[T : IndexedRows] measure_query_values(
  rows : T,
  ceiling : Int,
  phase : QueryGuardPhase,
  budget : QueryGuardBudget,
) -> Result[Unit, QueryGuardIssue] {
  for row in 0..<rows.row_count() {
    if budget.work <= 0 {
      return Err(MeasurementWork)
    }
    budget.work -= 1
    if rows.row_width(row) != rows.column_count() {
      return Err(InvalidLayout)
    }
    for column in 0..<rows.column_count() {
      if budget.work <= 0 {
        return Err(MeasurementWork)
      }
      budget.work -= 1
      let usage = try {
        let writer = @encode.measuring_writer(
          budget.bytes,
          budget.nodes,
          budget.depth,
        )
        emit_runtime_value(rows.read_cell(row, column), writer)
        @encode.finish_measurement_usage(writer)
      } catch {
        issue => return Err(Measurement(phase, row, column, issue))
      }
      budget.bytes -= usage.0
      budget.nodes -= usage.1
      if usage.0 > ceiling {
        return Err(ValueBytes(phase, row, column))
      }
    }
  }
  Ok(())
}

///|
/// Enforce all known scan values before evaluating any filter, then the complete
/// select output. Existing fragment budgets retain their row/live/work rules;
/// an additional root-only ceiling applies without changing checked identities.
/// Success is still a computation, not an acquisition capture or issuer record.
pub fn execute_query_receipt_guarded(
  prepared : QuerySequence,
  receipt : QueryReceipt,
  execution : SequenceExecutionLimits,
  max_output_rows~ : Int,
  max_value_bytes~ : Int,
  physical : QueryGuardMeasureLimits,
) -> Result[(CompletedSequence, (Int, Int, Int)), QueryGuardIssue] {
  if max_output_rows < 0 ||
    max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(prepared, receipt.owner) {
    return Err(ForeignReceipt)
  }
  let budget : QueryGuardBudget = {
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  match
    measure_query_values(
      ReceiptWireRows::{ receipt, },
      max_value_bytes,
      Scan,
      budget,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let original = prepared.generated
  if original.contexts.length() > budget.work {
    return Err(MeasurementWork)
  }
  budget.work -= original.contexts.length()
  let contexts = original.contexts.map(context => {
    ..context,
    root_result_bytes: Some(
      match context.root_result_bytes {
        Some(prior) => Int64::min(prior, max_value_bytes.to_int64())
        None => max_value_bytes.to_int64()
      },
    ),
  })
  let generated = GeneratedSequence::{ ..original, contexts, }
  let completed = match
    execute_generated_sequence(generated, [receipt.rows], execution) {
    Ok(value) => value
    Err(issue) => return Err(Execution(QuerySequenceIssue::Execution(issue)))
  }
  guard completed_output(
      completed,
      @acquisition.query_acquisition_capture(prepared.query),
    )
    is Some(output) else {
    return Err(MissingOutput)
  }
  if completed_row_count(output) > max_output_rows {
    return Err(OutputRows)
  }
  match measure_query_values(output.table, max_value_bytes, Output, budget) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok(
    (
      completed,
      (
        physical.max_work - budget.work,
        physical.max_bytes - budget.bytes,
        physical.max_nodes - budget.nodes,
      ),
    ),
  )
}
