///|
priv enum TargetRowCandidatesIssue {
  CandidateBudget
  CandidateTarget(@step_bounds.TargetRowsIssue)
  CandidateMembership(@capacity.TargetMembershipIssue)
}

///|
// Search the exact owned closure, not only the consumer's claim table.
// Retain every admitted occurrence, including repeated imported producers.
fn collect_target_row_candidates(
  closure : @capacity.ApplicationClosure,
  pipeline : @pipeline.CheckedPipeline,
  target : @pipeline.Target,
  consumer : Int?,
  max_work : Int,
  max_candidates : Int,
) -> Result[(Array[@capacity.TargetMembership], Int), TargetRowCandidatesIssue] {
  if max_work < 0 || max_candidates < 0 {
    return Err(CandidateBudget)
  }
  let mut work = 0
  let visits = @pipeline.contextual_closure_count(
    @capacity.application_closure_orders(closure),
  )
  let mut consumer_visit = consumer
  if consumer_visit is None {
    for visit in 0..<visits {
      if work == max_work {
        return Err(CandidateBudget)
      }
      work += 1
      let source = @capacity.application_coverage_sources(
        @capacity.application_closure_at(closure, visit).unwrap(),
      )
      if physical_equal(
          pipeline,
          @capacity.checked_pipeline(@capacity.source_coverage_graph(source)),
        ) {
        consumer_visit = Some(visit)
        break
      }
    }
  }
  guard consumer_visit is Some(consumer_visit) &&
    @capacity.application_closure_at(closure, consumer_visit)
    is Some(consumer_coverage) &&
    physical_equal(
      pipeline,
      @capacity.checked_pipeline(
        @capacity.source_coverage_graph(
          @capacity.application_coverage_sources(consumer_coverage),
        ),
      ),
    ) else {
    return Err(CandidateMembership(@capacity.ForeignConsumer))
  }
  let out = []
  for visit in 0..<visits {
    if work == max_work {
      return Err(CandidateBudget)
    }
    work += 1
    let source = @capacity.application_coverage_sources(
      @capacity.application_closure_at(closure, visit).unwrap(),
    )
    let applications = @capacity.source_coverage_program(source)
    let slots = @wire.claim_count(
      @wire.program_claim_arithmetic(
        @step_bounds.application_claims(applications),
      ),
    )
    for claim in 0..<slots {
      if work == max_work {
        return Err(CandidateBudget)
      }
      work += 1
      guard @step_bounds.application_at(applications, claim) is Some(bound) else {
        continue
      }
      let (result, used) = @step_bounds.check_target_rows_usage(
        pipeline,
        target,
        bound,
        max_work - work,
      )
      work += used
      match result {
        Ok(rows) => {
          if out.length() == max_candidates || work == max_work {
            return Err(CandidateBudget)
          }
          // Reserve retaining and consuming this result, in addition to the
          // visit, sparse slot and target traversal charges.
          work += 1
          match
            @capacity.bind_producer_target_membership(
              closure, rows, consumer_visit, visit, claim,
            ) {
            Ok(membership) => out.push(membership)
            Err(e) => return Err(CandidateMembership(e))
          }
        }
        Err(
          @step_bounds.WrongUnit
          | @step_bounds.UnrelatedBound
          | @step_bounds.MissingProducer
        ) => ()
        Err(@step_bounds.WorkLimit) => return Err(CandidateBudget)
        Err(e) => return Err(CandidateTarget(e))
      }
    }
  }
  Ok((out, work))
}
