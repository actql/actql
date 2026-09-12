///|
pub enum PreparedStagesIssue {
  InvalidLimits
  StageCount
  BudgetExceeded
  Stage(Int, PreparedStageIssue)
  Assembly(StageIssue)
}

///|
/// Construct every Stage context from one Local preparation. This shares the
/// Stage integration budget, not the complete source-admission budget. Capacity
/// applications remain explicit; no missing proofs are synthesized.
pub fn check_prepared_local_stages(
  prepared : @stage_results.PreparedLocalSource,
  applications : Array[Array[@capacity.ApplicationCoverage]],
  selected_policy : @policy.Policy,
  max_work~ : Int,
  max_text_bytes~ : Int,
  proof_owners? : Array[Array[(Int, Int, Int)]]? = None,
  input_owners? : Array[Array[(Int, Int, Int, Int)]]? = None,
) -> Result[StageContexts, PreparedStagesIssue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let operations = @stage_results.local_source_operations(prepared)
  let results = @stage_results.local_source_results(prepared)
  let count = @stages.stage_count(@stage_results.local_source_source(prepared))
  if applications.length() != count ||
    (proof_owners is Some(v) && v.length() != count) ||
    (input_owners is Some(v) && v.length() != count) {
    return Err(StageCount)
  }
  let base = @stages.bindings_usage(operations)
  let result_usage = @stage_results.usage(results)
  let shared = @stages.operations_usage(@stages.bound_operations(operations)).work
  let result_work = result_usage.work - shared
  if base.work > max_work ||
    result_work > max_work - base.work ||
    base.direct_text_bytes > max_text_bytes ||
    result_usage.text_bytes > max_text_bytes - base.direct_text_bytes {
    return Err(BudgetExceeded)
  }
  let mut work = max_work - base.work - result_work
  let mut text = max_text_bytes -
    base.direct_text_bytes -
    result_usage.text_bytes
  // Reserve gathering and the final Stage owner-join visits before allocation.
  if count > work / 2 {
    return Err(BudgetExceeded)
  }
  work -= count * 2
  let contexts = []
  for i in 0..<count {
    let checked = match
      check_prepared_local_stage(
        prepared,
        i,
        applications[i],
        selected_policy,
        max_work=work,
        max_text_bytes=text,
        proof_owners=match proof_owners {
          None => []
          Some(v) => v[i]
        },
        input_owners=match input_owners {
          None => []
          Some(v) => v[i]
        },
      ) {
      Ok(v) => v
      Err(e) => return Err(Stage(i, e))
    }
    work -= checked.work
    text -= checked.text
    // attach_stage_contexts verifies each retained producer's binding owner.
    if checked.visits.length() > work {
      return Err(BudgetExceeded)
    }
    work -= checked.visits.length()
    contexts.push(checked)
  }
  match
    attach_stage_contexts(
      operations,
      results,
      contexts,
      selected_policy,
      max_work=max_work - count,
      max_text_bytes~,
    ) {
    Ok(v) => Ok({ ..v, work: v.work + count, })
    Err(e) => Err(Assembly(e))
  }
}
