///|
pub enum PreparedReferencesIssue {
  InvalidLimits
  BudgetExceeded
  Body(Int, @stage_body.Issue)
  Uses(Int, @stage_body.ParameterIssue)
  Inventory(@program_refs.Issue)
  Usage(@program_refs.UsageIssue)
  Values(@references.BindingIssue)
  Attachment(ProgramReferenceIssue)
}

///|
/// Derive source-role references from the exact checked operations, request
/// slots and effective values. Per-stage parser limits remain explicit; the
/// aggregate work ceiling includes the retained Stage prefix and final join.
pub fn prepare_program_references(
  operations : OperationProfileChecks,
  body_limits : @stage_body.Limits,
  use_limits : @parameter_slots.Limits,
  reference_limits : @program_refs.Limits,
  max_work~ : Int,
) -> Result[ProgramReferences, PreparedReferencesIssue] {
  if max_work < 0 ||
    body_limits.max_work < 0 ||
    use_limits.max_work < 0 ||
    reference_limits.max_work < 0 {
    return Err(InvalidLimits)
  }
  let requests = operations.preparation.requests
  let stages = requests.contexts
  let collected = @stages.bound_operations(stages.operations)
  let source = @stages.operations_source(collected)
  let count = @stages.stage_count(source)
  if stages.work > max_work || count > max_work - stages.work {
    return Err(BudgetExceeded)
  }
  // attach_program_references visits each Stage after the reference branch.
  let cap = max_work - stages.work - count
  let usage = match
    @program_refs.prepare_declaration_usage(
      requests.slots,
      Array::makei(count, i => {
        @stages.operations_stage_at(collected, i).unwrap()
      }),
      body_limits,
      use_limits,
      reference_limits,
      max_work=cap,
    ) {
    Ok(v) => v
    Err(InvalidLimits) => return Err(InvalidLimits)
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(Body(i, e)) => return Err(Body(i, e))
    Err(Uses(i, e)) => return Err(Uses(i, e))
    Err(Inventory(e)) => return Err(Inventory(e))
    Err(Usage(e)) => return Err(Usage(e))
  }
  let values = @references.bound_values(
    @stages.bound_program_index(stages.operations),
  )
  let references = match
    @program_refs.bind_parameter_values(usage, values, max_work=cap) {
    Ok(v) => v
    Err(e) => return Err(Values(e))
  }
  match attach_program_references(stages, references, max_work~) {
    Ok(v) => Ok(v)
    Err(e) => Err(Attachment(e))
  }
}
