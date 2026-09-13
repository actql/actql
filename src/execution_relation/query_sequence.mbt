///|
/// Local residual support for the shared, already derived acquisition boundary.
/// This is neither an acquisition admission nor a completed observation. Source
/// authority, actual receipt evidence and capture still belong to its caller.
struct QuerySequence {
  query : @acquisition.QueryAcquisition
  generated : GeneratedSequence
}

///|
/// Full selected-scan admission, bound to exactly one prepared query. This is
/// retained input material, not source authority or acquisition completion.
struct QueryReceipt {
  owner : QuerySequence
  rows : CapturedRows
}

///|
pub(all) enum QuerySequenceIssue {
  InvalidLimits
  Limit
  ForeignPipeline
  ForeignParameters
  ForeignReceipt
  UnsupportedExecutionShape
  CaptureNotRetained
  ReceiptAdmission(CaptureIssue)
  Execution(SequenceRunIssue)
}

///|
/// The sole driver executes every operation. Do not feed it a larger pipeline
/// and accidentally run downstream consumers before the acquisition capture.
/// Supporting a capture inside a larger pipeline requires an owned execution
/// slice, not deleting steps or rebuilding a different CheckedPipeline here.
pub fn prepare_query_sequence(
  query : @acquisition.QueryAcquisition,
  generated : GeneratedSequence,
  max_work : Int,
) -> Result[QuerySequence, QuerySequenceIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let control = { remaining: max_work, max_frames: 0, }
  if !spend_control(control, 1) {
    return Err(Limit)
  }
  let owner = @lower.sequence_owner(generated.sequence)
  let prepared = @lower.bound_preparation(owner)
  let pipeline = @lower.pipeline(prepared)
  if !physical_equal(pipeline, @acquisition.query_acquisition_pipeline(query)) {
    return Err(ForeignPipeline)
  }
  let parameters = @acquisition.request_parameter_values(
    @acquisition.pipeline_requests_parameters(
      @acquisition.query_acquisition_owner(query),
    ),
  )
  match @lower.parameter_bindings(owner) {
    Some(bound) =>
      if !physical_equal(bound, parameters) {
        return Err(ForeignParameters)
      }
    None =>
      if @parameter.bound_value_count(parameters) != 0 {
        return Err(ForeignParameters)
      }
  }
  if @pipeline.input_count(pipeline) != 1 ||
    @pipeline.step_count(pipeline) != 2 ||
    @acquisition.query_acquisition_input(query) != @pipeline.Input(0) ||
    @acquisition.query_acquisition_filter_index(query) != 0 ||
    @acquisition.query_acquisition_capture(query) != @pipeline.Step(1) {
    return Err(UnsupportedExecutionShape)
  }
  guard @lower.node_at(prepared, 1) is Some(node) else {
    return Err(UnsupportedExecutionShape)
  }
  // Only the capture output may be retained by this narrow residual adapter.
  // In particular, do not expose the unfiltered receipt or a pre-capture result.
  if generated.retained_ids.length() != 1 {
    return Err(CaptureNotRetained)
  }
  let expected = @lower.node_id(node)
  let retained = generated.retained_ids[0]
  if !spend_control_text(control, expected) ||
    !spend_control_text(control, retained) {
    return Err(Limit)
  }
  if expected != retained {
    return Err(CaptureNotRetained)
  }
  Ok({ query, generated, })
}

///|
/// Broad receipt only: admit the entire selected scan under the original input
/// schema before evaluating the checked filter. This cannot stand in for native
/// full-scan validation evidence when the Host only receives selected rows.
/// Successful local computation does not discharge acquisition obligations.
pub fn evaluate_query_receipt(
  prepared : QuerySequence,
  rows : Array[@decode.Cursor],
  max_received_rows : Int,
  admission : ValueLimits,
  execution : SequenceExecutionLimits,
) -> Result[CompletedSequence, QuerySequenceIssue] {
  let receipt = match
    admit_query_receipt(prepared, rows, max_received_rows, admission) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  execute_query_receipt(prepared, receipt, execution)
}

///|
/// Admit once and retain the immutable full scan, including rows and columns
/// that a native realization will not transmit. No filter runs on this path.
pub fn admit_query_receipt(
  prepared : QuerySequence,
  rows : Array[@decode.Cursor],
  max_received_rows : Int,
  admission : ValueLimits,
) -> Result[QueryReceipt, QuerySequenceIssue] {
  let captured = match
    capture_input(
      @lower.sequence_owner(prepared.generated.sequence),
      0,
      rows,
      max_rows=max_received_rows,
      admission,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ReceiptAdmission(issue))
  }
  Ok({ owner: prepared, rows: captured, })
}

///|
/// Reuse admitted material with a fresh execution budget. The driver still
/// performs its normal input accounting and checks; admission is not a credit.
pub fn execute_query_receipt(
  prepared : QuerySequence,
  receipt : QueryReceipt,
  execution : SequenceExecutionLimits,
) -> Result[CompletedSequence, QuerySequenceIssue] {
  if !physical_equal(prepared, receipt.owner) {
    return Err(ForeignReceipt)
  }
  match
    execute_generated_sequence(prepared.generated, [receipt.rows], execution) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Execution(issue))
  }
}

///|
/// Immutable, owned material for bounded access hashing by the Host. This does
/// not expose a completion handle or permit a caller to issue execution records.
pub fn query_receipt_rows(receipt : QueryReceipt) -> CapturedRows {
  receipt.rows
}

///|
pub fn query_sequence_requirement(
  prepared : QuerySequence,
) -> @acquisition.QueryAcquisition {
  prepared.query
}
