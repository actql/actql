///|
/// Semantic source identity, separate from process-local ownership handles.
pub fn source_identity(
  program : CheckedProgram,
) -> @context.ProgramSourceIdentity {
  program.identity
}

///|
pub fn incoming_gates(
  program : CheckedProgram,
) -> @context.ProgramIncomingGates {
  program.gates
}

///|
/// Selection provenance; the per-Unit contract set is exposed separately.
pub fn contract_inventory(
  program : CheckedProgram,
) -> @context.CoreContractInventory {
  program.contracts
}

///|
/// Exact expression profiles admitted while checking this Program. These are
/// lowering inputs, not backend capabilities or an execution permit.
pub fn selected_expression_profiles(
  program : CheckedProgram,
) -> @context.ExpressionProfiles {
  program.expression_profiles
}

///|
pub fn unit_contract_count(program : CheckedProgram, unit : Int) -> Int? {
  program.units.get(unit).map(value => value.contracts.length())
}

///|
pub fn unit_contract_at(
  program : CheckedProgram,
  unit : Int,
  index : Int,
) -> (String, @context.CoreContractBody)? {
  match program.units.get(unit) {
    None => None
    Some(value) => value.contracts.get(index)
  }
}

///|
pub fn unit_result_import_count(program : CheckedProgram, unit : Int) -> Int? {
  program.units.get(unit).map(value => value.interfaces.length())
}

///|
/// The interface preserves the consumer input name and exact producer port.
pub fn unit_result_import_at(
  program : CheckedProgram,
  unit : Int,
  index : Int,
) -> BuiltResultInterface? {
  match program.units.get(unit) {
    None => None
    Some(value) => value.interfaces.get(index)
  }
}

///|
pub fn unit_contracts_cid(program : CheckedProgram, index : Int) -> String? {
  program.units.get(index).map(unit => unit.contracts_cid)
}

///|
pub fn unit_import_cid_count(program : CheckedProgram, unit : Int) -> Int? {
  program.units.get(unit).map(value => value.imports.length())
}

///|
pub fn unit_import_cid_at(
  program : CheckedProgram,
  unit : Int,
  index : Int,
) -> String? {
  program.units.get(unit).bind(value => value.imports.get(index))
}

///|
pub fn unit_gate_cid_count(program : CheckedProgram, unit : Int) -> Int? {
  program.units.get(unit).map(value => value.gates.length())
}

///|
pub fn unit_gate_cid_at(
  program : CheckedProgram,
  unit : Int,
  index : Int,
) -> String? {
  program.units.get(unit).bind(value => value.gates.get(index))
}

///|
pub fn unit_publication_count(program : CheckedProgram, index : Int) -> Int? {
  program.units.get(index).map(unit => unit.publications.length())
}

///|
/// Read an owned binding without copying its candidate or dependency arrays.
pub fn unit_publication_at(
  program : CheckedProgram,
  unit : Int,
  index : Int,
) -> PublicationExecution? {
  match program.units.get(unit) {
    None => None
    Some(unit) => unit.publications.get(index)
  }
}

///|
pub fn publication_selection(
  value : PublicationExecution,
) -> @context.PublicationRowLimit {
  value.selection
}

///|
pub fn publication_rows(value : PublicationExecution) -> @wire.LimitClaim {
  value.rows
}

///|
pub fn publication_bytes(value : PublicationExecution) -> @wire.LimitClaim {
  value.bytes
}

///|
pub fn publication_phase(value : PublicationExecution) -> PublicationPhase {
  value.phase
}

///|
pub fn publication_failure(value : PublicationExecution) -> PublicationFailure {
  value.failure
}

///|
/// Envelope requirements are Program-wide, not repeated per Unit. The bound
/// retains its expression site, demand and selected policy for execution.
pub fn expression_bound_count(program : CheckedProgram) -> Int {
  match program.units.get(0) {
    None => 0
    Some(unit) => unit.expression_execution.length()
  }
}

///|
/// Complete expression dispositions, including static profile and pattern
/// validation. Runtime bound reads alone are not this complete inventory.
pub fn expression_closure(
  program : CheckedProgram,
) -> @context.ProgramExpressionClosure? {
  program.units.get(0).map(unit => unit.expressions)
}

///|
pub fn expression_bound_at(
  program : CheckedProgram,
  index : Int,
) -> @context.TextBoundResolution? {
  match program.units.get(0) {
    None => None
    Some(unit) => unit.expression_execution.get(index).map(value => value.bound)
  }
}

///|
/// Preserve the owning requirement alongside the runtime bound. Indices refer
/// to the returned closure only, not to a public persistent identity.
pub fn expression_execution_at(
  program : CheckedProgram,
  index : Int,
) -> ExpressionExecution? {
  match program.units.get(0) {
    None => None
    Some(unit) => unit.expression_execution.get(index)
  }
}

///|
pub fn expression_execution_owner(
  value : ExpressionExecution,
) -> @context.ProgramExpressionClosure {
  value.owner
}

///|
pub fn expression_execution_requirement_index(
  value : ExpressionExecution,
) -> Int {
  value.requirement_index
}

///|
pub fn expression_execution_bound(
  value : ExpressionExecution,
) -> @context.TextBoundResolution {
  value.bound
}
