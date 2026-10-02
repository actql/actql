///|
/// Follow checked source edges to a bounded zero-input source or a typed
/// Carrier boundary. Ordinary remote Relation chains keep their native
/// whole-Stage realization until that realization supports selected Steps.
fn segmentable_relation_source(graph : CheckedDAG, start : Int) -> Bool {
  let mut stage = start
  let mut visited = 0
  while stage >= 0 &&
        stage < graph.owners.length() &&
        visited < graph.owners.length() {
    visited += 1
    let prepared = @lower.bound_preparation(graph.owners[stage])
    let count = @pipeline.step_count(@lower.pipeline(prepared))
    for step in 0..<count {
      guard @lower.preparation_carrier_at(prepared, @pipeline.Step(step))
        is Some(carrier) else {
        return false
      }
      if @carrier.kind(carrier) != @carrier.RelationKind {
        return true
      }
    }
    guard count > 0 && @lower.node_at(prepared, 0) is Some(first) else {
      return false
    }
    if @lower.preparation_input_count(prepared) == 0 &&
      @lower.node_input_count(first) == 0 {
      return @lower.node_supports_selected_managed_execution(first)
    }
    guard @lower.node_input_count(first) == 1 &&
      @lower.node_input_target(first, 0) is Some(@pipeline.Input(source)) else {
      return false
    }
    let mut predecessor = -1
    for edge in graph.data {
      if edge.consumer == stage && edge.input == source {
        predecessor = edge.producer
        break
      }
    }
    stage = predecessor
  }
  false
}

///|
/// Keep a Relation family child and its linear bounded suffix under one owner.
/// This is a shape decision, not provider registration or execution authority.
fn bounded_family_relation_chain(graph : CheckedDAG, stage : Int) -> Bool {
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let count = @pipeline.step_count(@lower.pipeline(prepared))
  guard count > 1 && @lower.node_at(prepared, 0) is Some(first) else {
    return false
  }
  match @lower.payload(first) {
    @lower.NestRows(_)
    | @lower.TimeSeriesValue(_)
    | @lower.IntervalJoinRows(_)
    | @lower.AsOfJoinRows(_)
    | @lower.SequenceRows(_) => ()
    @lower.EventValue(_) if @lower.operation(first) ==
      "TEA.window.session_assign" => ()
    _ => return false
  }
  for step in 0..<count {
    guard @lower.node_at(prepared, step) is Some(node) &&
      @carrier.kind(@lower.node_output_carrier(node)) == @carrier.RelationKind else {
      return false
    }
    if step > 0 &&
      (
        !@lower.node_supports_selected_managed_execution(node) ||
        @lower.node_input_count(node) != 1 ||
        @lower.node_input_target(node, 0) != Some(@pipeline.Step(step - 1))
      ) {
      return false
    }
    for port in 0..<@lower.node_input_count(node) {
      guard @lower.node_accepts_managed_relation_view(node, port) &&
        @lower.node_input_target(node, port) is Some(target) &&
        @lower.preparation_carrier_at(prepared, target) is Some(input) &&
        @carrier.kind(input) == @carrier.RelationKind else {
        return false
      }
    }
  }
  // Intermediate Result roots need independently owned task outputs.
  for result in graph.results {
    if result.task == stage &&
      @ports.port_target(
        @execution.managed_result_occurrence_port(result.occurrence),
      ) !=
      @pipeline.Step(count - 1) {
      return false
    }
  }
  true
}

