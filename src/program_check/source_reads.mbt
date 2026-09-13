///|
/// Acquisition bindings are Program-wide. An empty list on the Local domain
/// is not evidence that an unsupported SourceView was silently accepted.
pub fn source_execution_count(program : CheckedProgram) -> Int {
  match program.units.get(0) {
    None => 0
    Some(unit) => unit.source_execution.length()
  }
}

///|
pub fn source_execution_at(
  program : CheckedProgram,
  index : Int,
) -> SourceExecution? {
  match program.units.get(0) {
    None => None
    Some(unit) => unit.source_execution.get(index)
  }
}

///|
pub fn source_execution_subject(
  value : SourceExecution,
) -> SourceExecutionSubject {
  value.subject
}

///|
pub fn source_execution_kind(value : SourceExecution) -> SourceExecutionKind {
  value.kind
}

///|
pub fn source_execution_phase(value : SourceExecution) -> SourceExecutionPhase {
  value.phase
}

///|
pub fn source_execution_failure(
  value : SourceExecution,
) -> SourceExecutionFailure {
  value.failure
}

///|
pub fn source_execution_prerequisite_count(value : SourceExecution) -> Int {
  value.prerequisites.length()
}

///|
pub fn source_execution_prerequisite_at(
  value : SourceExecution,
  index : Int,
) -> SourceExecution? {
  value.prerequisites.get(index)
}
