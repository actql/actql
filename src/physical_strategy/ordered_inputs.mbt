///|
fn ordered_data_inputs_complete(
  input_counts : Array[Int],
  data : Array[DataEdge],
  supplied_slots? : Array[LocalInputSlot] = [],
  deferred_slot? : LocalInputSlot? = None,
  captured_prefix? : Int = 1,
) -> Bool {
  if input_counts.is_empty() ||
    captured_prefix < 0 ||
    captured_prefix > input_counts.length() {
    return false
  }
  let seen : Array[Array[Bool]] = Array::makei(input_counts.length(), task => {
    let count = input_counts[task]
    if count < 0 {
      []
    } else {
      Array::make(count, false)
    }
  })
  for edge in data {
    if edge.consumer < captured_prefix || edge.consumer >= input_counts.length() {
      return false
    }
    let inputs = seen[edge.consumer]
    if edge.input < 0 || edge.input >= inputs.length() || inputs[edge.input] {
      return false
    }
    inputs[edge.input] = true
  }
  for input in supplied_slots {
    if input.consumer < captured_prefix ||
      input.consumer >= input_counts.length() {
      return false
    }
    let inputs = seen[input.consumer]
    if input.input < 0 || input.input >= inputs.length() || inputs[input.input] {
      return false
    }
    inputs[input.input] = true
  }
  if deferred_slot is Some(input) {
    if input.consumer < captured_prefix ||
      input.consumer >= input_counts.length() {
      return false
    }
    let inputs = seen[input.consumer]
    if input.input < 0 || input.input >= inputs.length() || inputs[input.input] {
      return false
    }
    inputs[input.input] = true
  }
  for task in captured_prefix..<input_counts.length() {
    if input_counts[task] < 0 {
      return false
    }
    for present in seen[task] {
      if !present {
        return false
      }
    }
  }
  true
}

///|
pub fn graph_ordered_inputs_complete(graph : CheckedDAG) -> Bool {
  ordered_data_inputs_complete(
    graph.input_counts,
    graph.data,
    supplied_slots=graph.supplied_slots,
    captured_prefix=graph.captured_prefix,
  )
}

///|
// Plan-only coordinates from the SAME checked Direct requests. Inline Sources
// beside an imported Unit have no produced data edge yet. Recording that exact
// original input obligation is not a live supplied read or a completed task.
fn graph_keyed_model_direct_plan_slots(
  graph : CheckedDAG,
) -> Array[LocalInputSlot]? {
  let slots = graph.supplied_slots.copy()
  let identity = @checked.source_identity(graph.program)
  for index in 0..<@checked.source_execution_count(graph.program) {
    let check = @checked.source_execution_at(graph.program, index).unwrap()
    guard @checked.source_execution_kind(check) is @checked.CarrierResponse else {
      continue
    }
    let subject = @checked.source_execution_subject(check)
    guard subject.request is @acquisition.Direct(mode, request) else {
      continue
    }
    guard physical_equal(subject.owner, identity) &&
      @context.program_identity_stage_requests(identity, subject.stage)
      is Some(requests) &&
      @acquisition.pipeline_request_at(requests, subject.input)
      is Some(@acquisition.Direct(original_mode, original_request)) &&
      physical_equal(mode, original_mode) &&
      physical_equal(request, original_request) &&
      graph_stage_operation_task(graph, subject.stage, 0) is Some(task) &&
      graph.owners.get(task) is Some(owner) &&
      @checked.unit_pipeline(graph.program, subject.stage) is Some(pipeline) &&
      physical_equal(pipeline, @lower.pipeline(@lower.bound_preparation(owner))) &&
      @pipeline.lookup(
        pipeline,
        @acquisition.declaration(@acquisition.mode_input(mode)).input_name,
      )
      is Some(@pipeline.Input(input)) else {
      return None
    }
    if task < graph.captured_prefix {
      continue
    }
    guard graph.selected_steps[task] is None &&
      input >= 0 &&
      input < graph.input_counts[task] &&
      !graph.data.any(edge => edge.consumer == task && edge.input == input) else {
      return None
    }
    let present = slots.filter(slot => {
      slot.consumer == task && slot.input == input
    })
    if present.length() > 1 ||
      present.any(slot => {
        slot.source_input != input || slot.operation_input is Some(_)
      }) {
      return None
    }
    if present.is_empty() {
      slots.push({
        consumer: task,
        input,
        source_input: input,
        operation_input: None,
      })
    }
  }
  Some(slots)
}

