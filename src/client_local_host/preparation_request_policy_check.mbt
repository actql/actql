///|
/// One shallow CheckEnvironment (eight borrowed references/one Bool) and its
/// copied evidence reference inventory. Proof bodies remain with their issuer;
/// neither this copy nor a policy CID is Host verification or physical backing.
fn request_policy_selection_layout(
  count : Int,
) -> @execution.PreparationRepresentationUnits? {
  if count < 0 {
    return None
  }
  let environment : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 8L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  @execution.compose_preparation_representation([
    environment,
    closed_values_program_arrays(1L, count.to_int64(), false),
  ])
}

///|
/// Supplement the SAME checked Request before compiler/body selection. The
/// Host's nominal evidence is still matched by the existing full checker to
/// Program/Parameters/occurrence/SourceView/request/origins. This transition
/// never interprets a policy CID, callback result or returned Environment as
/// authority. Its original input and Environment cannot be substituted.
pub fn[I] supplement_request_computation_policies(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  evidence : Array[@checked.HostRequestValuePolicyEvidence],
) -> Result[@checked.CheckEnvironment, ClientRequestTerminalIssue] {
  guard owner.phase == ProgramCheck &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == SemanticCheckComplete &&
    child.arguments is Some(arguments) &&
    physical_equal(arguments.environment, environment) &&
    child.compiled_program is None &&
    child.compiled_effect is None &&
    child.work is None &&
    child.topology_work is None &&
    child.check_data is Some(_) &&
    owner.program_capacity is None &&
    owner.effect_capacity is None else {
    return Err(Preparation(ForeignOriginal))
  }
  let checked = match child.effect_candidate {
    Some(candidate) => @checked.effect_computation_checked_program(candidate)
    None => {
      guard child.check_outcome is Some(@checked.Checked(program)) else {
        return Err(Preparation(WrongPhase))
      }
      program
    }
  }
  let count = evidence.length()
  // The fixed Host selects at most one policy proof per checked occurrence.
  // This bounds pointer comparison/copy by the SAME checked inventory, not a
  // caller-provided limit or an unrelated default profile.
  if count > @checked.source_execution_count(checked) {
    return Err(Preparation(Policy))
  }
  if count == 0 ||
    @checked.checking_environment_request_value_policies_match(
      environment, evidence,
    ) {
    return Ok(environment)
  }
  owner.phase = Selecting
  child.busy = true
  preparation_module_call(
    () => {
      let result = supplement_request_computation_policies_owned(
        owner, input, child, arguments, environment, evidence, count,
      )
      if result is Err(_) {
        // A selected failed supplement cannot compile the earlier verdict as
        // if its required Host policy step had succeeded. Cleanup keeps the
        // same original Request and every still-retained child.
        owner.phase = ProgramCheckFailed
        child.phase = Failed
      }
      result
    },
    () => {
      child.busy = false
      if owner.phase == Selecting {
        child.phase = Failed
        owner.phase = ProgramCheckFailed
      }
    },
  )
}

///|
fn[I] supplement_request_computation_policies_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  child : ClientProgramCheckPreparation[I, Unit],
  arguments : ProgramCheckArguments,
  environment : @checked.CheckEnvironment,
  evidence : Array[@checked.HostRequestValuePolicyEvidence],
  count : Int,
) -> Result[@checked.CheckEnvironment, ClientRequestTerminalIssue] {
  guard request_policy_selection_layout(count) is Some(layout) &&
    @execution.preparation_representation_cost(layout) is Some(copy_bytes) &&
    child.check_data is Some(data) &&
    program_check_data_extent_cost(data) is Some(semantic_bytes) &&
    @execution.checked_preparation_add_product(copy_bytes, semantic_bytes, 1L)
    is Some(bytes) else {
    return Err(Preparation(Policy))
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(extents) => extents
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(Preparation(Policy))
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(_) => ()
  }
  // Imported currentness may reenter; preserve exact ownership and the funded
  // reference count before constructing the selected shallow Environment.
  guard owner.phase == Selecting &&
    owner.program_check is Some(current) &&
    physical_equal(current, child) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    evidence.length() == count else {
    return Err(Preparation(ForeignOriginal))
  }
  let selected = @checked.checking_environment_with_request_value_policies(
    environment, evidence,
  )
  // The original estimate already covers Source execution and publication
  // policy construction. Add that envelope while all old facts are retained;
  // no source inspection, Catalog admission, topology or checker replay occurs.
  guard data.semantic_work >= 0L && data.semantic_work <= 2147483647L else {
    return Err(Preparation(Policy))
  }
  let limits = {
    ..arguments.limits.compilation,
    work: data.semantic_work.to_int(),
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.RequestValuePolicyCheck,
      data.semantic_work,
    ) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(work) => work
  }
  child.work = Some(work)
  let (result, spent, complete) = match child.effect_candidate {
    Some(candidate) => {
      let (result, spent, complete) = @checked.observe_supplement_effect_request_value_policies(
        candidate, evidence, limits,
      )
      let result = match result {
        Err(issue) => Err(EffectInput(issue))
        Ok(value) => {
          child.effect_candidate = Some(value)
          Ok(())
        }
      }
      (result, spent, complete)
    }
    None => {
      guard child.check_outcome is Some(@checked.Checked(original)) else {
        return Err(Preparation(WrongPhase))
      }
      let (result, spent, complete) = @checked.observe_supplement_checked_request_value_policies(
        original, evidence, limits,
      )
      let result = match result {
        Err(issue) => Err(Check(issue))
        Ok(value) => {
          child.check_outcome = Some(value)
          Ok(())
        }
      }
      (result, spent, complete)
    }
  }
  child.check_work_complete = complete
  let charged = @resources.spend_preparation_phase_work64(
    work,
    spent.to_int64(),
  )
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(_) => child.work = None
  }
  match charged {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(_) => ()
  }
  match result {
    Err(issue) => Err(Preparation(ProgramCheck(issue)))
    Ok(_) => {
      child.arguments = Some({ ..arguments, environment: selected, })
      owner.phase = ProgramCheck
      Ok(selected)
    }
  }
}
