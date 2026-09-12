///|
pub(all) struct IncomingLimits {
  max_work : Int
  max_name_units : Int
  max_requirements : Int
} derive(Eq, Debug)

///|
pub(all) enum IncomingIssue {
  InvalidLimits
  BudgetExceeded
  InconsistentSource
  MissingProducer(Int, String)
  MissingResult(Int, String)
} derive(Eq, Debug)

///|
pub(all) enum IncomingMilestone {
  Accepted
  Completed
} derive(Eq, Debug)

///|
/// Requirements, not proof of successful execution or admitted receipts.
pub enum IncomingRequirement {
  Success(IncomingMilestone, StageSourceIdentity)
  Result(String, StageSourceIdentity, @stage_results.ResultImport)
  Receipt(String, String, StageSourceIdentity)
}

///|
pub struct IncomingSite {
  stage : Int
  consumer : StageSourceIdentity
  requirement : IncomingRequirement
}

///|
struct ProgramIncomingRequirements {
  identity : ProgramSourceIdentity
  wiring : @stage_results.ResultWiring
  entries : Array[IncomingSite]
  work : Int
  name_units : Int
}

///|
priv struct IncomingBudget {
  mut work : Int
  mut names : Int
  mut entries : Int
}

///|
priv suberror IncomingStop {
  IncomingStop(IncomingIssue)
}

///|
fn incoming_work(b : IncomingBudget, n : Int) -> Unit raise IncomingStop {
  if n > b.work {
    raise IncomingStop(BudgetExceeded)
  }
  b.work -= n
}

///|
fn incoming_name(b : IncomingBudget, name : String) -> Unit raise IncomingStop {
  if name.length() > b.names {
    raise IncomingStop(BudgetExceeded)
  }
  incoming_work(b, name.length())
  b.names -= name.length()
}

///|
fn incoming_producer(
  known : Map[String, StageSourceIdentity],
  name : String,
  index : Int,
  b : IncomingBudget,
) -> StageSourceIdentity raise IncomingStop {
  incoming_name(b, name)
  match known.get(name) {
    Some(v) => v
    None => raise IncomingStop(MissingProducer(index, name))
  }
}

///|
fn incoming_push(
  out : Array[IncomingSite],
  b : IncomingBudget,
  stage : Int,
  consumer : StageSourceIdentity,
  requirement : IncomingRequirement,
) -> Unit raise IncomingStop {
  incoming_work(b, 1)
  if b.entries == 0 {
    raise IncomingStop(BudgetExceeded)
  }
  b.entries -= 1
  out.push({ stage, consumer, requirement, })
}

