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
  if !@strategy.graph_program_has_effects(graph) {
    return None
  }
  local_tasks_control_capacity(graph)
}

///|
/// The SAME physical Local task loop after whole inputs have been bound to
/// its original DAG. The quote grants no SourceFree purpose or execution.
pub fn source_input_local_tasks_control_capacity(
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  if @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_captured_prefix(graph) != 0 {
    return None
  }
  local_tasks_control_capacity(graph)
}

///|
/// SAME loop control plus checked finite Query-prefix guards. No Source row,
/// reader, provider or String is copied. One exact finite reference snapshot
/// prevents caller-array mutation across callbacks; use the shared array extent.
/// Each current/live closure borrows seven originals (2H/14R); the optional
/// live and private Plan argument add 2H/2R/2W. Prefix RowRun correspondence
/// predicates borrow original references and return Bool without new products.
/// The outer caller reserves this complete control before entering the loop.
pub fn installed_captured_local_tasks_control_capacity(
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  let first = @strategy.graph_captured_prefix(graph).to_int64()
  if first <= 0L ||
    first >= @strategy.graph_task_count(graph).to_int64() ||
    @strategy.graph_program_has_effects(graph) {
    return None
  }
  guard local_tasks_control_capacity(graph) is Some(base) &&
    @execution.preparation_array_representation(1L, first, false)
    is Some(snapshot) &&
    @execution.compose_preparation_representation([
      {
        record_headers: 4L,
        reference_slots: 16L,
        scalar_words: 2L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      snapshot,
    ])
    is Some(guards) &&
    @execution.preparation_representation_cost(guards) is Some(guards) &&
    @execution.execution_capacity(guards, guards) is Some(guards) else {
    return None
  }
  @execution.add_execution_capacity(base, guards)
}

///|
fn local_tasks_control_capacity(
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  let tasks = @strategy.graph_task_count(graph).to_int64()
  let ports = @strategy.graph_data_count(graph).to_int64()
  if tasks <= 0L {
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

///|
// SAME Effect control owner, retained beyond individual output/body retirement.
// Per checked task: completion field; completion Some + record; producer Some;
// occurrence Some + record. Original identity/target are borrowed DATA only.
// No rows, callbacks, input binding, holding or owned text/wire are retained.
fn captured_task_completion_control_capacity(
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  let tasks = if @strategy.graph_program_has_effects(graph) {
    @strategy.graph_task_count(graph).to_int64()
  } else {
    0L
  }
  @execution.preparation_representation_cost({
    record_headers: 5L * tasks,
    reference_slots: 7L * tasks,
    scalar_words: 4L * tasks,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).bind(bytes => @execution.execution_capacity(bytes, bytes))
}