///|
/// Plan completeness only. The existing Direct-prefix constructor may retain a
/// downstream keyed request before Model input. Its exact checked request and
/// upstream key port describe a future producer, not startup CapturedRows.
/// Never insert these requirements into the graph's live supplied inventory.
fn graph_keyed_model_plan_input(
  graph : CheckedDAG,
  consumer : Int,
  model_step : Int,
) -> LocalInputSlot? {
  if (
      graph.captured_prefix < 1 &&
      !(graph.captured_prefix == 0 && !graph.supplied_slots.is_empty())
    ) ||
    model_step < 0 ||
    consumer < graph.captured_prefix ||
    consumer >= graph.owners.length() ||
    graph.selected_steps[consumer] is Some(_) {
    return None
  }
  if graph.prefix_ends[consumer] is Some(last) && last < model_step {
    return None
  }
  let mut stage = -1
  for index in 0..<graph.stage_tasks.length() {
    let tasks = graph.stage_tasks[index]
    if (tasks.length() == 1 && tasks[0] == consumer) ||
      tasks.get(model_step) == Some(consumer) {
      stage = index
      break
    }
  }
  if stage < graph.captured_prefix {
    return None
  }
  if graph.stage_tasks[stage].length() != 1 {
    for step in 0..<(model_step + 1) {
      if graph.stage_tasks[stage].get(step) != Some(consumer) {
        return None
      }
    }
  }
  let prepared = @lower.bound_preparation(graph.owners[consumer])
  let pipeline = @lower.pipeline(prepared)
  guard @checked.unit_pipeline(graph.program, stage) is Some(original_pipeline) &&
    physical_equal(pipeline, original_pipeline) &&
    @lower.node_at(prepared, model_step) is Some(model) &&
    @lower.payload(model) is @lower.Infer(_) else {
    return None
  }
  let identity = @checked.source_identity(graph.program)
  let mut deferred : LocalInputSlot? = None
  for index in 0..<@checked.source_execution_count(graph.program) {
    let check = @checked.source_execution_at(graph.program, index).unwrap()
    let subject = @checked.source_execution_subject(check)
    if subject.stage != stage {
      continue
    }
    guard @checked.source_execution_kind(check)
      is @checked.KeyedRequest(binding) else {
      continue
    }
    let step = @acquisition.keyed_join_step(binding.join)
    let left = @acquisition.keyed_join_left(binding.join)
    let left_complete = match left {
      @pipeline.Step(upstream) =>
        upstream >= 0 &&
        upstream < step &&
        @lower.node_at(prepared, upstream) is Some(_)
      @pipeline.Input(input) => {
        // A genuine imported Result needs no preceding operation. Its ONE
        // checked input port must still point to the exact producer/edge;
        // two Source ancestors do not create two consumer input ports.
        let incoming = graph.data.filter(edge => {
          edge.consumer == consumer && edge.input == input
        })
        match
          (
            @pipeline.input_at(pipeline, input),
            @pipeline.input_producer(pipeline, input),
            @checked.unit_input_completeness(graph.program, stage, input),
          ) {
          (Some((name, _)), Some(producer), Some(completeness)) =>
            match completeness.binding {
              @checked.Imported(interface, original) =>
                physical_equal(original, producer) &&
                interface.input_name == name &&
                incoming.length() == 1 &&
                incoming[0].target == @pipeline.producer_target(producer) &&
                graph.owners
                .get(incoming[0].producer)
                .map(owner => {
                  physical_equal(
                    @pipeline.producer_pipeline(producer),
                    @lower.pipeline(@lower.bound_preparation(owner)),
                  )
                })
                .unwrap_or(false)
              _ => false
            }
          _ => false
        }
      }
    }
    guard left_complete &&
      physical_equal(subject.owner, identity) &&
      binding.stage == stage &&
      subject.input == @acquisition.keyed_join_input(binding.join) &&
      step < model_step &&
      @lower.node_at(prepared, step) is Some(join) &&
      @lower.node_input_target(join, 0) == Some(left) &&
      @pipeline.lookup(
        pipeline,
        @acquisition.declaration(subject.source).input_name,
      )
      is Some(@pipeline.Input(source_input)) &&
      @lower.node_input_target(join, 1) == Some(@pipeline.Input(source_input)) &&
      @context.program_identity_stage_requests(identity, stage)
      is Some(requests) &&
      @acquisition.pipeline_request_at(requests, subject.input)
      is Some(@acquisition.Keyed(mode, request)) &&
      subject.request is @acquisition.Keyed(original_mode, original_request) &&
      physical_equal(mode, original_mode) &&
      physical_equal(request, original_request) &&
      physical_equal(@acquisition.keyed_join_request(binding.join), request) else {
      return None
    }
    if deferred is Some(_) {
      return None
    }
    // Source request ordinals exclude imported Result ports. Resolve the
    // original declared name into the pipeline before marking its plan slot.
    deferred = Some({
      consumer,
      input: source_input,
      source_input,
      operation_input: None,
    })
  }
  // This is the existing single-keyed producer/factory's construction scope.
  // More requests need their own original producer connection, never a count
  // inferred from aliases, sample rows or a caller-authored URI.
  guard deferred is Some(slot) &&
    graph_keyed_model_direct_plan_slots(graph) is Some(planned_sources) else {
    return None
  }
  let existing = planned_sources.filter(actual => {
    actual.consumer == slot.consumer && actual.input == slot.input
  })
  if existing.length() > 1 ||
    existing.any(actual => {
      actual.source_input != slot.source_input ||
      actual.operation_input != slot.operation_input
    }) {
    return None
  }
  guard ordered_data_inputs_complete(
    graph.input_counts,
    graph.data,
    supplied_slots=planned_sources,
    deferred_slot=if existing.is_empty() { deferred } else { None },
    captured_prefix=graph.captured_prefix,
  ) else {
    return None
  }
  Some(slot)
}

