///|
struct RowsToVectorsExecution {
  inner : RowsToEventsExecution
}

///|
pub enum RowsToVectorsPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@records.Completed, progress~ : Int64, work~ : Int64)
  Failed(EventsBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
struct VectorsToRowsExecution {
  inner : EventsToRowsExecution
}

///|
pub enum VectorsToRowsPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  Failed(EventsBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub fn start_rows_to_vectors(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @execution.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[RowsToVectorsExecution, EventsBridgeIssue] {
  start_rows_to_records(
    control,
    sequence,
    step,
    input,
    limits,
    storage_bytes,
    available,
    fn(prepared, node) {
      match prepared {
        @lower.VectorStep(vector) =>
          @lower.operation(node) == "BRIDGE.rows.to_vectors" &&
          @carrier.kind(@lower.vector_output_carrier(vector)) ==
          @carrier.VectorsKind
        _ => false
      }
    },
  ).map(inner => { inner, })
}

///|
pub fn advance_rows_to_vectors(
  value : RowsToVectorsExecution,
  quantum : Int,
) -> Result[RowsToVectorsPoll, EventsBridgeIssue] {
  advance_rows_to_events(value.inner, quantum).map(fn(poll) {
    match poll {
      Continue(progress~, work~) => Continue(progress~, work~)
      Complete(output, progress~, work~) => Complete(output, progress~, work~)
      Failed(issue, progress~, work~) => Failed(issue, progress~, work~)
      Stopped(reason, progress~, work~) => Stopped(reason, progress~, work~)
    }
  })
}

///|
pub fn cleanup_rows_to_vectors(
  value : RowsToVectorsExecution,
) -> Result[Bool, EventsBridgeIssue] {
  cleanup_rows_to_events(value.inner)
}

///|
pub fn rows_to_vectors_cleanup_pending(value : RowsToVectorsExecution) -> Bool {
  rows_to_events_cleanup_pending(value.inner)
}

///|
pub fn start_vectors_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[VectorsToRowsExecution, EventsBridgeIssue] {
  start_records_to_rows(
    control,
    preparation,
    sequence,
    step,
    input,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    inputs,
    @projection.Vectors,
    fn(carrier) { carrier is @carrier.VectorValue(_) },
    control_work_limit,
  ).map(inner => { inner, })
}

///|
pub fn start_vectors_view_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[VectorsToRowsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    @lower.carrier_projection_operation(projection) == @projection.Vectors &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_kind(input) == @carrier.VectorsKind &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidKernel)
  }
  start_storage_to_rows(
    control,
    preparation,
    owner,
    @pipeline.Step(step),
    Viewed(input),
    fn() { @lifecycle.producer_view_record_count(input) is Some(_) },
    None,
    schema,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    None,
    control_work_limit,
  ).map(inner => { inner, })
}

///|
pub fn advance_vectors_to_rows(
  value : VectorsToRowsExecution,
  quantum : Int,
) -> Result[VectorsToRowsPoll, EventsBridgeIssue] {
  advance_events_to_rows(value.inner, quantum).map(fn(poll) {
    match poll {
      Continue(progress~, work~) => Continue(progress~, work~)
      Complete(output, progress~, work~) => Complete(output, progress~, work~)
      Failed(issue, progress~, work~) => Failed(issue, progress~, work~)
      Stopped(reason, progress~, work~) => Stopped(reason, progress~, work~)
    }
  })
}

///|
pub fn cleanup_vectors_to_rows(
  value : VectorsToRowsExecution,
) -> Result[Bool, EventsBridgeIssue] {
  cleanup_events_to_rows(value.inner)
}

///|
pub fn vectors_to_rows_cleanup_pending(value : VectorsToRowsExecution) -> Bool {
  events_to_rows_cleanup_pending(value.inner)
}
