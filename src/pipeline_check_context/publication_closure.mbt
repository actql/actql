///|
pub enum PublicationClosureIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOrders(Int, Int)
  MissingStage(Int)
  RowTarget(Int, Int, @step_bounds.TargetRowsIssue)
  RowMembership(Int, Int, @capacity.TargetMembershipIssue)
}

///|
pub struct PublicationResolution {
  stage : Int
  result_index : Int
  port : @results.ResultPort
  context : PipelineContext
  obligation : @results.Obligation
}

///|
struct ProgramPublicationClosure {
  owner : ProgramIncomingLinks
  entries : Array[PublicationResolution]
  rows : Array[PublicationRowCandidate]
  work : Int
}

///|
/// Applicable Program row evidence for one exact Result. This is a candidate,
/// not a selected minimum or evidence of successful publication enforcement.
pub struct PublicationRowCandidate {
  publication : PublicationResolution
  membership : @capacity.TargetMembership
}

///|
/// Retain the already checked publication-order decisions for every Result.
/// Conditional input checks and runtime publication enforcement are not receipts.
pub fn close_program_publications(
  owner : ProgramIncomingLinks,
  max_work : Int,
  max_requirements : Int,
) -> Result[ProgramPublicationClosure, PublicationClosureIssue] {
  if max_work < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let stages = owner.incoming.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let wiring = owner.incoming.wiring
  if owner.work >= max_work ||
    stages.contexts.length() > max_work - owner.work - 1 {
    return Err(BudgetExceeded)
  }
  let mut work = owner.work + stages.contexts.length() + 1
  let entries = []
  for stage in 0..<stages.contexts.length() {
    guard @stage_results.wiring_stage_at(wiring, stage) is Some(producer) else {
      return Err(MissingStage(stage))
    }
    let ports = @stage_results.stage_port_publications(producer)
    let context = stages.contexts[stage].context
    let count = @results.port_count(ports)
    if count > max_work - work {
      return Err(BudgetExceeded)
    }
    work += count
    for result_index in 0..<count {
      let port = @results.port_at(ports, result_index).unwrap()
      if !physical_equal(@results.port_orders(port), context.orders) {
        return Err(ForeignOrders(stage, result_index))
      }
      // The public Result grammar currently has one bounded order obligation.
      // Match its enum exhaustively so new kinds cannot inherit this discharge.
      let obligations = @results.pending_validations(@results.port_result(port))
      if obligations.length() > max_work - work ||
        obligations.length() > max_requirements - entries.length() {
        return Err(BudgetExceeded)
      }
      work += obligations.length()
      for obligation in obligations {
        match obligation {
          @results.TotalDeterministicOrder => {
            let order = @results.port_order(port)
            if @results.publication_result_index(order) != result_index ||
              !physical_equal(
                @results.publication_results(order),
                context.results,
              ) {
              return Err(ForeignOrders(stage, result_index))
            }
          }
        }
        entries.push({ stage, result_index, port, context, obligation, })
      }
    }
  }
  let rows = []
  for publication in entries {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let closure = publication.context.capacity
    let pipeline = @results.pipeline(publication.context.results)
    let target = @results.target(@results.port_result(publication.port))
    let visits = @pipeline.contextual_closure_count(
      @capacity.application_closure_orders(closure),
    )
    for visit in 0..<visits {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let coverage = @capacity.application_closure_at(closure, visit).unwrap()
      let source = @capacity.application_coverage_sources(coverage)
      // A proof may belong to a predecessor, but the consuming occurrence
      // must be this Result's pipeline. Its membership records the producer.
      if !physical_equal(
          pipeline,
          @capacity.checked_pipeline(@capacity.source_coverage_graph(source)),
        ) {
        continue
      }
      let applications = @capacity.source_coverage_program(source)
      let mut claim = 0
      while true {
        if work == max_work {
          return Err(BudgetExceeded)
        }
        work += 1
        guard @step_bounds.application_at(applications, claim) is Some(bound) else {
          break
        }
        let (result, used) = @step_bounds.check_target_rows_usage(
          pipeline,
          target,
          bound,
          max_work - work,
        )
        work += used
        match result {
          Ok(target_rows) => {
            if rows.length() >= max_requirements - entries.length() {
              return Err(BudgetExceeded)
            }
            let membership = match
              @capacity.bind_target_membership(
                closure, target_rows, visit, claim,
              ) {
              Ok(v) => v
              Err(e) =>
                return Err(
                  RowMembership(publication.stage, publication.result_index, e),
                )
            }
            rows.push({ publication, membership, })
          }
          Err(
            @step_bounds.WrongUnit
            | @step_bounds.UnrelatedBound
            | @step_bounds.MissingProducer
          ) => ()
          Err(@step_bounds.WorkLimit) => return Err(BudgetExceeded)
          Err(e) =>
            return Err(
              RowTarget(publication.stage, publication.result_index, e),
            )
        }
        claim += 1
      }
    }
  }
  Ok({ owner, entries, rows, work, })
}

///|
pub fn publication_row_candidate_count(v : ProgramPublicationClosure) -> Int {
  v.rows.length()
}

///|
pub fn publication_row_candidate_at(
  v : ProgramPublicationClosure,
  index : Int,
) -> PublicationRowCandidate? {
  v.rows.get(index)
}

///|
pub fn publication_closure_owner(
  v : ProgramPublicationClosure,
) -> ProgramIncomingLinks {
  v.owner
}

///|
pub fn publication_closure_count(v : ProgramPublicationClosure) -> Int {
  v.entries.length()
}

///|
pub fn publication_closure_at(
  v : ProgramPublicationClosure,
  index : Int,
) -> PublicationResolution? {
  v.entries.get(index)
}

///|
pub fn publication_closure_work(v : ProgramPublicationClosure) -> Int {
  v.work
}
