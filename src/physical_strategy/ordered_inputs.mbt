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
/// Plan completeness only. The existing two-Direct constructor may retain a
/// downstream keyed request before Model input. Its exact checked request and
/// upstream key port describe a future producer, not startup CapturedRows.
/// Never insert these requirements into the graph's live supplied inventory.
pub fn graph_keyed_model_plan_inputs_complete(
  graph : CheckedDAG,
  consumer : Int,
  model_step : Int,
) -> Bool {
  if graph.captured_prefix != 2 ||
    model_step < 0 ||
    consumer < graph.captured_prefix ||
    consumer >= graph.owners.length() ||
    graph.selected_steps[consumer] is Some(_) {
    return false
  }
  if graph.prefix_ends[consumer] is Some(last) && last < model_step {
    return false
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
    return false
  }
  if graph.stage_tasks[stage].length() != 1 {
    for step in 0..<(model_step + 1) {
      if graph.stage_tasks[stage].get(step) != Some(consumer) {
        return false
      }
    }
  }
  let prepared = @lower.bound_preparation(graph.owners[consumer])
  let pipeline = @lower.pipeline(prepared)
  guard @checked.unit_pipeline(graph.program, stage) is Some(original_pipeline) &&
    physical_equal(pipeline, original_pipeline) &&
    @lower.node_at(prepared, model_step) is Some(model) &&
    @lower.payload(model) is @lower.Infer(_) else {
    return false
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
    guard physical_equal(subject.owner, identity) &&
      binding.stage == stage &&
      subject.input == @acquisition.keyed_join_input(binding.join) &&
      step < model_step &&
      @acquisition.keyed_join_left(binding.join) is @pipeline.Step(upstream) &&
      upstream >= 0 &&
      upstream < step &&
      @lower.node_at(prepared, upstream) is Some(_) &&
      @lower.node_at(prepared, step) is Some(join) &&
      @lower.node_input_target(join, 0) == Some(@pipeline.Step(upstream)) &&
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
      return false
    }
    if deferred is Some(_) {
      return false
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
  deferred is Some(_) &&
  ordered_data_inputs_complete(
    graph.input_counts,
    graph.data,
    supplied_slots=graph.supplied_slots,
    deferred_slot=deferred,
    captured_prefix=graph.captured_prefix,
  )
}
