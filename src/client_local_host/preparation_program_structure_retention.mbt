///|
/// Retire only the previous synchronous Program constructor's actual scratch.
/// Its full frame returned before this call. Index/Program/observer DATA and
/// outside borrowers stay retained; no parent or physical backing is closed.
pub fn[I, P] reconcile_program_json_preparation_structure(
  owner : ClientProgramJsonPreparation[I, P],
) -> Result[Unit, ClientProgramJsonPreparationIssue] {
  guard !owner.busy &&
    owner.phase == Constructed &&
    owner.program is Some(_) &&
    owner.input is Some(input) &&
    owner.structure_quote is Some((retained, _)) else {
    return Err(WrongPhase)
  }
  if retained < owner.base_retained {
    return Err(Overflow)
  }
  let core = retained - owner.base_retained
  guard @execution.checked_preparation_add_product(
      core, program_json_quote_control_bytes, 1L,
    )
    is Some(e) &&
    @execution.checked_preparation_add_product(owner.base_execution, e, 1L)
    is Some(e) else {
    return Err(Overflow)
  }
  owner.busy = true
  let result = @resources.reconcile_working_preparation_phase(
    owner.capacity,
    input,
    retained,
    e,
  )
  owner.busy = false
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.phase = RetainedProgram
      Ok(())
    }
  }
}
