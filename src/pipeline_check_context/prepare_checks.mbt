///|
pub enum PrepareChecksIssue {
  InvalidLimits
  BudgetExceeded
  Validation(ExpressionValidationIssue)
  Patterns(PatternIssue)
  TextBounds(TextBoundsIssue)
  ExpressionProfiles(ExpressionProfilesIssue)
  Assembly(PreparationIssue)
  OperationProfiles(OperationProfilesIssue)
}

///|
/// Derive all expression checks from the source branch's selected policy owner.
/// Static operation resolution and exhaustive obligation closure remain separate.
pub fn prepare_program_checks(
  sources : SourceProducerContext,
  expression_profiles : ExpressionProfiles,
  operation_profiles : PureOperationProfiles,
  limits : PreparationBudget,
  max_policy_depth~ : Int,
  max_requirements~ : Int,
  max_regex_depth~ : Int,
  property_graph? : Bool = false,
) -> Result[OperationProfileChecks, PrepareChecksIssue] {
  if limits.work < 0 ||
    limits.text_bytes < 0 ||
    limits.source_value_nodes < 0 ||
    limits.source_comparison_pairs < 0 ||
    limits.policy_nodes < 0 ||
    limits.local_input_nodes < 0 ||
    limits.pattern_ast_bytes < 0 ||
    limits.pattern_ast_nodes < 0 ||
    max_policy_depth < 0 ||
    max_requirements < 0 ||
    max_regex_depth < 0 ||
    max_regex_depth > 1073741822 {
    return Err(InvalidLimits)
  }
  let selected = sources.capacity.context.policy
  let requests = sources.capacity.context.rows.requests
  if sources.work >= limits.work ||
    requests.text > limits.text_bytes ||
    requests.nodes > limits.source_value_nodes ||
    requests.pairs > limits.source_comparison_pairs ||
    selected.usage.policy_nodes > limits.policy_nodes ||
    selected.usage.local_input_nodes > limits.local_input_nodes {
    return Err(BudgetExceeded)
  }
  // Reserve the source-only branch and final owner join. Only the exact shared
  // selected-policy prefix is credited to the expression branch.
  let work = limits.work - (sources.work - selected.usage.work) - 1
  let text = limits.text_bytes - requests.text
  let validation = match
    prepare_expression_validation(selected, {
      max_work: work,
      max_text_bytes: text,
      max_policy_nodes: limits.policy_nodes,
      max_policy_depth,
      max_requirements,
    }) {
    Ok(v) => v
    Err(e) => return Err(Validation(e))
  }
  let patterns = match
    check_patterns(validation, {
      max_work: work,
      max_text_bytes: text,
      max_ast_bytes: limits.pattern_ast_bytes,
      max_ast_nodes: limits.pattern_ast_nodes,
      max_regex_depth,
    }) {
    Ok(v) => v
    Err(e) => return Err(Patterns(e))
  }
  let bounds = match
    check_text_bounds(patterns, { max_work: work, max_text_bytes: text, }) {
    Ok(v) => v
    Err(e) => return Err(TextBounds(e))
  }
  let profiles = match
    check_expression_profiles(
      validation,
      expression_profiles,
      validation.usage.work + (work - bounds.usage.work),
    ) {
    Ok(v) => v
    Err(e) => return Err(ExpressionProfiles(e))
  }
  let preparation = match
    assemble_preparation(sources, bounds, profiles, limits) {
    Ok(v) => v
    Err(e) => return Err(Assembly(e))
  }
  match
    check_operation_profiles(
      preparation,
      operation_profiles,
      limits.work,
      property_graph~,
    ) {
    Ok(v) => Ok(v)
    Err(e) => Err(OperationProfiles(e))
  }
}
