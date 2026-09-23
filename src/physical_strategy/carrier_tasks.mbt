///|
/// Split a mixed sequence at checked managed read boundaries. A prefix without
/// standalone providers remains one fused task through its Relation bridge;
/// later row operations use their own selected tasks.
/// -1 means that every step can be selected independently.
fn carrier_segment_prefix_end(graph : CheckedDAG, stage : Int) -> Int? {
  if stage <= 0 || stage >= graph.owners.length() {
    return None
  }
  if graph.selected_steps[stage] is Some(_) ||
    graph.prefix_ends[stage] is Some(_) {
    return None
  }
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let pipeline = @lower.pipeline(prepared)
  let count = @pipeline.step_count(pipeline)
  if count < 2 {
    return None
  }
  let mut found_carrier = false
  let mut found_relation = false
  let mut prefer_fused_without_relation = false
  let mut all_selected = true
  for step in 0..<count {
    guard @lower.node_at(prepared, step) is Some(node) else { return None }
    if !@lower.node_supports_selected_managed_execution(node) {
      all_selected = false
      break
    }
    if @lower.operation(node) == "BRIDGE.rows.to_graph" &&
      @lower.node_input_count(node) > 1 {
      guard @lower.node_input_target(node, 0) is Some(first) else {
        return None
      }
      for input in 1..<@lower.node_input_count(node) {
        if @lower.node_input_target(node, input) != Some(first) {
          return None
        }
      }
    }
    for input in 0..<@lower.node_input_count(node) {
      match @lower.node_input_target(node, input) {
        Some(@pipeline.Step(producer)) => {
          guard producer >= 0 &&
            producer < step &&
            @lower.preparation_carrier_at(prepared, @pipeline.Step(producer))
            is Some(carrier) else {
            return None
          }
          if @carrier.kind(carrier) == @carrier.RelationKind {
            if @lower.preparation_schema_at(prepared, @pipeline.Step(producer))
              is None ||
              !@lower.node_accepts_managed_relation_view(node, input) {
              return None
            }
            found_relation = true
          } else {
            if !@lower.node_accepts_managed_carrier_view(node, input) {
              return None
            }
            found_carrier = true
            if @lower.node_prefers_fused_without_relation_consumer(node) {
              prefer_fused_without_relation = true
            }
          }
        }
        Some(@pipeline.Input(_)) => ()
        None => return None
      }
    }
  }
  if all_selected &&
    found_carrier &&
    (!prefer_fused_without_relation || found_relation) {
    return Some(-1)
  }
  // Find the maximal selected Relation suffix in one pass. Its predecessor
  // is the exact output retained by the fused prefix.
  let mut suffix_start = count
  while suffix_start > 1 {
    let step = suffix_start - 1
    guard @lower.node_at(prepared, step) is Some(node) else { return None }
    if !@lower.node_supports_selected_managed_execution(node) ||
      @lower.node_input_count(node) != 1 ||
      !@lower.node_accepts_managed_relation_view(node, 0) ||
      @lower.node_input_target(node, 0) != Some(@pipeline.Step(step - 1)) {
      break
    }
    suffix_start = step
  }
  if suffix_start == count || suffix_start < 2 {
    return None
  }
  let terminal = suffix_start - 1
  guard @lower.preparation_carrier_at(prepared, @pipeline.Step(terminal))
    is Some(carrier) &&
    @carrier.kind(carrier) == @carrier.RelationKind else {
    return None
  }
  let mut carrier_prefix = false
  for step in 0..<terminal {
    guard @lower.preparation_carrier_at(prepared, @pipeline.Step(step))
      is Some(input_carrier) else {
      return None
    }
    if @carrier.kind(input_carrier) != @carrier.RelationKind {
      carrier_prefix = true
    }
  }
  if !carrier_prefix {
    return None
  }
  for result in graph.results {
    if result.task == stage {
      match
        @ports.port_target(
          @execution.managed_result_occurrence_port(result.occurrence),
        ) {
        @pipeline.Step(step) => if step < terminal { return None }
        _ => return None
      }
    }
  }
  Some(terminal)
}

