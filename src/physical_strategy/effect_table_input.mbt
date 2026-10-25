///|
/// A private input in the same checked Effect inventory. Its authored member,
/// Stage declaration and producer target cannot be replaced by a Result port.
pub struct CheckedEffectTableInputPort {
  member_index : Int
  stage : Int
  task : Int
  occurrence : @execution.ManagedTableInputOccurrence
}

///|
fn bind_checked_effect_table_inputs(
  bindings : @results.EffectResultBindings,
  graph : CheckedDAG,
  owners : Array[@lower.BoundPrepared],
) -> Result[Array[CheckedEffectTableInputPort?], GraphIssue] {
  let incoming = @context.incoming_links_requirements(
    @context.program_incoming_gates_owner(
      @checked.incoming_gates(graph.program),
    ),
  )
  let wiring = @context.program_incoming_wiring(incoming)
  let output : Array[CheckedEffectTableInputPort?] = []
  for index in 0..<@results.effect_result_binding_count(bindings) {
    let binding = @results.effect_result_binding_at(bindings, index).unwrap()
    let header = @results.effect_result_binding_header(binding)
    let stage = @syntax.effect_header_stage(header)
    match @syntax.effect_header_source_table_input(header) {
      None => {
        if @results.effect_result_binding_table_input(binding) is Some(_) {
          return Err(ForeignEffectSource(index))
        }
        output.push(None)
      }
      Some(name) => {
        guard @syntax.effect_header_kind(header) == "store" &&
          @syntax.effect_header_source_result(header) is None &&
          @results.effect_result_binding_result(binding) is None &&
          @results.effect_result_binding_table_input(binding)
          is Some(definition) &&
          @results.wiring_stage_at(wiring, stage) is Some(stage_ports) &&
          @results.stage_port_table_inputs(stage_ports) is Some(inputs) &&
          @ports.lookup_table_input(inputs, name) is Some(actual) &&
          physical_equal(actual, definition) &&
          owners.get(stage) is Some(owner) else {
          return Err(ForeignEffectSource(index))
        }
        let occurrence = match
          @execution.bind_managed_table_input_occurrence(owner, inputs, name) {
          Ok(value) => value
          Err(_) => return Err(ForeignEffectSource(index))
        }
        guard graph_stage_target_task(
            graph,
            stage,
            @ports.table_input_target(definition),
          )
          is Some(task) &&
          graph.owners.get(task) is Some(task_owner) &&
          physical_equal(owner, task_owner) else {
          return Err(UnsupportedEffectSource(index))
        }
        output.push(Some({ member_index: index, stage, task, occurrence, }))
      }
    }
  }
  Ok(output)
}

///|
pub fn checked_effect_table_input_at(
  value : CheckedEffectComputationDAG,
  index : Int,
) -> CheckedEffectTableInputPort? {
  value.table_sources.get(index).bind(value => value)
}

///|
pub fn checked_effect_table_input_member(
  value : CheckedEffectTableInputPort,
) -> Int {
  value.member_index
}

///|
pub fn checked_effect_table_input_stage(
  value : CheckedEffectTableInputPort,
) -> Int {
  value.stage
}

///|
pub fn checked_effect_table_input_task(
  value : CheckedEffectTableInputPort,
) -> Int {
  value.task
}
