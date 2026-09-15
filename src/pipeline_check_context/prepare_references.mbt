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
  let requests = operations.preparation.sources.capacity.context.rows.requests
  let stages = requests.contexts
  let collected = @stages.bound_operations(stages.operations)
  let source = @stages.operations_source(collected)
  let count = @stages.stage_count(source)
  if stages.work > max_work || count > max_work - stages.work {
    return Err(BudgetExceeded)
  }
  // attach_program_references visits each Stage after the reference branch.
  let cap = max_work - stages.work - count
  let request_work = @request_slots.work(requests.slots)
  if request_work > cap || count > cap - request_work {
    return Err(BudgetExceeded)
  }
  let mut remaining = cap - request_work - count
  let uses = []
  for i in 0..<count {
    let body = match
      @stage_body.prepare(@stages.operations_stage_at(collected, i).unwrap(), {
        ..body_limits,
        max_work: Int::min(body_limits.max_work, remaining),
      }) {
      Ok(v) => v
      Err(e) => return Err(Body(i, e))
    }
    let value = match
      @stage_body.collect_parameter_uses(body, {
        ..use_limits,
        max_work: Int::min(use_limits.max_work, remaining),
      }) {
      Ok(v) => v
      Err(e) => return Err(Uses(i, e))
    }
    remaining -= @stage_body.parameter_work(value)
    uses.push(value)
  }
  let inventory = match
    @program_refs.prepare(requests.slots, uses, {
      ..reference_limits,
      max_work: Int::min(reference_limits.max_work, cap),
    }) {
    Ok(v) => v
    Err(e) => return Err(Inventory(e))
  }
  let usage = match
    @program_refs.check_declaration_usage(inventory, max_work=cap) {
    Ok(v) => v
    Err(e) => return Err(Usage(e))
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
