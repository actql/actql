///|
pub(all) enum GraphSelectionResource {
  SelectorWork
  SelectorBytes
} derive(Eq, Debug)

///|
pub(all) enum GraphSelectorRule {
  AdmitIdentities
  RevalidateReferences
  DeduplicateIdentities
  RequireMembership
  EvaluateNodePredicate
  RequireSelectorResources
} derive(Eq, Debug)

///|
pub struct GraphSelectorCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  graph : @pipeline.Target
  relation : @pipeline.Target?
  selector : @graph.CheckedSelector
  rule : GraphSelectorRule
  policy : @policy.Policy
}

///|
pub fn graph_selector_resource_count(check : GraphSelectorCheck) -> Int {
  if check.rule == RequireSelectorResources {
    2
  } else {
    0
  }
}

///|
pub fn graph_selector_resource_at(
  check : GraphSelectorCheck,
  index : Int,
) -> GraphSelectionResource? {
  if check.rule != RequireSelectorResources {
    return None
  }
  match index {
    0 => Some(SelectorWork)
    1 => Some(SelectorBytes)
    _ => None
  }
}

///|
fn graph_selector_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.SelectorRequirement(pending) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.input is Some(graph) &&
    @pipeline.operation_obligations_selector(site.obligations) is Some(selector) &&
    @pipeline.operation_obligation_group_at(step.operation, site.group)
    is Some(group) &&
    @pipeline.operation_obligations_selector(group) is Some(expected) &&
    physical_equal(selector, expected) &&
    @pipeline.operation_obligations_scope(group) ==
    @pipeline.operation_obligations_scope(site.obligations) &&
    @graph.selector_pending_at(selector, site.index) == Some(pending) else {
    return Err(ForeignOccurrence(site.step))
  }
  let (relation, role, index) = match step.operation {
    Traverse(selector=target, ..) => (target, @pipeline.Right, 1)
    _ => return Err(ForeignOccurrence(site.step))
  }
  guard @pipeline.input_occurrence_at(step, 0) is Some(primary) &&
    primary.role == @pipeline.Primary &&
    primary.target == graph else {
    return Err(ForeignOccurrence(site.step))
  }
  if relation is Some(target) {
    guard @graph.selector_form(selector) is @graph.RelationIds(..) &&
      @pipeline.input_occurrence_at(step, index) is Some(edge) &&
      edge.role == role &&
      edge.target == target else {
      return Err(ForeignOccurrence(site.step))
    }
  } else if @graph.selector_form(selector) is @graph.RelationIds(..) {
    return Err(ForeignOccurrence(site.step))
  }
  let rule = match pending {
    AdmitSelectorIdentities => AdmitIdentities
    RevalidateSelectorReferences => RevalidateReferences
    DeduplicateSelectorIdentities => DeduplicateIdentities
    RequireSelectorMembership => RequireMembership
    EvaluateSelectorPredicate => EvaluateNodePredicate
    ResolveSelectorResources => RequireSelectorResources
  }
  Ok(
    Some(
      GraphSelectorExecution({
        site,
        step,
        graph,
        relation,
        selector,
        rule,
        policy,
      }),
    ),
  )
}
