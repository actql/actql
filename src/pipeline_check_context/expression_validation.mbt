///|
pub(all) struct ExpressionValidationLimits {
  max_work : Int
  max_text_bytes : Int
  max_policy_nodes : Int
  max_policy_depth : Int
  max_requirements : Int
} derive(Eq, Debug)

///|
pub(all) enum ExpressionValidationIssue {
  InvalidLimits
  BudgetExceeded
  TextTime(@environment.TextTimeIssue)
} derive(Eq, Debug)

///|
struct ExpressionValidationContext {
  selected : SelectedPolicyContext
  text_time : @environment.TextTime?
  sites : Array[(Int, Int)]
  usage : SelectedPolicyUsage
}

///|
struct ExpressionValidationSite {
  owner : ExpressionValidationContext
  stage : Int
  index : Int
}

///|
/// Connect existing static requirements to their exact staged bindings and
/// selected environment. No requirement is discharged by this constructor.
pub fn prepare_expression_validation(
  selected : SelectedPolicyContext,
  limits : ExpressionValidationLimits,
) -> Result[ExpressionValidationContext, ExpressionValidationIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_policy_nodes < 0 ||
    limits.max_policy_depth < 0 ||
    limits.max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let before = selected.usage
  if before.work >= limits.max_work ||
    before.text_bytes > limits.max_text_bytes ||
    before.policy_nodes > limits.max_policy_nodes {
    return Err(BudgetExceeded)
  }
  let mut work = before.work + 1
  let mut text = before.text_bytes
  let mut nodes = before.policy_nodes
  let environment = @local_inputs.program_environment(
    selected.context.snapshots,
  )
  // Validate a present component even when no expression consumes it. Absence
  // remains unresolved; it is neither a default policy nor profile admission.
  let text_time = match
    @environment.read_text_time(environment, {
      max_bytes: limits.max_text_bytes - text,
      max_nodes: Int::min(
        limits.max_policy_nodes - nodes,
        limits.max_work - work,
      ),
      max_depth: limits.max_policy_depth,
    }) {
    Ok(policy) => {
      let (bytes, count) = @environment.text_time_usage(policy)
      text += bytes
      nodes += count
      work += count
      Some(policy)
    }
    Err(@environment.MissingTextTime) => None
    Err(@environment.BudgetExceeded) => return Err(BudgetExceeded)
    Err(e) => return Err(TextTime(e))
  }
  let sites : Array[(Int, Int)] = []
  let stages = selected.context.wired.stages
  for stage in 0..<stages.contexts.length() {
    if work == limits.max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let context = stages.contexts[stage].context
    let count = expression_requirement_count(context)
    if count > limits.max_work - work ||
      count > limits.max_requirements - sites.length() {
      return Err(BudgetExceeded)
    }
    work += count
    for index in 0..<count {
      sites.push((stage, index))
    }
  }
  Ok({
    selected,
    text_time,
    sites,
    usage: { ..before, work, text_bytes: text, policy_nodes: nodes, },
  })
}

///|
pub fn expression_validation_selected(
  v : ExpressionValidationContext,
) -> SelectedPolicyContext {
  v.selected
}

///|
pub fn expression_validation_text_time(
  v : ExpressionValidationContext,
) -> @environment.TextTime? {
  v.text_time
}

///|
pub fn expression_validation_usage(
  v : ExpressionValidationContext,
) -> SelectedPolicyUsage {
  v.usage
}

///|
pub fn expression_validation_count(v : ExpressionValidationContext) -> Int {
  v.sites.length()
}

///|
pub fn expression_validation_at(
  v : ExpressionValidationContext,
  index : Int,
) -> ExpressionValidationSite? {
  v.sites.get(index).map(pair => { owner: v, stage: pair.0, index: pair.1, })
}

///|
pub fn validation_site_context(
  v : ExpressionValidationSite,
) -> ExpressionValidationContext {
  v.owner
}

///|
/// Process-local coordinates, never a persistent Program/Invocation identity.
pub fn validation_site_location(v : ExpressionValidationSite) -> (Int, Int) {
  (v.stage, v.index)
}

///|
pub fn validation_site_requirement(
  v : ExpressionValidationSite,
) -> ExpressionRequirement {
  expression_requirement_at(
    v.owner.selected.context.wired.stages.contexts[v.stage].context,
    v.index,
  ).unwrap()
}

///|
pub fn validation_site_parameters(
  v : ExpressionValidationSite,
) -> ParameterVisit {
  let requirement = validation_site_requirement(v)
  v.owner.selected.context.wired.stages.contexts[v.stage].visits[requirement.visit]
}
