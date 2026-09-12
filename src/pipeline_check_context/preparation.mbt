///|
/// Independent accounting dimensions; none is a physical heap ceiling.
pub(all) struct PreparationBudget {
  work : Int
  text_bytes : Int
  source_value_nodes : Int
  source_comparison_pairs : Int
  policy_nodes : Int
  local_input_nodes : Int
  pattern_ast_bytes : Int
  pattern_ast_nodes : Int
} derive(Eq, Debug)

///|
pub(all) enum PreparationIssue {
  InvalidLimits
  ForeignSelectedPolicy
  BudgetExceeded
} derive(Eq, Debug)

///|
/// Owned assembly, not a lowering-ready Program or an execution permit.
struct ProgramPreparation {
  sources : SourceProducerContext
  expressions : TextBoundsChecks
  usage : PreparationBudget
}

///|
/// Join source and expression checks at their exact common selected policy.
/// Retains all unresolved bindings, profile checks and runtime obligations.
pub fn assemble_preparation(
  sources : SourceProducerContext,
  expressions : TextBoundsChecks,
  limits : PreparationBudget,
) -> Result[ProgramPreparation, PreparationIssue] {
  if limits.work < 0 ||
    limits.text_bytes < 0 ||
    limits.source_value_nodes < 0 ||
    limits.source_comparison_pairs < 0 ||
    limits.policy_nodes < 0 ||
    limits.local_input_nodes < 0 ||
    limits.pattern_ast_bytes < 0 ||
    limits.pattern_ast_nodes < 0 {
    return Err(InvalidLimits)
  }
  let validation = expressions.patterns.context
  let selected = sources.capacity.context.policy
  if !physical_equal(selected, validation.selected) {
    return Err(ForeignSelectedPolicy)
  }
  // The exact shared selected-policy preparation is counted once. Each branch
  // retains monotonic usage, and subtraction precedes bounded addition.
  let extra_work = expressions.usage.work - selected.usage.work
  let requests = sources.capacity.context.rows.requests
  if sources.work >= limits.work ||
    extra_work > limits.work - sources.work - 1 ||
    expressions.usage.text_bytes > limits.text_bytes ||
    requests.text > limits.text_bytes - expressions.usage.text_bytes ||
    requests.nodes > limits.source_value_nodes ||
    requests.pairs > limits.source_comparison_pairs ||
    validation.usage.policy_nodes > limits.policy_nodes ||
    selected.usage.local_input_nodes > limits.local_input_nodes ||
    expressions.patterns.usage.ast_bytes > limits.pattern_ast_bytes ||
    expressions.patterns.usage.ast_nodes > limits.pattern_ast_nodes {
    return Err(BudgetExceeded)
  }
  Ok({
    sources,
    expressions,
    usage: {
      work: sources.work + extra_work + 1,
      text_bytes: expressions.usage.text_bytes + requests.text,
      source_value_nodes: requests.nodes,
      source_comparison_pairs: requests.pairs,
      policy_nodes: validation.usage.policy_nodes,
      local_input_nodes: selected.usage.local_input_nodes,
      pattern_ast_bytes: expressions.patterns.usage.ast_bytes,
      pattern_ast_nodes: expressions.patterns.usage.ast_nodes,
    },
  })
}

///|
pub fn preparation_sources(v : ProgramPreparation) -> SourceProducerContext {
  v.sources
}

///|
pub fn preparation_expressions(v : ProgramPreparation) -> TextBoundsChecks {
  v.expressions
}

///|
pub fn preparation_usage(v : ProgramPreparation) -> PreparationBudget {
  v.usage
}
