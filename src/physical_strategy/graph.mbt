///|
/// Derived from owned checked ports, never supplied as an alternative Plan.
pub struct DataEdge {
  producer : Int
  target : @pipeline.Target
  consumer : Int
  input : Int
  source_input : Int?
  operation_input : (Int, Int)?
}

///|
pub struct ControlEdge {
  predecessor : Int
  consumer : Int
  gate : @context.PreparedIncomingGate
}

///|
/// One checked Local input position. It has no producer task and must be
/// supplied by the Host under the exact bound preparation before execution.
priv struct LocalInputSlot {
  consumer : Int
  input : Int
  source_input : Int
  operation_input : (Int, Int)?
}

///|
struct CheckedDAG {
  program : @checked.CheckedProgram
  source_free_root : Bool
  owners : Array[@lower.BoundPrepared]
  targets : Array[@pipeline.Target?]
  input_counts : Array[Int]
  selected_steps : Array[Int?]
  data : Array[DataEdge]
  supplied_slots : Array[LocalInputSlot]
  control : Array[ControlEdge]
  operations : Array[Array[TaskOperationRequirement]]
  numeric : Array[Array[TaskNumericObservation]]
  results : Array[CheckedResultOccurrence]
}

///|
/// A physical computation graph paired with its exact checked Effect closure.
/// The graph accessor supplies computation only; it never discharges Preview
/// or apply obligations or turns this Program into an Effect-free Run.
pub struct CheckedEffectComputationDAG {
  candidate : @checked.EffectProgramStaticCandidate
  graph : CheckedDAG
}

