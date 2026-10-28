///|
struct CheckedStageTopology {
  stage : @parameters.CollectedStage
  results : @results.CheckedResultInputs
  contextual : @pipeline.ContextualClosure
  table_inputs : @results.CheckedTableInputs?
}

///|
struct CheckedTopologyImport {
  name : String
  producer : CheckedStageTopology
  input : @pipeline.ProducedInput
}

///|
struct CheckedTopologyImports {
  source : @parameters.Source
  index : Int
  entries : Array[CheckedTopologyImport]
  stage : @parameters.CollectedStage?
  work : Int
  text_bytes : Int
}

///|
struct CheckedTopologyExport {
  name : String
  producer : CheckedStageTopology
  input : @pipeline.ProducedInput
}

///|
/// Conditional static topology. It cannot be passed to the publication binder.
/// Original pipelines/projections retain value and profile obligations; named
/// Result declarations retain their unresolved publication-order obligations.
struct CheckedTopology {
  source : @parameters.Source
  stages : Array[CheckedStageTopology]
  imports : Array[CheckedTopologyImports]
  exports : Array[CheckedTopologyExport]
  local_inputs : Array[@local.Attached]?
  local_environment : @local.ProgramEnvironmentInputs?
  reconciled_inputs : Array[@local.ReconciledAttachment]?
  usage : LocalProgramUsage
  calendar_profile : @calendar_profile.Profile?
  model_tasks : @environment.ModelTasks?
}

///|
priv enum ProgramStage {
  Publication(StagePorts)
  Topology(CheckedStageTopology)
}

///|
priv enum ProgramImports {
  Publication(ResultImports)
  Topology(CheckedTopologyImports)
}

///|
priv enum ProgramAttachedImports {
  Publication(AttachedImports)
  Topology(CheckedTopologyImports)
}

///|
pub enum LocalProgramPreparation {
  Publication(ResultWiring)
  Topology(CheckedTopology)
}

///|
fn program_stage(value : ProgramStage) -> @parameters.CollectedStage {
  match value {
    Publication(v) => v.stage
    Topology(v) => v.stage
  }
}

///|
fn program_result_input(
  value : ProgramStage,
  name : String,
) -> @pipeline.ProducedInput? {
  match value {
    Publication(v) =>
      @results.lookup_port(v.ports, name).map(@results.port_input)
    Topology(v) => @results.lookup_checked_input(v.results, name)
  }
}

///|
fn program_import_usage(value : ProgramImports) -> (Int, Int) {
  match value {
    Publication(v) => import_usage(v)
    Topology(v) => (v.work, v.text_bytes)
  }
}

///|
fn program_import_count(value : ProgramImports) -> Int {
  match value {
    Publication(v) => import_count(v)
    Topology(v) => v.entries.length()
  }
}

///|
fn program_import_at(
  value : ProgramImports,
  i : Int,
) -> (String, @pipeline.ProducedInput) {
  match value {
    Publication(v) => {
      let entry = import_at(v, i).unwrap()
      (input_name(entry), input_producer(entry))
    }
    Topology(v) => (v.entries[i].name, v.entries[i].input)
  }
}

///|
fn resolve_program_imports(
  source : @parameters.Source,
  index : Int,
  stages : Array[ProgramStage],
  limits : ImportLimits,
  check_only : Bool,
) -> Result[ProgramImports, ImportIssue] {
  if !check_only {
    let producers = stages.map(fn(stage) {
      guard stage is Publication(owner) else {
        abort("mixed preparation modes")
      }
      owner
    })
    return resolve_imports(source, index, producers, limits).map(fn(v) {
      ProgramImports::Publication(v)
    })
  }
  let (entries, work, text_bytes) = match
    resolve_result_references(
      source,
      index,
      stages,
      limits,
      owner_stage=program_stage,
      lookup=program_result_input,
    ) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  Ok(
    Topology({
      source,
      index,
      stage: None,
      work,
      text_bytes,
      entries: entries.map(fn(entry) {
        let (name, owner, input) = entry
        guard owner is Topology(producer) else {
          abort("mixed preparation modes")
        }
        { name, producer, input, }
      }),
    }),
  )
}

///|
fn attach_program_imports(
  value : ProgramImports,
  stage : @parameters.CollectedStage,
  max_work : Int,
) -> Result[ProgramAttachedImports, ImportIssue] {
  match value {
    Publication(v) =>
      attach_imports(v, stage, max_work~).map(fn(v) {
        ProgramAttachedImports::Publication(v)
      })
    Topology(v) =>
      match
        check_import_attachment(
          v.source,
          v.index,
          v.entries,
          v.work,
          stage,
          max_work,
          entry_name=fn(e) { e.name },
          entry_input=fn(e) { e.input },
        ) {
        Err(e) => Err(e)
        Ok(work) => Ok(Topology({ ..v, stage: Some(stage), work, }))
      }
  }
}

///|
fn program_attached_work(value : ProgramAttachedImports) -> Int {
  match value {
    Publication(v) => attached_work(v)
    Topology(v) => v.work
  }
}

