///|
// Saved material admission uses the existing bounded readers. The outer
// material, nested Program/Environment, typed contracts and compiler output
// coexist; source text and retained wire are distinct from active parse work.
// These are existing managed execution units, not an RSS/GC guarantee.
fn request_model_recovery_capacity(
  units : Int64,
  containers : Int,
) -> @execution.ExecutionCapacity? {
  if units < 0L || units > 2147483647L || containers < 0 {
    return None
  }
  @execution.execution_capacity_inventory(
    [
      { unit: ValueNodeSlots, count: units, copies: 6, },
      { unit: DecodedTextBytes, count: units, copies: 6, },
      { unit: CanonicalWireBytes, count: units, copies: 4, },
      { unit: ValueNodeSlots, count: containers.to_int64(), copies: 8, },
    ],
    [
      { unit: ValueNodeSlots, count: units, copies: 2, },
      { unit: CanonicalWireBytes, count: units, copies: 4, },
      { unit: CursorRootSlots, count: Int64::min(units, 100L), copies: 2, },
    ],
    RetainedAlongsideExecution,
  )
}

///|
/// Reserve each saved-material/dependency/binding constructor on the SAME
/// physical restoration Request. The Journal's original Request/Definition
/// pair stays nominal; no checked owner, compiler or Model permission is
/// issued. Completed constructor retention accumulates while scratch is a
/// sequential peak. Failure leaves all prior capacity and cleanup intact.
pub fn[I] reserve_request_model_recovery_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  count : Int,
  wire_at : (Int) -> String,
  containers : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard (owner.phase == Open || owner.phase == ModelRecovery) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None &&
    @publication.publication_contract_name(definition) == "run_definition" &&
    count >= 0 &&
    containers >= 0 else {
    return Err(ForeignOriginal)
  }
  match owner.program_domain_compilation_inputs {
    None => {
      if owner.phase != Open ||
        owner.snapshot_base is Some(_) ||
        owner.submitted_intent is Some(_) ||
        owner.program_check is Some(_) ||
        owner.program_json is Some(_) {
        return Err(WrongPhase)
      }
      owner.program_domain_compilation_inputs = Some(
        RequestModelRecovery(request, definition),
      )
    }
    Some(RequestModelRecovery(old_request, old_definition)) =>
      if !physical_equal(old_request, request) ||
        !physical_equal(old_definition, definition) {
        return Err(ForeignOriginal)
      }
    _ => return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      // Current/capacity admission precedes the original wire callback. The
      // callback only reads immutable already-owned Strings, once each.
      let (old_r, old_e) = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      match
        @resources.check_working_preparation_capacity_current(
          owner.capacity,
          input,
        ) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      let mut units = 0L
      for index in 0..<count {
        let wire = wire_at(index)
        guard @execution.checked_preparation_add_product(
            units,
            wire.length().to_int64(),
            3L,
          )
          is Some(next) else {
          return Err(Policy)
        }
        units = next
      }
      guard request_model_recovery_capacity(units, containers) is Some(required) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_retained_bytes(required),
          1L,
        )
        is Some(r) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_execution_bytes(required),
          1L,
        )
        is Some(e) else {
        return Err(Policy)
      }
      let result = @resources.reserve_working_preparation_phase(
        owner.capacity,
        input,
        r,
        Int64::max(old_e, e),
      )
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.program_domain_compilation_inputs
        is Some(RequestModelRecovery(old_request, old_definition)) &&
        physical_equal(old_request, request) &&
        physical_equal(old_definition, definition) else {
        return Err(ForeignOriginal)
      }
      owner.phase = ModelRecovery
      result.map_err(issue => Capacity(issue))
    },
    () => if owner.phase == Selecting { owner.phase = ModelRecovery },
  )
}
