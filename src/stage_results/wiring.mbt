///|
pub(all) struct WiringLimits {
  max_work : Int
  max_text_bytes : Int
  max_imports : Int
  max_exports : Int
} derive(Eq, Debug)

///|
pub(all) enum WiringIssue {
  InvalidLimits
  StageCountMismatch
  ForeignStage(Int)
  ForeignProducer(Int, String)
  UnknownExport(String, String)
  BudgetExceeded
} derive(Eq, Debug)

///|
struct ResultExport {
  name : String
  producer : StagePorts
  port : @results.ResultPort
}

///|
struct ResultWiring {
  source : @parameters.Source
  stages : Array[StagePorts]
  imports : Array[AttachedImports]
  exports : Array[ResultExport]
  work : Int
  text_bytes : Int
}

///|
/// Close all stage Result edges and root exports, not ordinary/receipt Inputs
/// or full Program semantics. Earlier parsing and operation admission are separate.
pub fn wire_results(
  source : @parameters.Source,
  stages : Array[StagePorts],
  imports : Array[AttachedImports],
  limits : WiringLimits,
) -> Result[ResultWiring, WiringIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_imports < 0 ||
    limits.max_exports < 0 {
    return Err(InvalidLimits)
  }
  let count = @parameters.stage_count(source)
  if stages.length() != count || imports.length() != count {
    return Err(StageCountMismatch)
  }
  let program = @parameters.program(source)
  let exports = @syntax.export_count(program)
  if count > limits.max_work || exports > limits.max_exports {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work - count
  let mut text = limits.max_text_bytes
  let mut left = limits.max_imports
  let retained_stages : Array[StagePorts] = []
  let retained_imports = []
  let known : Map[String, StagePorts] = Map([])
  for i in 0..<count {
    let owner = stages[i]
    let attached = imports[i]
    if !physical_equal(@parameters.source(owner.stage), source) ||
      @parameters.stage_index(owner.stage) != i ||
      !physical_equal(attached.stage, owner.stage) {
      return Err(ForeignStage(i))
    }
    let ports_used = @results.ports_usage(owner.ports)
    // Subtract independently to avoid overflow in aggregate counters.
    for amount in [ports_used.work, attached.work] {
      if amount > work {
        return Err(BudgetExceeded)
      }
      work -= amount
    }
    for amount in [ports_used.text_bytes, attached.imports.text_bytes] {
      if amount > text {
        return Err(BudgetExceeded)
      }
      text -= amount
    }
    let entries = attached.imports.entries
    if entries.length() > left || entries.length() > work {
      return Err(BudgetExceeded)
    }
    left -= entries.length()
    work -= entries.length()
    for entry in entries {
      let earlier = @parameters.stage_index(entry.producer.stage)
      if earlier >= i {
        return Err(ForeignProducer(i, entry.name))
      }
      let expected = retained_stages[earlier]
      if !physical_equal(entry.producer.stage, expected.stage) ||
        !physical_equal(entry.producer.ports, expected.ports) {
        return Err(ForeignProducer(i, entry.name))
      }
    }
    let name = @parameters.stage_at(source, i).unwrap().id
    match @scalar.admit_utf8_length(name, text) {
      Err(_) => return Err(BudgetExceeded)
      Ok(n) => text -= n
    }
    known[name] = owner
    retained_stages.push(owner)
    retained_imports.push(attached)
  }
  if exports > work {
    return Err(BudgetExceeded)
  }
  work -= exports
  let retained_exports : Array[ResultExport] = []
  for i in 0..<exports {
    let (name, stage, result) = @syntax.export_at(program, i).unwrap()
    for value in [name, stage, result] {
      match @scalar.admit_utf8_length(value, text) {
        Err(_) => return Err(BudgetExceeded)
        Ok(n) => text -= n
      }
    }
    let producer = match known.get(stage) {
      None => return Err(UnknownExport(stage, result))
      Some(v) => v
    }
    let port = match @results.lookup_port(producer.ports, result) {
      None => return Err(UnknownExport(stage, result))
      Some(v) => v
    }
    retained_exports.push({ name, producer, port, })
  }
  Ok({
    source,
    stages: retained_stages,
    imports: retained_imports,
    exports: retained_exports,
    work: limits.max_work - work,
    text_bytes: limits.max_text_bytes - text,
  })
}

///|
pub fn wiring_source(value : ResultWiring) -> @parameters.Source {
  value.source
}

///|
pub fn wiring_stage_at(value : ResultWiring, index : Int) -> StagePorts? {
  value.stages.get(index)
}

///|
pub fn wiring_imports_at(value : ResultWiring, index : Int) -> AttachedImports? {
  value.imports.get(index)
}

///|
pub fn wiring_usage(value : ResultWiring) -> (Int, Int) {
  (value.work, value.text_bytes)
}

///|
pub fn export_count(value : ResultWiring) -> Int {
  value.exports.length()
}

///|
pub fn export_at(value : ResultWiring, index : Int) -> ResultExport? {
  value.exports.get(index)
}

///|
pub fn export_name(value : ResultExport) -> String {
  value.name
}

///|
pub fn export_stage(value : ResultExport) -> StagePorts {
  value.producer
}

///|
pub fn export_port(value : ResultExport) -> @results.ResultPort {
  value.port
}
