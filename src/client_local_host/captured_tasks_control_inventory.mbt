///|
// Incremental captured-entry constructors only. The existing source-free
// task array/current/live/reject/output closures keep their original owner.
// Each new guard closure retains its caller callback, DAG, capture and exact
// requirements (1H/4R). The optional live guard adds Some (1H/1R/1W).
// Quote both guards even when the optional one is absent. No payload is copied.
let captured_local_tasks_control_units : @execution.PreparationRepresentationUnits = {
  record_headers: 3L,
  reference_slots: 9L,
  scalar_words: 1L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let captured_local_tasks_control_bytes : Int64 = @execution.preparation_representation_cost(
  captured_local_tasks_control_units,
).unwrap()

///|
/// Pure constructor quote, not a reservation or an admission. The original
/// outer Host composes this once into its fixed control reservation before
/// execute_captured_local_tasks_guarded and retains it through result/failure
/// cleanup. Source and selected Common provider capacity remain separate.
pub fn captured_local_tasks_control_capacity() -> @execution.ExecutionCapacity? {
  @execution.execution_capacity(
    captured_local_tasks_control_bytes, captured_local_tasks_control_bytes,
  )
}
