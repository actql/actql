///|
// Keep candidate membership, including its consumer visit and original sparse
// claim index. Selection does not make observation or enforcement claims.
fn select_source_acquisition_rows(
  requests : SourceRequestContexts,
  max_work : Int,
) -> Result[
  (SourceRowContexts, Array[Array[@capacity.TargetMembership?]]),
  PrepareSourcesIssue,
] {
  let mut work = requests.work
  if work > max_work {
    return Err(BudgetExceeded)
  }
  let operations = @stages.bound_operations(requests.contexts.operations)
  let stages = []
  let memberships = []
  for stage, facts in requests.keyed_facts {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let joins = @sourceviews.keyed_facts_joins(facts)
    let pipeline = @parameter_slots.pipeline(
      @stages.collection(
        @stages.operations_stage_at(operations, stage).unwrap(),
      ),
    )
    let closure = requests.contexts.contexts[stage].context.capacity
    let rows : Array[@step_bounds.TargetRows?] = []
    let owned : Array[@capacity.TargetMembership?] = []
    let selected_rows : Map[(Bool, Int), @capacity.TargetMembership?] = Map([])
    for index in 0..<@sourceviews.keyed_join_count(joins) {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let target = @sourceviews.keyed_join_left(
        @sourceviews.keyed_join_at(joins, index).unwrap(),
      )
      let key = match target {
        @pipeline.Input(i) => (false, i)
        @pipeline.Step(i) => (true, i)
      }
      if selected_rows.get(key) is Some(selected) {
        rows.push(selected.map(@capacity.target_membership_rows))
        owned.push(selected)
        continue
      }
      let (candidates, used) = match
        collect_target_row_candidates(
          closure,
          pipeline,
          target,
          None,
          max_work - work,
          max_work - work,
          source_requests=requests.inputs.sourceviews.map(views => {
            @sourceviews.catalog(@sourceviews.pipeline_resolution(views))
          }),
        ) {
        Ok(value) => value
        Err(CandidateBudget) => return Err(BudgetExceeded)
        Err(CandidateTarget(error)) =>
          return Err(Rows(Target(stage, index, error)))
        Err(CandidateMembership(error)) =>
          return Err(Producers(Membership(stage, index, error)))
        Err(CandidateSourceInput(error)) =>
          return Err(Rows(SourceInput(stage, index, error)))
      }
      work += used
      let mut best : @capacity.TargetMembership? = None
      let mut best_value = 0L
      let mut best_cid = ""
      for candidate in candidates {
        if work == max_work {
          return Err(BudgetExceeded)
        }
        work += 1
        let bound = @capacity.target_membership_rows(candidate)
        let value = @step_bounds.target_rows_value(bound)
        let cid = @step_bounds.target_rows_candidate_cid(bound)
        if cid.length() > max_work - work {
          return Err(BudgetExceeded)
        }
        work += cid.length()
        if best_cid.length() > max_work - work {
          return Err(BudgetExceeded)
        }
        work += best_cid.length()
        if best is None ||
          value < best_value ||
          (value == best_value && cid < best_cid) {
          best = Some(candidate)
          best_value = value
          best_cid = cid
        }
      }
      // Absence is retained once for this exact target, never replaced by a
      // Host ceiling, zero estimate or a second traversal of the same target.
      selected_rows[key] = best
      rows.push(best.map(@capacity.target_membership_rows))
      owned.push(best)
    }
    let checked = match
      @sourceviews.check_keyed_row_estimates(facts, rows, max_work - work) {
      Ok(value) => value
      Err(error) => return Err(Rows(Stage(stage, error)))
    }
    work += @sourceviews.keyed_rows_work(checked)
    stages.push(checked)
    memberships.push(owned)
  }
  Ok(({ requests, stages, work, }, memberships))
}
