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
  captured_prefix : Int
  owners : Array[@lower.BoundPrepared]
  stage_tasks : Array[Array[Int]]
  targets : Array[@pipeline.Target?]
  input_counts : Array[Int]
  selected_steps : Array[Int?]
  prefix_ends : Array[Int?]
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
struct CheckedEffectComputationDAG {
  candidate : @checked.EffectProgramStaticCandidate
  graph : CheckedDAG
  sources : Array[CheckedEffectSourcePort?]
}

///|
/// One authored Effect source bound to its exact checked Stage Result port.
/// This is static provenance, not a retained output or permission to read it.
struct CheckedEffectSourcePort {
  member_index : Int
  stage : Int
  task : Int
  occurrence : @execution.ManagedResultOccurrence
}

///|
/// The same computation graph retained with its exact admitted Run owner.
/// This is not a captured input, Preview, or Effect apply permit.
struct CheckedEffectRunDAG {
  computation : CheckedEffectComputationDAG
  run : @checked.EffectProgramRunCandidate
}

///|
pub fn prepare_checked_effect_computation_dag(
  candidate : @checked.EffectProgramStaticCandidate,
  owners : Array[@lower.BoundPrepared],
  max_tasks : Int,
  max_work : Int,
  source_free_root? : Bool = false,
) -> Result[CheckedEffectComputationDAG, GraphIssue] {
  let bindings = @results.effect_static_candidate_results(
    @checked.effect_program_static_effects(candidate),
  )
  let member_count = @results.effect_result_binding_count(bindings)
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if member_count > max_work {
    return Err(WorkLimit)
  }
  match
    prepare_checked_dag_owned(
      @checked.effect_program_static_checked_computation(candidate),
      owners,
      max_tasks,
      max_work - member_count,
      source_free_root~,
    ) {
    Ok(graph) => {
      let sources = match
        bind_checked_effect_source_ports(bindings, graph, owners) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Ok({ candidate, graph, sources, })
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Consume the checked Stage wiring rather than resolving a Result by name
/// against a caller-supplied or root-only inventory. One unit of graph work
/// was reserved for each member before this bounded pass.
fn bind_checked_effect_source_ports(
  bindings : @results.EffectResultBindings,
  graph : CheckedDAG,
  owners : Array[@lower.BoundPrepared],
) -> Result[Array[CheckedEffectSourcePort?], GraphIssue] {
  let incoming = @context.incoming_links_requirements(
    @context.program_incoming_gates_owner(
      @checked.incoming_gates(graph.program),
    ),
  )
  let wiring = @context.program_incoming_wiring(incoming)
  let sources : Array[CheckedEffectSourcePort?] = []
  for index in 0..<@results.effect_result_binding_count(bindings) {
    let binding = @results.effect_result_binding_at(bindings, index).unwrap()
    let header = @results.effect_result_binding_header(binding)
    let stage = @syntax.effect_header_stage(header)
    match @syntax.effect_header_source_result(header) {
      None => {
        if @results.effect_result_binding_result(binding) is Some(_) {
          return Err(ForeignEffectSource(index))
        }
        sources.push(None)
      }
      Some(name) => {
        guard @results.effect_result_binding_result(binding) is Some(result) &&
          @results.wiring_stage_at(wiring, stage) is Some(stage_ports) &&
          @ports.lookup_port(
            @results.stage_port_publications(stage_ports),
            name,
          )
          is Some(port) &&
          physical_equal(@ports.port_result(port), result) &&
          owners.get(stage) is Some(owner) else {
          return Err(ForeignEffectSource(index))
        }
        let occurrence = match
          @execution.bind_managed_result_occurrence(owner, name, port) {
          Ok(value) => value
          Err(_) => return Err(ForeignEffectSource(index))
        }
        let target = @ports.port_target(port)
        guard graph_stage_target_task(graph, stage, target) is Some(task) else {
          return Err(UnsupportedEffectSource(index))
        }
        guard graph.owners.get(task) is Some(task_owner) &&
          physical_equal(task_owner, owner) else {
          return Err(ForeignEffectSource(index))
        }
        sources.push(Some({ member_index: index, stage, task, occurrence, }))
      }
    }
  }
  Ok(sources)
}

///|
pub fn checked_effect_source_count(value : CheckedEffectComputationDAG) -> Int {
  value.sources.length()
}

///|
pub fn checked_effect_source_at(
  value : CheckedEffectComputationDAG,
  index : Int,
) -> CheckedEffectSourcePort? {
  value.sources.get(index).bind(source => source)
}

///|
pub fn checked_effect_source_member(value : CheckedEffectSourcePort) -> Int {
  value.member_index
}

///|
pub fn checked_effect_source_stage(value : CheckedEffectSourcePort) -> Int {
  value.stage
}

///|
pub fn checked_effect_source_occurrence(
  value : CheckedEffectSourcePort,
) -> @execution.ManagedResultOccurrence {
  value.occurrence
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
/// Keep the original checked Effect and Run owners together. A second static
/// candidate with equal CIDs cannot replace the graph's checked owner.
pub fn bind_checked_effect_run_dag(
  computation : CheckedEffectComputationDAG,
  run : @checked.EffectProgramRunCandidate,
) -> Result[CheckedEffectRunDAG, RunIssue] {
  if !physical_equal(
      computation.candidate,
      @checked.effect_program_run_static_candidate(run),
    ) {
    return Err(ForeignCandidate)
  }
  Ok({ computation, run, })
}

///|
pub fn checked_effect_run_graph(value : CheckedEffectRunDAG) -> CheckedDAG {
  value.computation.graph
}

///|
pub fn checked_effect_run_owner(
  value : CheckedEffectRunDAG,
) -> @checked.EffectProgramRunCandidate {
  value.run
}

///|
pub fn checked_effect_run_source_count(value : CheckedEffectRunDAG) -> Int {
  value.computation.sources.length()
}

///|
pub fn checked_effect_run_source_at(
  value : CheckedEffectRunDAG,
  index : Int,
) -> CheckedEffectSourcePort? {
  value.computation.sources.get(index).bind(source => source)
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
  EffectGraphOwnerRequired
  ForeignEffectSource(Int)
  UnsupportedEffectSource(Int)
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
  captured_prefix? : Int = 1,
) -> Result[CheckedDAG, GraphIssue] {
  if @checked.checked_program_has_effects(program) {
    return Err(EffectGraphOwnerRequired)
  }
  prepare_checked_dag_owned(
    program,
    owners,
    max_tasks,
    max_work,
    source_free_root~,
    captured_prefix~,
  )
}

///|
/// Shared physical preparation after the caller retains the appropriate
/// checked owner. This private entry cannot discard an Effect owner.
fn prepare_checked_dag_owned(
  program : @checked.CheckedProgram,
  owners : Array[@lower.BoundPrepared],
  max_tasks : Int,
  max_work : Int,
  source_free_root? : Bool = false,
  captured_prefix? : Int = 1,
) -> Result[CheckedDAG, GraphIssue] {
  if max_tasks < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = @checked.unit_count(program)
  if captured_prefix != 1 && captured_prefix != 2 {
    return Err(InvalidLimits)
  }
  if source_free_root && captured_prefix != 1 {
    return Err(InvalidLimits)
  }
  let captured_prefix = if source_free_root { 0 } else { captured_prefix }
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
  // This bounded increment admits exactly two independent acquisition Stages
  // at the beginning. It does not schedule acquisition/Compute interleaving.
  // Ordinary checked Stage-success ordering is preserved: the Host acquires
  // in prefix order, so source zero succeeds before source one may start.
  if captured_prefix == 2 {
    if count < 3 ||
      data.any(edge => edge.consumer < captured_prefix) ||
      supplied_slots.any(slot => slot.consumer < captured_prefix) {
      return Err(UnsupportedIncoming(0))
    }
    let source_checks = @checked.source_execution_count(program)
    if source_checks > work {
      return Err(WorkLimit)
    }
    work -= source_checks
    let acquisitions = Array::make(captured_prefix, 0)
    for index in 0..<source_checks {
      let check = @checked.source_execution_at(program, index).unwrap()
      let subject = @checked.source_execution_subject(check)
      if subject.stage < 0 || subject.stage >= captured_prefix {
        return Err(UnsupportedIncoming(subject.stage))
      }
      match @checked.source_execution_kind(check) {
        @checked.HostCombination => acquisitions[subject.stage] += 1
        @checked.KeyedRequest(_)
        | @checked.KeyedEgress(_)
        | @checked.KeyedResources(_)
        | @checked.KeyedResponse(_) =>
          return Err(UnsupportedIncoming(subject.stage))
        _ => ()
      }
    }
    for stage in 0..<captured_prefix {
      if acquisitions[stage] != 1 ||
        @pipeline.input_count(@checked.unit_pipeline(program, stage).unwrap()) !=
        1 {
        return Err(UnsupportedIncoming(stage))
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
    captured_prefix,
    owners: owners.copy(),
    stage_tasks: Array::makei(count, stage => [stage]),
    targets: Array::makei(count, task => {
      let pipeline = @lower.pipeline(@lower.bound_preparation(owners[task]))
      if task < captured_prefix || @pipeline.step_count(pipeline) == 0 {
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
    prefix_ends: Array::make(count, None),
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
/// Checked Unit indices follow authored Stages; physical tasks may split a
/// Unit into several bounded operations and therefore have different indices.
pub fn graph_task_unit_index(graph : CheckedDAG, task : Int) -> Int? {
  if task < 0 || task >= graph.owners.length() {
    return None
  }
  for stage, tasks in graph.stage_tasks {
    if tasks.contains(task) {
      return Some(stage)
    }
  }
  None
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
/// Terminal checked step of a fused prefix retained as one physical task.
pub fn graph_task_prefix_end(graph : CheckedDAG, index : Int) -> Int? {
  graph.prefix_ends.get(index).bind(value => value)
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
pub fn data_edge_producer(value : DataEdge) -> Int {
  value.producer
}

///|
pub fn data_edge_consumer(value : DataEdge) -> Int {
  value.consumer
}

///|
pub fn data_edge_input(value : DataEdge) -> Int {
  value.input
}

///|
pub fn graph_control_count(graph : CheckedDAG) -> Int {
  graph.control.length()
}

///|
pub fn graph_control_at(graph : CheckedDAG, index : Int) -> ControlEdge? {
  graph.control.get(index)
}

///|
/// The physical producer task may differ from the authored Stage when a
/// mixed Carrier sequence has been split into independently owned tasks.
pub fn checked_effect_source_task(value : CheckedEffectSourcePort) -> Int {
  value.task
}

///|
/// Resolve a checked Stage target to its physical producer task. A split
/// Carrier sequence retains the authored Stage but moves each Step to its
/// own task; callers must still present the exact checked Result occurrence
/// before they can borrow the output.
pub fn graph_stage_target_task(
  graph : CheckedDAG,
  stage : Int,
  target : @pipeline.Target,
) -> Int? {
  guard mapped_stage_target(graph.stage_tasks, stage, target) is Some(task) &&
    graph.targets.get(task).bind(value => value) == Some(target) else {
    return None
  }
  Some(task)
}

///|
/// Number of checked acquisition tasks preceding all Compute tasks.
/// The two-source profile never expands or interleaves its acquisition Stages.
pub fn graph_captured_prefix(graph : CheckedDAG) -> Int {
  graph.captured_prefix
}