///|
pub fn prepare_checked_effect_computation_dag(
  candidate : @checked.EffectProgramStaticCandidate,
  owners : Array[@lower.BoundPrepared],
  max_tasks : Int,
  max_work : Int,
) -> Result[CheckedEffectComputationDAG, GraphIssue] {
  match
    prepare_checked_dag(
      @checked.effect_program_static_checked_computation(candidate),
      owners,
      max_tasks,
      max_work,
    ) {
    Ok(graph) => Ok({ candidate, graph, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn checked_effect_computation_graph(
  value : CheckedEffectComputationDAG,
) -> CheckedDAG {
  value.graph
}

///|
pub fn checked_effect_computation_owner(
  value : CheckedEffectComputationDAG,
) -> @checked.EffectProgramStaticCandidate {
  value.candidate
}

///|
pub fn graph_program_has_effects(graph : CheckedDAG) -> Bool {
  @checked.checked_program_has_effects(graph.program)
}

///|
/// Exact checked root export. An authored alias and its ResultPort form one
/// publication occurrence; graph terminality is not publication evidence.
priv struct CheckedResultOccurrence {
  task : Int
  occurrence : @execution.ManagedResultOccurrence
}

///|
/// Original checked occurrence and disposition. This is not an execution
/// receipt: every ExecutionCheck must be supported by the chosen connector.
pub struct TaskOperationRequirement {
  site : @context.OperationRequirementSite
  disposition : @context.OperationDisposition
}

///|
pub(all) enum NumericObservationFamily {
  Group
  WindowGroup
  Pivot
  Analytic
} derive(Eq, Debug)

///|
priv enum NumericObservationOwner {
  GroupOwner(@checked.GroupNumericSlot)
  PivotOwner(@checked.PivotNumericSlot)
  AnalyticOwner(@checked.AnalyticNumericSlot)
}

///|
/// Producer-owned static slot projected into the execution DAG. This is not a
/// selected reduction member, an attempt binding, or captured observation.
struct TaskNumericObservation {
  step : Int
  name : String
  slot_cid : String
  profile : @numeric.Profile
  operation : @numeric.Operation
  family : NumericObservationFamily
  owner : NumericObservationOwner
}

///|
pub(all) enum GraphIssue {
  InvalidLimits
  TaskLimit
  WorkLimit
  ForeignPipeline(Int)
  ForeignParameters(Int)
  ForeignControl(Int)
  MissingProducer(Int, Int)
  ForeignPort(Int, Int)
  UnsupportedIncoming(Int)
  NonDAG(Int)
  ForeignRequirement(Int)
} derive(Eq, Debug)

///|
/// Complete ordered unit inventory. The supplied preparations must belong to
/// this exact CheckedProgram, including Parameter ownership. Semantic control
/// edges are read from owned success gates, not inferred from stage numbering.
/// Serial order is a valid topological order only after both edge kinds pass.
pub fn prepare_checked_dag(
  program : @checked.CheckedProgram,
  owners : Array[@lower.BoundPrepared],
  max_tasks : Int,
  max_work : Int,
  source_free_root? : Bool = false,
) -> Result[CheckedDAG, GraphIssue] {
  if max_tasks < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = @checked.unit_count(program)
  if count > max_tasks || owners.length() != count {
    return Err(TaskLimit)
  }
  if source_free_root &&
    (
      count == 0 ||
      @pipeline.input_count(
        @lower.pipeline(@lower.bound_preparation(owners[0])),
      ) !=
      0 ||
      !@pipeline.starts_with_values(
        @lower.pipeline(@lower.bound_preparation(owners[0])),
      )
    ) {
    return Err(UnsupportedIncoming(0))
  }
  if count > max_work {
    return Err(WorkLimit)
  }
  let mut work = max_work - count
  let identity = @checked.source_identity(program)
  let gates = @checked.incoming_gates(program)
  let incoming = @context.incoming_links_requirements(
    @context.program_incoming_gates_owner(gates),
  )
  if !physical_equal(@context.program_incoming_identity(incoming), identity) ||
    @context.program_identity_stage_count(identity) != count ||
    @context.program_incoming_gates_stage_count(gates) != count {
    return Err(ForeignControl(0))
  }
  let stages = []
  let incoming_count = @context.program_incoming_count(incoming)
  if incoming_count > work {
    return Err(WorkLimit)
  }
  work -= incoming_count
  for index in 0..<incoming_count {
    let site = @context.program_incoming_at(incoming, index).unwrap()
    if site.requirement is @context.Receipt(_, _, _) {
      return Err(UnsupportedIncoming(site.stage))
    }
  }
  for stage in 0..<count {
    guard @checked.unit_pipeline(program, stage) is Some(pipeline) &&
      physical_equal(
        @lower.pipeline(@lower.bound_preparation(owners[stage])),
        pipeline,
      ) else {
      return Err(ForeignPipeline(stage))
    }
    guard @context.program_identity_stage_at(identity, stage) is Some(source) else {
      return Err(ForeignControl(stage))
    }
    let parameters = @parameters.bound_values(
      @context.stage_identity_parameter_values(source),
    )
    match @lower.parameter_bindings(owners[stage]) {
      Some(actual) =>
        if !physical_equal(actual, parameters) {
          return Err(ForeignParameters(stage))
        }
      None =>
        if @binding.bound_value_count(parameters) != 0 {
          return Err(ForeignParameters(stage))
        }
    }
    stages.push(source)
  }
  let data = []
  let supplied_slots = []
  let control = []
  for stage in 0..<count {
    let gate_count = @context.program_incoming_gates_count(gates, stage).unwrap()
    if gate_count > work {
      return Err(WorkLimit)
    }
    work -= gate_count
    for index in 0..<gate_count {
      let gate = @context.program_incoming_gates_at(gates, stage, index).unwrap()
      let check = @context.incoming_gate_check(gate)
      guard check.site.stage == stage &&
        physical_equal(check.site.consumer, stages[stage]) &&
        check.kind is @context.StageSuccess(milestone) &&
        check.site.requirement is @context.Success(required, predecessor) &&
        milestone == required else {
        return Err(ForeignControl(stage))
      }
      let mut found = None
      for candidate in 0..<count {
        if work == 0 {
          return Err(WorkLimit)
        }
        work -= 1
        if physical_equal(stages[candidate], predecessor) {
          found = Some(candidate)
          break
        }
      }
      guard found is Some(predecessor) else {
        return Err(ForeignControl(stage))
      }
      if predecessor >= stage {
        return Err(NonDAG(stage))
      }
      control.push({ predecessor, consumer: stage, gate, })
    }
    let pipeline = @checked.unit_pipeline(program, stage).unwrap()
    let imports = @checked.unit_result_import_count(program, stage).unwrap()
    if imports > work {
      return Err(WorkLimit)
    }
    work -= imports
    for index in 0..<imports {
      let imported = @checked.unit_result_import_at(program, stage, index).unwrap()
      let site = @context.result_import_type_site(imported.row)
      guard site.stage == stage &&
        physical_equal(site.consumer, stages[stage]) &&
        site.requirement is @context.Result(name, predecessor, port) &&
        name == imported.input_name else {
        return Err(ForeignPort(stage, index))
      }
      let producer = @results.input_producer(port)
      let mut source = None
      for candidate in 0..<count {
        if work == 0 {
          return Err(WorkLimit)
        }
        work -= 1
        if physical_equal(stages[candidate], predecessor) {
          if !physical_equal(
              @pipeline.producer_pipeline(producer),
              @checked.unit_pipeline(program, candidate).unwrap(),
            ) {
            return Err(ForeignPort(stage, index))
          }
          source = Some(candidate)
          break
        }
      }
      guard source is Some(source) else {
        return Err(MissingProducer(stage, index))
      }
      if source >= stage {
        return Err(NonDAG(stage))
      }
      let mut input = None
      for candidate in 0..<@pipeline.input_count(pipeline) {
        if work == 0 {
          return Err(WorkLimit)
        }
        work -= 1
        if @pipeline.input_at(pipeline, candidate).map(pair => pair.0) ==
          Some(name) {
          guard @pipeline.input_producer(pipeline, candidate) is Some(actual) &&
            physical_equal(actual, producer) else {
            return Err(ForeignPort(stage, index))
          }
          input = Some(candidate)
          break
        }
      }
      guard input is Some(input) else { return Err(ForeignPort(stage, index)) }
      data.push({
        producer: source,
        target: @pipeline.producer_target(producer),
        consumer: stage,
        input,
        source_input: Some(input),
        operation_input: None,
      })
    }
    let input_count = @pipeline.input_count(pipeline)
    if input_count > work {
      return Err(WorkLimit)
    }
    work -= input_count
    for input in 0..<input_count {
      guard @checked.unit_input_completeness(program, stage, input)
        is Some(requirement) else {
        return Err(MissingProducer(stage, input))
      }
      if @checked.input_completeness_is_supplied(requirement) {
        supplied_slots.push({
          consumer: stage,
          input,
          source_input: input,
          operation_input: None,
        })
      }
    }
  }
  // Charge the snapshot copy before allocating; later caller array edits cannot
  // substitute another preparation for a validated unit.
  if count > work {
    return Err(WorkLimit)
  }
  work -= count
  let closure = @context.stage_requirement_operations(
    @checked.requirements(program),
  )
  let inventory = @context.operation_resolution_requirements(
    @context.operation_closure_index(closure),
  )
  let requirements = @context.operation_closure_count(closure)
  if requirements > work {
    return Err(WorkLimit)
  }
  let operations : Array[Array[TaskOperationRequirement]] = Array::makei(
    count,
    _ => [],
  )
  let numeric : Array[Array[TaskNumericObservation]] = Array::makei(count, _ => {
    []
  })
  for index in 0..<requirements {
    guard @context.operation_requirements_at(inventory, index) is Some(site) &&
      @context.operation_closure_at(closure, index) is Some(disposition) &&
      @context.program_identity_producer_is_local(
        identity,
        site.stage,
        site.producer_visit,
      )
      is Some(is_local) else {
      return Err(ForeignRequirement(index))
    }
    // Prerequisite visits validate imported producers; they do not execute
    // again in the importing Unit. The frontend owns this correspondence.
    if !is_local {
      continue
    }
    guard @checked.unit_pipeline(program, site.stage) is Some(pipeline) &&
      physical_equal(site.pipeline, pipeline) &&
      @pipeline.step_at(pipeline, site.step) is Some(_) else {
      return Err(ForeignRequirement(index))
    }
    operations[site.stage].push({ site, disposition, })
    if @checked.numeric_slot_for_requirement(program, index) is Some(slot) {
      let demand = @checked.group_numeric_slot_demand(slot)
      guard disposition is ExecutionCheck(GroupExecution(check)) &&
        check.rule is CaptureNumericObservation(retained) &&
        physical_equal(retained, demand) &&
        retained.requirement_index == index else {
        return Err(ForeignRequirement(index))
      }
      if work == 0 {
        return Err(WorkLimit)
      }
      work -= 1
      guard @checked.group_numeric_slot_reduction(slot) is Some(operation) else {
        return Err(ForeignRequirement(index))
      }
      numeric[site.stage].push({
        step: site.step,
        name: @checked.group_numeric_slot_name(slot),
        slot_cid: @checked.group_numeric_slot_cid(slot),
        profile: retained.profile,
        operation,
        family: if @checked.group_numeric_slot_is_window_group(slot) {
          WindowGroup
        } else {
          Group
        },
        owner: GroupOwner(slot),
      })
    }
    if @checked.analytic_numeric_slot_for_requirement(program, index)
      is Some(slot) {
      let demand = @checked.analytic_numeric_slot_demand(slot)
      guard disposition is ExecutionCheck(AnalyticExecution(check)) &&
        check.rule is CaptureNumericObservation(retained) &&
        physical_equal(retained, demand) &&
        retained.requirement_index == index else {
        return Err(ForeignRequirement(index))
      }
      if work == 0 {
        return Err(WorkLimit)
      }
      work -= 1
      guard @checked.analytic_numeric_slot_reduction(slot) is Some(operation) else {
        return Err(ForeignRequirement(index))
      }
      numeric[site.stage].push({
        step: site.step,
        name: @checked.analytic_numeric_slot_name(slot),
        slot_cid: @checked.analytic_numeric_slot_cid(slot),
        profile: retained.profile,
        operation,
        family: Analytic,
        owner: AnalyticOwner(slot),
      })
    }
    if @checked.pivot_numeric_slots_for_requirement(program, index)
      is Some(slots) {
      let demand = @checked.pivot_numeric_slots_demand(slots)
      guard disposition is ExecutionCheck(PivotExecution(check)) &&
        check.rule is CaptureNumericObservations(retained) &&
        physical_equal(retained, demand) &&
        retained.requirement_index == index else {
        return Err(ForeignRequirement(index))
      }
      let slot_count = @checked.pivot_numeric_slot_count(slots)
      if slot_count > work {
        return Err(WorkLimit)
      }
      work -= slot_count
      for position in 0..<slot_count {
        let slot = @checked.pivot_numeric_slot_at(slots, position).unwrap()
        guard @checked.pivot_numeric_slot_reduction(slot) is Some(operation) else {
          return Err(ForeignRequirement(index))
        }
        numeric[site.stage].push({
          step: site.step,
          name: @checked.pivot_numeric_slot_name(slot),
          slot_cid: @checked.pivot_numeric_slot_cid(slot),
          profile: retained.profile,
          operation,
          family: Pivot,
          owner: PivotOwner(slot),
        })
      }
    }
  }
  let wiring = @context.program_incoming_wiring(incoming)
  let results : Array[CheckedResultOccurrence] = []
  for index in 0..<@results.export_count(wiring) {
    let result_export = @results.export_at(wiring, index).unwrap()
    let task = @stages.stage_index(
      @results.stage_port_source(@results.export_stage(result_export)),
    )
    guard owners.get(task) is Some(owner) else {
      return Err(ForeignPort(task, index))
    }
    let occurrence = match
      @execution.bind_managed_result_occurrence(
        owner,
        @results.export_name(result_export),
        @results.export_port(result_export),
      ) {
      Ok(value) => value
      Err(_) => return Err(ForeignPort(task, index))
    }
    results.push({ task, occurrence, })
  }
  let logical : CheckedDAG = {
    program,
    source_free_root,
    owners: owners.copy(),
    targets: Array::makei(count, task => {
      let pipeline = @lower.pipeline(@lower.bound_preparation(owners[task]))
      if (task == 0 && !source_free_root) || @pipeline.step_count(pipeline) == 0 {
        None
      } else {
        Some(@pipeline.Step(@pipeline.step_count(pipeline) - 1))
      }
    }),
    input_counts: Array::makei(count, task => {
      @pipeline.input_count(
        @lower.pipeline(@lower.bound_preparation(owners[task])),
      )
    }),
    selected_steps: Array::make(count, None),
    data,
    supplied_slots,
    control,
    operations,
    numeric,
    results,
  }
  expand_internal_carrier_tasks(logical, max_tasks, work)
}

///|
pub fn graph_task_operation_count(graph : CheckedDAG, task : Int) -> Int? {
  graph.operations.get(task).map(items => items.length())
}

///|
/// Only the Unit's local occurrences, retaining the exact frontend owners.
pub fn graph_task_operation_at(
  graph : CheckedDAG,
  task : Int,
  index : Int,
) -> TaskOperationRequirement? {
  graph.operations.get(task).bind(items => items.get(index))
}

///|
pub fn graph_task_numeric_observation_count(
  graph : CheckedDAG,
  task : Int,
) -> Int? {
  graph.numeric.get(task).map(items => items.length())
}

///|
pub fn graph_task_numeric_observation_at(
  graph : CheckedDAG,
  task : Int,
  index : Int,
) -> TaskNumericObservation? {
  graph.numeric.get(task).bind(items => items.get(index))
}

///|
pub fn task_numeric_observation_step(value : TaskNumericObservation) -> Int {
  value.step
}

///|
pub fn task_numeric_observation_name(value : TaskNumericObservation) -> String {
  value.name
}

///|
pub fn task_numeric_observation_slot_cid(
  value : TaskNumericObservation,
) -> String {
  value.slot_cid
}

///|
pub fn task_numeric_observation_profile(
  value : TaskNumericObservation,
) -> @numeric.Profile {
  value.profile
}

///|
pub fn task_numeric_observation_operation(
  value : TaskNumericObservation,
) -> @numeric.Operation {
  value.operation
}

///|
pub fn task_numeric_observation_family(
  value : TaskNumericObservation,
) -> NumericObservationFamily {
  value.family
}

///|
pub fn task_numeric_observation_same_owner(
  left : TaskNumericObservation,
  right : TaskNumericObservation,
) -> Bool {
  match (left.owner, right.owner) {
    (GroupOwner(a), GroupOwner(b)) => physical_equal(a, b)
    (PivotOwner(a), PivotOwner(b)) => physical_equal(a, b)
    (AnalyticOwner(a), AnalyticOwner(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
pub fn graph_program(graph : CheckedDAG) -> @checked.CheckedProgram {
  graph.program
}

///|
/// Exact identity of the admitted Program Definition. This is not a source
/// text hash and is never derived from a task or connector configuration.
pub fn graph_program_definition_cid(graph : CheckedDAG) -> String {
  @context.program_identity_definition_cid(
    @checked.source_identity(graph.program),
  )
}

///|
/// Complete checked root Result inventory, including distinct authored aliases.
pub fn graph_result_count(graph : CheckedDAG) -> Int {
  graph.results.length()
}

///|
pub fn graph_result_task(graph : CheckedDAG, index : Int) -> Int? {
  graph.results.get(index).map(result => result.task)
}

///|
pub fn graph_result_name(graph : CheckedDAG, index : Int) -> String? {
  graph.results
  .get(index)
  .map(result => @execution.managed_result_occurrence_name(result.occurrence))
}

///|
/// Exact checked occurrence for common publication execution. This opaque
/// binding includes its Program owner and ResultPort; a name is insufficient.
pub fn graph_result_occurrence(
  graph : CheckedDAG,
  index : Int,
) -> @execution.ManagedResultOccurrence? {
  graph.results.get(index).map(result => result.occurrence)
}

///|
pub fn graph_task_count(graph : CheckedDAG) -> Int {
  graph.owners.length()
}

///|
pub fn graph_task_owner(
  graph : CheckedDAG,
  index : Int,
) -> @lower.BoundPrepared? {
  graph.owners.get(index)
}

///|
pub fn graph_task_target(graph : CheckedDAG, index : Int) -> @pipeline.Target? {
  graph.targets.get(index).bind(value => value)
}

///|
pub fn graph_task_input_count(graph : CheckedDAG, index : Int) -> Int? {
  graph.input_counts.get(index)
}

///|
pub fn graph_task_selected_step(graph : CheckedDAG, index : Int) -> Int? {
  graph.selected_steps.get(index).bind(value => value)
}

///|
pub fn graph_data_count(graph : CheckedDAG) -> Int {
  graph.data.length()
}

///|
pub fn graph_data_at(graph : CheckedDAG, index : Int) -> DataEdge? {
  graph.data.get(index)
}

///|
/// Original checked operation coordinate for an internal physical edge.
/// Author-visible pipeline inputs return none.
pub fn data_edge_operation_input(value : DataEdge) -> (Int, Int)? {
  value.operation_input
}

///|
pub fn graph_control_count(graph : CheckedDAG) -> Int {
  graph.control.length()
}

///|
pub fn graph_control_at(graph : CheckedDAG, index : Int) -> ControlEdge? {
  graph.control.get(index)
}
