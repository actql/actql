///|
/// Derived from owned checked ports, never supplied as an alternative Plan.
pub struct DataEdge {
  producer : Int
  target : @pipeline.Target
  consumer : Int
  input : Int
}

///|
pub struct ControlEdge {
  predecessor : Int
  consumer : Int
  gate : @context.PreparedIncomingGate
}

///|
struct CheckedDAG {
  program : @checked.CheckedProgram
  owners : Array[@lower.BoundPrepared]
  data : Array[DataEdge]
  control : Array[ControlEdge]
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
) -> Result[CheckedDAG, GraphIssue] {
  if max_tasks < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = @checked.unit_count(program)
  if count > max_tasks || owners.length() != count {
    return Err(TaskLimit)
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
      })
    }
  }
  // Charge the snapshot copy before allocating; later caller array edits cannot
  // substitute another preparation for a validated unit.
  if count > work {
    return Err(WorkLimit)
  }
  Ok({ program, owners: owners.copy(), data, control, })
}

///|
pub fn graph_program(graph : CheckedDAG) -> @checked.CheckedProgram {
  graph.program
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
pub fn graph_data_count(graph : CheckedDAG) -> Int {
  graph.data.length()
}

///|
pub fn graph_data_at(graph : CheckedDAG, index : Int) -> DataEdge? {
  graph.data.get(index)
}

///|
pub fn graph_control_count(graph : CheckedDAG) -> Int {
  graph.control.length()
}

///|
pub fn graph_control_at(graph : CheckedDAG, index : Int) -> ControlEdge? {
  graph.control.get(index)
}