///|
fn mapped_stage_target(
  tasks : Array[Array[Int]],
  stage : Int,
  target : @pipeline.Target,
) -> Int? {
  guard tasks.get(stage) is Some(stage_tasks) && !stage_tasks.is_empty() else {
    return None
  }
  if stage_tasks.length() == 1 {
    return stage_tasks.get(0)
  }
  match target {
    @pipeline.Step(step) => stage_tasks.get(step)
    @pipeline.Input(_) => None
  }
}

///|
fn original_data_edge(
  graph : CheckedDAG,
  stage : Int,
  input : Int,
) -> DataEdge? {
  for edge in graph.data {
    if edge.consumer == stage && edge.input == input {
      return Some(edge)
    }
  }
  None
}

///|
fn original_supplied_slot(
  graph : CheckedDAG,
  stage : Int,
  input : Int,
) -> LocalInputSlot? {
  for slot in graph.supplied_slots {
    if slot.consumer == stage && slot.input == input {
      return Some(slot)
    }
  }
  None
}

///|
/// Expand structurally safe mixed Carrier/Relation sequences into common
/// physical tasks. The author-visible owner, global step coordinates and
/// Result occurrences remain unchanged.
pub fn expand_internal_carrier_tasks(
  graph : CheckedDAG,
  max_tasks : Int,
  max_work : Int,
) -> Result[CheckedDAG, GraphIssue] {
  if max_tasks < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let stages = graph.owners.length()
  let mut any_segmentable = false
  for stage in 0..<stages {
    if carrier_segment_prefix_end(graph, stage) is Some(_) {
      any_segmentable = true
      break
    }
  }
  if !any_segmentable {
    return Ok(graph)
  }
  let mut work = max_work
  let stage_tasks : Array[Array[Int]] = Array::makei(stages, _ => [])
  let expanded = Array::make(stages, false)
  let owners = []
  let targets = []
  let input_counts = []
  let selected_steps = []
  let prefix_ends = []
  let operations : Array[Array[TaskOperationRequirement]] = []
  let numeric : Array[Array[TaskNumericObservation]] = []

  for stage in 0..<stages {
    if work == 0 {
      return Err(WorkLimit)
    }
    work -= 1
    let split_boundary = carrier_segment_prefix_end(graph, stage)
    let split = split_boundary is Some(_)
    expanded[stage] = split
    let step_count = @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(graph.owners[stage])),
    )
    let prefix_end = split_boundary.unwrap_or(-1)
    let task_count = if !split {
      1
    } else if prefix_end < 0 {
      step_count
    } else {
      step_count - prefix_end
    }
    let mapping_work = if split { step_count } else { 1 }
    if owners.length() + task_count > max_tasks || mapping_work > work {
      return Err(
        if owners.length() + task_count > max_tasks {
          TaskLimit
        } else {
          WorkLimit
        },
      )
    }
    work -= mapping_work
    for position in 0..<task_count {
      let task = owners.length()
      if split && position == 0 && prefix_end >= 0 {
        for _ in 0..<(prefix_end + 1) {
          stage_tasks[stage].push(task)
        }
      } else {
        stage_tasks[stage].push(task)
      }
      owners.push(graph.owners[stage])
      operations.push([])
      numeric.push([])
      if split {
        let step = if prefix_end >= 0 {
          prefix_end + position
        } else {
          position
        }
        let node = @lower.node_at(
          @lower.bound_preparation(graph.owners[stage]),
          step,
        ).unwrap()
        targets.push(Some(@pipeline.Step(step)))
        if prefix_end >= 0 && position == 0 {
          input_counts.push(graph.input_counts[stage])
          selected_steps.push(None)
          prefix_ends.push(Some(prefix_end))
        } else {
          input_counts.push(@lower.node_input_count(node))
          selected_steps.push(Some(step))
          prefix_ends.push(None)
        }
      } else {
        targets.push(graph.targets[stage])
        input_counts.push(graph.input_counts[stage])
        selected_steps.push(None)
        prefix_ends.push(None)
      }
    }
  }

  let data : Array[DataEdge] = []
  let supplied_slots : Array[LocalInputSlot] = []
  for stage in 0..<stages {
    if !expanded[stage] {
      let consumer = stage_tasks[stage][0]
      for edge in graph.data {
        if edge.consumer == stage {
          guard mapped_stage_target(stage_tasks, edge.producer, edge.target)
            is Some(producer) else {
            return Err(ForeignPort(stage, edge.input))
          }
          data.push({ ..edge, producer, consumer, })
        }
      }
      for slot in graph.supplied_slots {
        if slot.consumer == stage {
          supplied_slots.push({ ..slot, consumer, })
        }
      }
      continue
    }
    let prepared = @lower.bound_preparation(graph.owners[stage])
    let prefix_end = carrier_segment_prefix_end(graph, stage).unwrap_or(-1)
    if prefix_end >= 0 {
      let prefix_task = stage_tasks[stage][0]
      for edge in graph.data {
        if edge.consumer == stage {
          guard mapped_stage_target(stage_tasks, edge.producer, edge.target)
            is Some(producer) else {
            return Err(ForeignPort(stage, edge.input))
          }
          data.push({ ..edge, producer, consumer: prefix_task, })
        }
      }
      for slot in graph.supplied_slots {
        if slot.consumer == stage {
          supplied_slots.push({ ..slot, consumer: prefix_task, })
        }
      }
    }
    for step, consumer in stage_tasks[stage] {
      if step <= prefix_end {
        continue
      }
      let node = @lower.node_at(prepared, step).unwrap()
      for operation_input in 0..<@lower.node_input_count(node) {
        match @lower.node_input_target(node, operation_input) {
          Some(@pipeline.Step(producer_step)) =>
            data.push({
              producer: stage_tasks[stage][producer_step],
              target: @pipeline.Step(producer_step),
              consumer,
              input: operation_input,
              source_input: None,
              operation_input: Some((step, operation_input)),
            })
          Some(@pipeline.Input(source_input)) =>
            match original_data_edge(graph, stage, source_input) {
              Some(edge) => {
                guard mapped_stage_target(
                    stage_tasks,
                    edge.producer,
                    edge.target,
                  )
                  is Some(producer) else {
                  return Err(ForeignPort(stage, source_input))
                }
                data.push({
                  producer,
                  target: edge.target,
                  consumer,
                  input: operation_input,
                  source_input: Some(source_input),
                  operation_input: Some((step, operation_input)),
                })
              }
              None =>
                match original_supplied_slot(graph, stage, source_input) {
                  Some(slot) =>
                    supplied_slots.push({
                      consumer,
                      input: operation_input,
                      source_input: slot.source_input,
                      operation_input: Some((step, operation_input)),
                    })
                  None => return Err(MissingProducer(stage, source_input))
                }
            }
          None => return Err(ForeignPort(stage, operation_input))
        }
      }
    }
  }

  let control = []
  for edge in graph.control {
    let predecessor_tasks = stage_tasks[edge.predecessor]
    let consumer_tasks = stage_tasks[edge.consumer]
    control.push({
      predecessor: predecessor_tasks[predecessor_tasks.length() - 1],
      consumer: consumer_tasks[0],
      gate: edge.gate,
    })
  }
  for stage in 0..<stages {
    for requirement in graph.operations[stage] {
      let task = if expanded[stage] {
        stage_tasks[stage][requirement.site.step]
      } else {
        stage_tasks[stage][0]
      }
      operations[task].push(requirement)
    }
    for observation in graph.numeric[stage] {
      let task = if expanded[stage] {
        stage_tasks[stage][observation.step]
      } else {
        stage_tasks[stage][0]
      }
      numeric[task].push(observation)
    }
  }
  let results = []
  for result in graph.results {
    let target = @ports.port_target(
      @execution.managed_result_occurrence_port(result.occurrence),
    )
    guard mapped_stage_target(stage_tasks, result.task, target) is Some(task) else {
      return Err(ForeignPort(result.task, 0))
    }
    results.push({ task, occurrence: result.occurrence, })
  }
  Ok({
    program: graph.program,
    source_free_root: graph.source_free_root,
    owners,
    stage_tasks,
    targets,
    input_counts,
    selected_steps,
    prefix_ends,
    data,
    supplied_slots,
    control,
    operations,
    numeric,
    results,
  })
}
