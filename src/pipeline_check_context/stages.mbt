///|
pub(all) enum StageIssue {
  InvalidLimits
  ForeignOperations
  StageCount
  ForeignResults(Int)
  ForeignBindings(Int, Int)
  ForeignPolicy(Int)
  BudgetExceeded(Int)
} derive(Eq, Debug)

///|
struct StageContexts {
  operations : @stages.BoundOperations
  results : @stage_results.Checked
  contexts : Array[BoundParameters]
  policy : @policy.Policy
  work : Int
  text : Int
  values_claims : Map[Int, Array[(@pipeline.CheckedPipeline, Array[Int?])]]?
  generated_bytes : Int
  generated_nodes : Int
}

///|
/// Attach all source-bound stage Results to their exact checked contexts and
/// selected bindings/policy. This does not close input/import wiring, static
/// profile discharge or persistent Program identities.
pub fn attach_stage_contexts(
  operations : @stages.BoundOperations,
  results : @stage_results.Checked,
  contexts : Array[BoundParameters],
  selected_policy : @policy.Policy,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[StageContexts, StageIssue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let collected = @stages.bound_operations(operations)
  if !physical_equal(collected, @stage_results.operations(results)) {
    return Err(ForeignOperations)
  }
  let source = @stages.operations_source(collected)
  if contexts.length() != @stages.stage_count(source) {
    return Err(StageCount)
  }
  let selected_values = @references.bound_values(
    @stages.bound_program_index(operations),
  )
  let base = @stages.bindings_usage(operations)
  let result_usage = @stage_results.usage(results)
  // Both children retain the same operation collection; charge it once.
  let result_work = result_usage.work - @stages.operations_usage(collected).work
  let mut work = base.work
  let mut text = base.direct_text_bytes
  if work > max_work ||
    text > max_text_bytes ||
    result_work > max_work - work ||
    result_usage.text_bytes > max_text_bytes - text {
    return Err(BudgetExceeded(0))
  }
  work += result_work
  text += result_usage.text_bytes
  let owned : Array[BoundParameters] = []
  for i in 0..<contexts.length() {
    let bound = contexts[i]
    let context = bound.context
    if !physical_equal(
        context.results,
        @stage_results.stage_at(results, i).unwrap(),
      ) {
      return Err(ForeignResults(i))
    }
    if @policy.cid(@capacity.application_closure_policy(context.capacity)) !=
      @policy.cid(selected_policy) {
      return Err(ForeignPolicy(i))
    }
    if work == max_work ||
      bound.work > max_work - work - 1 ||
      bound.text > max_text_bytes - text {
      return Err(BudgetExceeded(i))
    }
    work += 1 + bound.work
    text += bound.text
    for visit in 0..<bound.visits.length() {
      if work == max_work {
        return Err(BudgetExceeded(i))
      }
      work += 1
      let values = @pipeline.bound_guard_bindings(
        @pipeline.bound_guard_closure_at(context.guards, visit).unwrap(),
      )
      if values is Some(values) && !physical_equal(values, selected_values) {
        return Err(ForeignBindings(i, visit))
      }
    }
    owned.push(bound)
  }
  Ok({
    operations,
    results,
    contexts: owned,
    policy: selected_policy,
    work,
    text,
    values_claims: None,
    generated_bytes: 0,
    generated_nodes: 0,
  })
}

///|
pub fn stage_operations(v : StageContexts) -> @stages.BoundOperations {
  v.operations
}

///|
pub fn stage_results(v : StageContexts) -> @stage_results.Checked {
  v.results
}

///|
pub fn stage_context_at(v : StageContexts, index : Int) -> BoundParameters? {
  v.contexts.get(index)
}

///|
pub fn stage_policy(v : StageContexts) -> @policy.Policy {
  v.policy
}

///|
pub fn stage_usage(v : StageContexts) -> (Int, Int) {
  (v.work, v.text)
}