///|
pub fn graph_keyed_model_plan_inputs_complete(
  graph : CheckedDAG,
  consumer : Int,
  model_step : Int,
) -> Bool {
  graph_keyed_model_plan_input(graph, consumer, model_step) is Some(_)
}

///|
// Runtime binding only: an actual currently readable checked keyed input is
// required. The original graph and its plan-only supplied inventory stay
// unchanged; this private physical view borrows the same original Owners.
pub fn graph_with_completed_keyed_model_input(
  graph : CheckedDAG,
  consumer : Int,
  model_step : Int,
  read : @execution.SuppliedRelationRead,
) -> CheckedDAG? {
  guard graph_keyed_model_plan_input(graph, consumer, model_step) is Some(slot) &&
    @execution.supplied_relation_read_matches_input(
      read,
      graph.owners[consumer],
      slot.source_input,
    ) &&
    @execution.supplied_relation_read_available(read) else {
    return None
  }
  if graph.supplied_slots.any(actual => {
      actual.consumer == slot.consumer &&
      actual.input == slot.input &&
      actual.source_input == slot.source_input &&
      actual.operation_input == slot.operation_input
    }) {
    return Some(graph)
  }
  let supplied_slots = graph.supplied_slots.copy()
  supplied_slots.push(slot)
  Some({ ..graph, supplied_slots, })
}