///|
/// Derive every incoming requirement from this exact source and Result wiring.
/// Does not issue a Unit CID or fill missing Effect/receipt contracts with {}.
pub fn collect_program_incoming(
  identity : ProgramSourceIdentity,
  limits : IncomingLimits,
) -> Result[ProgramIncomingRequirements, IncomingIssue] {
  if limits.max_work < 0 ||
    limits.max_name_units < 0 ||
    limits.max_requirements < 0 {
    return Err(InvalidLimits)
  }
  if identity.work > limits.max_work {
    return Err(BudgetExceeded)
  }
  let wired = identity.sources.operations.preparation.sources.capacity.context.rows.requests.inputs.wired
  let wiring = wired.wiring
  let source = @stage_results.wiring_source(wiring)
  let source_owner = @stages.operations_source(
    @stages.bound_operations(identity.sources.references.stages.operations),
  )
  if !physical_equal(source, source_owner) ||
    identity.stages.length() != @stages.stage_count(source) {
    return Err(InconsistentSource)
  }
  let b = {
    work: limits.max_work - identity.work,
    names: limits.max_name_units,
    entries: limits.max_requirements,
  }
  try {
    incoming_work(b, 1)
    incoming_name(b, @stages.program(source).id)
    let known : Map[String, StageSourceIdentity] = Map([])
    let entries = []
    for i in 0..<identity.stages.length() {
      incoming_work(b, 1)
      let consumer = identity.stages[i]
      let stage = @stages.stage_at(source, i).unwrap()
      incoming_name(b, stage.id)
      match stage.predecessor {
        @syntax.Initial => ()
        @syntax.Accepted(name) =>
          incoming_push(
            entries,
            b,
            i,
            consumer,
            Success(Accepted, incoming_producer(known, name, i, b)),
          )
        @syntax.Completed(name) =>
          incoming_push(
            entries,
            b,
            i,
            consumer,
            Success(Completed, incoming_producer(known, name, i, b)),
          )
      }
      let imports = @stage_results.attached_imports(
        @stage_results.wiring_imports_at(wiring, i).unwrap(),
      )
      let n = @stage_results.import_count(imports)
      incoming_work(b, n)
      let ports : Map[String, @stage_results.ResultImport] = Map([])
      for j in 0..<n {
        let port = @stage_results.import_at(imports, j).unwrap()
        let name = @stage_results.input_name(port)
        incoming_name(b, name)
        ports[name] = port
      }
      incoming_work(b, @syntax.import_count(stage))
      for j in 0..<@syntax.import_count(stage) {
        let (name, reference) = @syntax.import_at(stage, j).unwrap()
        incoming_name(b, name)
        match reference {
          @syntax.Result(producer~, result~) => {
            let owner = incoming_producer(known, producer, i, b)
            incoming_name(b, result)
            let port = match ports.get(name) {
              Some(v) => v
              None => raise IncomingStop(MissingResult(i, name))
            }
            let actual = @stage_results.input_stage(port)
            let actual_index = @stages.stage_index(
              @stage_results.stage_port_source(actual),
            )
            let expected_index = @program_refs.stage_semantics_index(
              @program_refs.stage_definition_semantics(owner.definition),
            )
            let actual_name = @results.name(
              @results.port_result(@stage_results.input_port(port)),
            )
            incoming_name(b, actual_name)
            let expected = @stage_results.wiring_stage_at(
              wiring, expected_index,
            ).unwrap()
            if actual_index != expected_index ||
              actual_name != result ||
              !physical_equal(
                @stage_results.stage_port_source(actual),
                @stage_results.stage_port_source(expected),
              ) ||
              !physical_equal(
                @stage_results.stage_port_publications(actual),
                @stage_results.stage_port_publications(expected),
              ) {
              raise IncomingStop(MissingResult(i, name))
            }
            incoming_push(entries, b, i, consumer, Result(name, owner, port))
          }
          @syntax.Receipt(producer~, effect~) => {
            let owner = incoming_producer(known, producer, i, b)
            incoming_name(b, effect)
            incoming_push(entries, b, i, consumer, Receipt(name, effect, owner))
          }
        }
      }
      known[stage.id] = consumer
    }
    Ok({
      identity,
      wiring,
      entries,
      work: limits.max_work - b.work,
      name_units: limits.max_name_units - b.names,
    })
  } catch {
    IncomingStop(e) => Err(e)
  }
}

///|
pub fn program_incoming_identity(
  v : ProgramIncomingRequirements,
) -> ProgramSourceIdentity {
  v.identity
}

///|
pub fn program_incoming_wiring(
  v : ProgramIncomingRequirements,
) -> @stage_results.ResultWiring {
  v.wiring
}

///|
pub fn program_incoming_count(v : ProgramIncomingRequirements) -> Int {
  v.entries.length()
}

///|
pub fn program_incoming_at(
  v : ProgramIncomingRequirements,
  index : Int,
) -> IncomingSite? {
  v.entries.get(index)
}

///|
pub fn program_incoming_usage(v : ProgramIncomingRequirements) -> (Int, Int) {
  (v.work, v.name_units)
}

///|
/// Typed namespace pair; never concatenate IDs or substitute a parent CID.
pub fn program_incoming_namespace(
  v : ProgramIncomingRequirements,
  stage : Int,
) -> (String, String)? {
  v.identity.stages
  .get(stage)
  .map(s => {
    (
      @program_refs.program_definition_id(v.identity.definition),
      @program_refs.stage_definition_id(s.definition),
    )
  })
}