///|
/// Split a mixed sequence at checked managed read boundaries. A prefix without
/// standalone providers remains one fused task through its Relation bridge;
/// later row operations use their own selected tasks.
/// -1 means that every step can be selected independently.
fn carrier_segment_prefix_end(graph : CheckedDAG, stage : Int) -> Int? {
  if stage < 0 || stage >= graph.owners.length() {
    return None
  }
  if graph.selected_steps[stage] is Some(_) ||
    graph.prefix_ends[stage] is Some(_) {
    return None
  }
  let prepared = @lower.bound_preparation(graph.owners[stage])
  let pipeline = @lower.pipeline(prepared)
  let count = @pipeline.step_count(pipeline)
  let mut intermediate_result = false
  for result in graph.results {
    if result.task == stage &&
      @ports.port_target(
        @execution.managed_result_occurrence_port(result.occurrence),
      )
      is @pipeline.Step(step) &&
      step < count - 1 {
      intermediate_result = true
    }
  }
  if stage == 0 {
    if !graph.source_free_root {
      return None
    }
    let mut values_source = false
    let mut carrier_construction = false
    let mut carrier_relation_consumer = false
    let mut relation_only = true
    let mut values_roots = 0
    for step in 0..<count {
      guard @lower.node_at(prepared, step) is Some(node) else { return None }
      match @lower.operation(node) {
        "REL.values" => {
          values_source = true
          if @lower.node_input_count(node) == 0 {
            values_roots += 1
          }
        }
        _ => ()
      }
      if @carrier.kind(@lower.node_output_carrier(node)) !=
        @carrier.RelationKind {
        relation_only = false
        for input in 0..<@lower.node_input_count(node) {
          if @lower.node_input_target(node, input)
            is Some(@pipeline.Step(producer)) &&
            @lower.preparation_carrier_at(prepared, @pipeline.Step(producer))
            is Some(source) &&
            @carrier.kind(source) == @carrier.RelationKind {
            carrier_construction = true
          }
        }
      }
      if @lower.preparation_carrier_at(prepared, @pipeline.Step(step))
        is Some(output) &&
        @carrier.kind(output) == @carrier.RelationKind {
        for input in 0..<@lower.node_input_count(node) {
          match @lower.node_input_target(node, input) {
            Some(@pipeline.Step(producer)) =>
              if @lower.preparation_carrier_at(
                  prepared,
                  @pipeline.Step(producer),
                )
                is Some(source) &&
                @carrier.kind(source) != @carrier.RelationKind {
                carrier_relation_consumer = true
              }
            _ => ()
          }
        }
      }
    }
    // Independent Values roots cannot be realized as one linear pipeline.
    // Let a Relation-only DAG reach the existing selected-provider and exact
    // per-edge checks below; root count alone never authorizes a split.
    let independent_relations = relation_only && values_roots > 1
    // A source-free Carrier prefix needs segmentation when a later typed
    // Carrier-to-Relation step or an intermediate Result needs independent
    // ownership. Carrier-only prefixes without either retain fused execution.
    if !values_source ||
      (
        !independent_relations &&
        (
          (!carrier_construction && !intermediate_result) ||
          (!carrier_relation_consumer && !intermediate_result)
        )
      ) {
      return None
    }
  }
  if count < 2 {
    return None
  }
  // The registered family child and bounded row suffix share one chain owner.
  // Carrier-valued inputs and intermediate Result roots still use segmentation.
  if bounded_family_relation_chain(graph, stage) {
    return None
  }
  let mut found_carrier = false
  let mut found_relation = false
  let mut found_zero_input = false
  let mut zero_input_count = 0
  let mut found_binary = false
  let mut found_external_input = false
  let mut prefer_fused_without_relation = false
  let mut all_selected = true
  for step in 0..<count {
    guard @lower.node_at(prepared, step) is Some(node) else { return None }
    if !@lower.node_supports_selected_managed_execution(node) {
      all_selected = false
      break
    }
    if @lower.node_input_count(node) == 0 {
      found_zero_input = true
      zero_input_count += 1
    } else if @lower.node_input_count(node) == 2 {
      found_binary = true
    }
    if stage != 0 &&
      @lower.operation(node) == "BRIDGE.rows.to_graph" &&
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
    // A graph constructed in this Stage and a separately supplied start
    // Relation still belong to the fused traversal task. Splitting here
    // would request a Graph output that the existing task never retained.
    if @lower.operation(node) == "SGA.traverse" &&
      @lower.node_input_count(node) == 2 &&
      @lower.node_input_target(node, 0) is Some(@pipeline.Step(_)) &&
      @lower.node_input_target(node, 1) is Some(@pipeline.Input(_)) {
      return None
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
        Some(@pipeline.Input(_)) => found_external_input = true
        None => return None
      }
    }
  }
  if all_selected &&
    found_carrier &&
    (!prefer_fused_without_relation || found_relation) {
    return Some(-1)
  }
  // A retained intermediate Relation Result needs its own exact output.
  // Use the same checked managed-view handoff as Carrier consumers, only
  // when every occurrence has a registered selected execution capability.
  // A captured predecessor is already an owned Result; splitting its
  // consumer does not split or repeat the physical source acquisition.
  if intermediate_result && all_selected && found_relation && !found_carrier {
    if found_zero_input && !found_external_input {
      return Some(-1)
    }
    guard @lower.node_at(prepared, 0) is Some(first) else { return None }
    // A registered unary consumer or binary JOIN can start from retained
    // Relation ports. Prove every input separately, including two references
    // to the same producer; one valid port cannot authorize the other.
    let input_count = @lower.node_input_count(first)
    if input_count == 1 || input_count == 2 {
      let mut complete_inputs = true
      for input in 0..<input_count {
        if !@lower.node_accepts_managed_relation_view(first, input) {
          complete_inputs = false
          break
        }
        guard @lower.node_input_target(first, input)
          is Some(@pipeline.Input(source)) else {
          complete_inputs = false
          break
        }
        let mut retained_relation = false
        for edge in graph.data {
          if edge.consumer == stage &&
            edge.input == source &&
            edge.producer >= 0 &&
            edge.producer < graph.owners.length() {
            let predecessor = @lower.bound_preparation(
              graph.owners[edge.producer],
            )
            if @lower.preparation_carrier_at(predecessor, edge.target)
              is Some(carrier) &&
              @carrier.kind(carrier) == @carrier.RelationKind {
              retained_relation = true
            }
          }
        }
        if !retained_relation {
          complete_inputs = false
          break
        }
      }
      if complete_inputs {
        return Some(-1)
      }
    }
  }
  // A checked multi-source Relation DAG can use the same per-edge handoff
  // when every zero-input producer and binary consumer has a bounded provider.
  if all_selected && found_zero_input && found_binary && found_relation {
    return Some(-1)
  }
  // Independent zero-input branches need no external representation plan.
  // Split their exact internal Relation edges even without a binary join.
  if all_selected &&
    zero_input_count > 1 &&
    found_relation &&
    !found_external_input {
    return Some(-1)
  }
  // Exact supplied input and completed Relation edges can each select
  // independently owned Relation steps.
  if all_selected && found_relation && !found_carrier {
    guard @lower.node_at(prepared, 0) is Some(first) else { return None }
    if @lower.node_accepts_managed_relation_view(first, 0) &&
      @lower.node_input_count(first) == 1 &&
      @lower.node_input_target(first, 0) is Some(@pipeline.Input(source)) {
      if original_supplied_slot(graph, stage, source) is Some(_) {
        return Some(-1)
      }
      for edge in graph.data {
        if edge.consumer != stage ||
          edge.input != source ||
          edge.producer < 0 ||
          edge.producer >= graph.owners.length() {
          continue
        }
        if segmentable_relation_source(graph, edge.producer) {
          return Some(-1)
        }
      }
    }
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
  if suffix_start == count || suffix_start < 1 {
    return None
  }
  let terminal = suffix_start - 1
  guard @lower.preparation_carrier_at(prepared, @pipeline.Step(terminal))
    is Some(carrier) &&
    @carrier.kind(carrier) == @carrier.RelationKind else {
    return None
  }
  if terminal == 0 {
    // The prefix is independently bounded; its later Relation consumers can
    // be split without executing the whole authored sequence synchronously.
    guard @lower.node_at(prepared, 0) is Some(prefix) &&
      @lower.node_at(prepared, 1) is Some(consumer) &&
      @lower.node_supports_bounded_managed_prefix(prefix, consumer) else {
      return None
    }
    // A linear Cross Join followed by supported row projections has a
    // bounded whole-task owner. Keep its checked operation occurrences in
    // that task so the retained output uses the same chain completion.
    if @lower.payload(prefix) is @lower.CrossJoinRows(_) {
      let mut row_suffix = true
      for step in 1..<count {
        guard @lower.node_at(prepared, step) is Some(node) else { return None }
        match @lower.payload(node) {
          @lower.Where(_) | @lower.Derive(_) | @lower.Select(_) => ()
          _ => row_suffix = false
        }
      }
      if row_suffix {
        return None
      }
    }
  } else {
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
