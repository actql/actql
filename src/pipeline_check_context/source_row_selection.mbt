///|
// Keep candidate membership, including its consumer visit and original sparse
// claim index. Selection does not make observation or enforcement claims.
fn select_source_acquisition_rows(
  requests : SourceRequestContexts,
  max_work : Int,
) -> Result[
  (SourceRowContexts, Array[Array[@capacity.TargetMembership]]),
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
    let rows = []
    let owned = []
    let selected_rows : Map[(Bool, Int), @capacity.TargetMembership] = Map([])
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
        rows.push(@capacity.target_membership_rows(selected))
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
        ) {
        Ok(value) => value
        Err(CandidateBudget) => return Err(BudgetExceeded)
        Err(CandidateTarget(error)) =>
          return Err(Rows(Target(stage, index, error)))
        Err(CandidateMembership(error)) =>
          return Err(Producers(Membership(stage, index, error)))
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
        if value <= 0 {
          continue
        }
        let cid = @wire.cid(
          @wire.program_proof_witness(
            @step_bounds.checked_proof(@step_bounds.target_rows_bound(bound)),
          ),
        )
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
      guard best is Some(selected) else {
        let join = @sourceviews.keyed_join_at(joins, index).unwrap()
        let step = @pipeline.step_at(
          pipeline,
          @sourceviews.keyed_join_step(join),
        ).unwrap()
        return Err(Rows(MissingPositiveBound(stage, index, step.source)))
      }
      selected_rows[key] = selected
      rows.push(@capacity.target_membership_rows(selected))
      owned.push(selected)
    }
    let checked = match
      @sourceviews.check_keyed_row_bounds(facts, rows, max_work - work) {
      Ok(value) => value
      Err(error) => return Err(Rows(Stage(stage, error)))
    }
    work += @sourceviews.keyed_rows_work(checked)
    stages.push(checked)
    memberships.push(owned)
  }
  Ok(({ requests, stages, work, }, memberships))
}