///|
// Every stage was issued by the shared preparation loop and every input by the
// source-bound resolver/attachment checks. Resolve root exports without ports.
fn finish_checked_topology(
  source : @parameters.Source,
  stages : Array[ProgramStage],
  imports : Array[ProgramAttachedImports],
  limits : WiringLimits,
  locals : Array[@local.Attached],
  environment : @local.ProgramEnvironmentInputs?,
  reconciled : Array[@local.ReconciledAttachment],
  usage : LocalProgramUsage,
  calendar_profile : @calendar_profile.Profile?,
  model_tasks : @environment.ModelTasks?,
) -> Result[CheckedTopology, WiringIssue] {
  let checked_stages = stages.map(fn(stage) {
    guard stage is Topology(v) else { abort("mixed preparation modes") }
    v
  })
  let checked_imports = imports.map(fn(imported) {
    guard imported is Topology(v) else { abort("mixed preparation modes") }
    v
  })
  let program = @parameters.complete_program(source)
  let count = program.map(@syntax.export_count).unwrap_or(0)
  if count > limits.max_exports || count > limits.max_work {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work - count
  let mut text = limits.max_text_bytes
  let exports : Array[CheckedTopologyExport] = []
  for i in 0..<count {
    let (name, producer, result) = @syntax.export_at(program.unwrap(), i).unwrap()
    for value in [name, producer, result] {
      match @scalar.admit_utf8_length(value, text) {
        Err(_) => return Err(BudgetExceeded)
        Ok(n) => text -= n
      }
    }
    let mut found = None
    for stage in checked_stages {
      if work == 0 {
        return Err(BudgetExceeded)
      }
      work -= 1
      if @parameters.stage_at(source, @parameters.stage_index(stage.stage)).unwrap().id ==
        producer {
        found = Some(stage)
        break
      }
    }
    let owner = match found {
      None => return Err(UnknownExport(producer, result))
      Some(v) => v
    }
    let input = match @results.lookup_checked_input(owner.results, result) {
      None => return Err(UnknownExport(producer, result))
      Some(v) => v
    }
    exports.push({ name, producer: owner, input, })
  }
  Ok({
    source,
    calendar_profile,
    model_tasks,
    stages: checked_stages,
    imports: checked_imports,
    exports,
    local_inputs: if environment is None {
      Some(locals)
    } else {
      None
    },
    local_environment: environment,
    reconciled_inputs: if environment is Some(_) {
      Some(reconciled)
    } else {
      None
    },
    usage: {
      ..usage,
      work: usage.work + limits.max_work - work,
      text_bytes: usage.text_bytes + limits.max_text_bytes - text,
    },
  })
}

///|
pub fn topology_source(value : CheckedTopology) -> @parameters.Source {
  value.source
}

///|
pub fn topology_stage_at(
  value : CheckedTopology,
  index : Int,
) -> CheckedStageTopology? {
  value.stages.get(index)
}

///|
pub fn topology_stage_source(
  value : CheckedStageTopology,
) -> @parameters.CollectedStage {
  value.stage
}

///|
pub fn topology_stage_results(
  value : CheckedStageTopology,
) -> @results.CheckedResultInputs {
  value.results
}

///|
pub fn topology_imports_at(
  value : CheckedTopology,
  index : Int,
) -> CheckedTopologyImports? {
  value.imports.get(index)
}

///|
pub fn topology_import_count(value : CheckedTopologyImports) -> Int {
  value.entries.length()
}

///|
pub fn topology_import_at(
  value : CheckedTopologyImports,
  index : Int,
) -> CheckedTopologyImport? {
  value.entries.get(index)
}

///|
pub fn topology_input_name(value : CheckedTopologyImport) -> String {
  value.name
}

///|
pub fn topology_input_stage(
  value : CheckedTopologyImport,
) -> CheckedStageTopology {
  value.producer
}

///|
pub fn topology_input_producer(
  value : CheckedTopologyImport,
) -> @pipeline.ProducedInput {
  value.input
}

///|
pub fn topology_export_count(value : CheckedTopology) -> Int {
  value.exports.length()
}

///|
pub fn topology_export_at(
  value : CheckedTopology,
  index : Int,
) -> CheckedTopologyExport? {
  value.exports.get(index)
}

///|
pub fn topology_export_name(value : CheckedTopologyExport) -> String {
  value.name
}

///|
pub fn topology_export_stage(
  value : CheckedTopologyExport,
) -> CheckedStageTopology {
  value.producer
}

///|
pub fn topology_export_input(
  value : CheckedTopologyExport,
) -> @pipeline.ProducedInput {
  value.input
}

///|
pub fn topology_local_environment(
  value : CheckedTopology,
) -> @local.ProgramEnvironmentInputs? {
  value.local_environment
}

///|
pub fn topology_local_input_at(
  value : CheckedTopology,
  index : Int,
) -> @local.Attached? {
  value.local_inputs.bind(fn(entries) { entries.get(index) })
}

///|
pub fn topology_reconciled_input_at(
  value : CheckedTopology,
  index : Int,
) -> @local.ReconciledAttachment? {
  value.reconciled_inputs.bind(fn(entries) { entries.get(index) })
}

///|
pub fn topology_usage(value : CheckedTopology) -> LocalProgramUsage {
  value.usage
}

///|
pub fn topology_stage_orders(
  value : CheckedStageTopology,
) -> @pipeline.ContextualClosure {
  value.contextual
}

///|
pub fn topology_stage_table_inputs(
  value : CheckedStageTopology,
) -> @results.CheckedTableInputs? {
  value.table_inputs
}

///|
pub fn topology_import_stage(
  value : CheckedTopologyImports,
) -> @parameters.CollectedStage {
  value.stage.unwrap()
}

///|
pub fn topology_calendar_profile(
  value : CheckedTopology,
) -> @calendar_profile.Profile? {
  value.calendar_profile
}

///|
pub fn topology_model_tasks(
  value : CheckedTopology,
) -> @environment.ModelTasks? {
  value.model_tasks
}
