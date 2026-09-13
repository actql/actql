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
fn query_guard_phase(
  phase : @execution.FixedInputGuardPhase,
) -> QueryGuardPhase {
  match phase {
    InputValues => Scan
    Output => Output
  }
}

///|
/// Query ownership and port selection wrap the acquisition-independent engine.
pub fn execute_query_receipt_guarded(
  prepared : QuerySequence,
  receipt : QueryReceipt,
  execution : @execution.SequenceExecutionLimits,
  max_output_rows~ : Int,
  max_value_bytes~ : Int,
  physical : QueryGuardMeasureLimits,
) -> Result[(@execution.CompletedSequence, (Int, Int, Int)), QueryGuardIssue] {
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
  match
    @execution.execute_fixed_input_guarded(
      prepared.generated,
      receipt.rows,
      @acquisition.query_acquisition_capture(prepared.query),
      execution,
      max_output_rows~,
      max_value_bytes~,
      {
        max_work: physical.max_work,
        max_bytes: physical.max_bytes,
        max_nodes: physical.max_nodes,
        max_depth: physical.max_depth,
      },
    ) {
    Ok(value) => Ok(value)
    Err(issue) =>
      Err(
        match issue {
          InvalidLimits => InvalidLimits
          ForeignInput => ForeignReceipt
          MeasurementWork => MeasurementWork
          Measurement(phase, row, column, issue) =>
            Measurement(query_guard_phase(phase), row, column, issue)
          ValueBytes(phase, row, column) =>
            ValueBytes(query_guard_phase(phase), row, column)
          InvalidLayout => InvalidLayout
          Execution(issue) => Execution(QuerySequenceIssue::Execution(issue))
          OutputRows => OutputRows
          MissingOutput => MissingOutput
        },
      )
  }
}
