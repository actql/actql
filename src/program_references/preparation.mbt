///|
pub enum PreparationIssue {
  InvalidLimits
  BudgetExceeded
  Body(Int, @body.Issue)
  Uses(Int, @body.ParameterIssue)
  Inventory(Issue)
  Usage(UsageIssue)
}

///|
/// Close declaration use from the exact retained request and stage owners,
/// before requiring any execution values. This certifies reference use only;
/// static obligation closure and executable admission remain separate owners.
/// The ceiling includes request, stage-body and use prefixes exactly once.
pub fn prepare_declaration_usage(
  requests : @requests.Slots,
  stages : Array[@stages.CollectedStage],
  body_limits : @body.Limits,
  use_limits : @collection.Limits,
  reference_limits : Limits,
  max_work~ : Int,
) -> Result[DeclarationUsage, PreparationIssue] {
  if max_work < 0 ||
    body_limits.max_work < 0 ||
    use_limits.max_work < 0 ||
    reference_limits.max_work < 0 {
    return Err(InvalidLimits)
  }
  let source = @requests.source(requests)
  let count = @stages.stage_count(source)
  if stages.length() != count {
    return Err(Inventory(StageCountMismatch))
  }
  let request_work = @requests.work(requests)
  if request_work > max_work || count > max_work - request_work {
    return Err(BudgetExceeded)
  }
  let mut remaining = max_work - request_work - count
  let uses = []
  for i in 0..<count {
    let stage = stages[i]
    if @stages.stage_index(stage) != i ||
      !physical_equal(@stages.source(stage), source) {
      return Err(Inventory(ForeignStage(i)))
    }
    let body = match
      @body.prepare(stage, {
        ..body_limits,
        max_work: Int::min(body_limits.max_work, remaining),
      }) {
      Ok(v) => v
      Err(e) => return Err(Body(i, e))
    }
    let value = match
      @body.collect_parameter_uses(body, {
        ..use_limits,
        max_work: Int::min(use_limits.max_work, remaining),
      }) {
      Ok(v) => v
      Err(e) => return Err(Uses(i, e))
    }
    remaining -= @body.parameter_work(value)
    uses.push(value)
  }
  let inventory = match
    prepare(requests, uses, {
      ..reference_limits,
      max_work: Int::min(reference_limits.max_work, max_work),
    }) {
    Ok(v) => v
    Err(e) => return Err(Inventory(e))
  }
  match check_declaration_usage(inventory, max_work~) {
    Ok(v) => Ok(v)
    Err(e) => Err(Usage(e))
  }
}
