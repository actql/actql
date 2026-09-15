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
  row_ranges : Array[(Int, Int)]
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
  let stages = owner.incoming.identity.contexts
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
  let row_ranges = []
  for publication in entries {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let first_row = rows.length()
    let closure = publication.context.capacity
    let pipeline = @results.pipeline(publication.context.results)
    let target = @results.target(@results.port_result(publication.port))
    let (candidates, used) = match
      collect_target_row_candidates(
        closure,
        pipeline,
        target,
        None,
        max_work - work,
        max_requirements - entries.length() - rows.length(),
      ) {
      Ok(found) => found
      Err(CandidateBudget) => return Err(BudgetExceeded)
      Err(CandidateTarget(e)) =>
        return Err(RowTarget(publication.stage, publication.result_index, e))
      Err(CandidateMembership(e)) =>
        return Err(
          RowMembership(publication.stage, publication.result_index, e),
        )
    }
    work += used
    for membership in candidates {
      rows.push({ publication, membership, })
    }
    row_ranges.push((first_row, rows.length() - first_row))
  }
  Ok({ owner, entries, rows, row_ranges, work, })
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
