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

///|
/// Caller controls for a retained Effect tail, composed into the original
/// Plan before execution. Provider/import/output buffers remain in that Plan's
/// existing task quotes. This accounts only for the shared driving loop:
/// its task table, current/live/reject/lookup/cleanup closures, result/failure
/// records, per-task operation/completion aliases and ordered input wrappers.
/// Count all task-local wrappers together, even though preparation temporaries
/// normally die before the next task. No row, String or provider copy is added.
pub fn retained_effect_local_tasks_control_capacity(
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  let tasks = @strategy.graph_task_count(graph).to_int64()
  let ports = @strategy.graph_data_count(graph).to_int64()
  if tasks <= 0L || !@strategy.graph_program_has_effects(graph) {
    return None
  }
  let bytes = @execution.preparation_representation_cost({
    // Fixed loop/result/error frames; each task's record, Some/Result and
    // preparation/obligation wrappers; each ordered port's variant and array.
    record_headers: 16L + 12L * tasks + 2L * ports,
    reference_slots: 32L + 16L * tasks + 4L * ports,
    scalar_words: 8L + 4L * tasks + ports,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
  bytes.bind(value => @execution.execution_capacity(value, value))
}
