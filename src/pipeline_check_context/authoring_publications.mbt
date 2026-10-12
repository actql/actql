///|
pub enum AuthoringPublicationIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOrders
  MissingHostCeiling(String)
  RowTarget(Int, @step_bounds.TargetRowsIssue)
  RowMembership(Int, @capacity.TargetMembershipIssue)
  SourceInput(Int, @step_bounds.SourceInputRowsIssue)
}

///|
struct AuthoringPublicationSelection {
  port : @results.ResultPort
  candidates : Array[@capacity.TargetMembership]
  row_host : @policy.Ceiling
  byte_host : @policy.Ceiling
  maximum_rows : Int64
}

///|
/// Complete static publication-order and candidate selection for the retained
/// source-free context. Canonical execution-subject binding and enforcement
/// remain later obligations; this is not whole-Program template verification.
struct AuthoringPublicationChecks {
  owner : PipelineAuthoringContext
  ports : @results.ResultPorts
  selections : Array[AuthoringPublicationSelection]
  work : Int
}

///|
pub fn prepare_authoring_publications(
  owner : PipelineAuthoringContext,
  ports : @results.ResultPorts,
  max_work : Int,
  max_requirements : Int,
) -> Result[AuthoringPublicationChecks, AuthoringPublicationIssue] {
  if max_work < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let context = owner.context
  if !physical_equal(@results.ports_orders(ports), context.orders) {
    return Err(ForeignOrders)
  }
  let (shared, _) = @results.checked_orders_usage(context.orders)
  let port_work = @results.ports_usage(ports).work - shared
  let count = @results.port_count(ports)
  if owner.work >= max_work ||
    port_work > max_work - owner.work - 1 ||
    count > max_work - owner.work - port_work - 1 ||
    count > max_requirements {
    return Err(BudgetExceeded)
  }
  let mut work = owner.work + port_work + count + 1
  let mut requirements = count
  let policy = @capacity.application_closure_policy(context.capacity)
  guard @policy.ceiling(policy, "max_artifact_rows") is Some(row_host) else {
    return Err(MissingHostCeiling("max_artifact_rows"))
  }
  guard @policy.ceiling(policy, "max_artifact_bytes") is Some(byte_host) else {
    return Err(MissingHostCeiling("max_artifact_bytes"))
  }
  let selections = []
  for index in 0..<count {
    let port = @results.port_at(ports, index).unwrap()
    if !physical_equal(@results.port_orders(port), context.orders) {
      return Err(ForeignOrders)
    }
    let result = @results.port_result(port)
    let obligations = @results.pending_validations(result)
    if obligations.length() > max_work - work ||
      obligations.length() > max_requirements - requirements {
      return Err(BudgetExceeded)
    }
    work += obligations.length()
    requirements += obligations.length()
    for obligation in obligations {
      match obligation {
        @results.TotalDeterministicOrder => {
          let order = @results.port_order(port)
          if @results.publication_result_index(order) != index ||
            !physical_equal(
              @results.publication_results(order),
              context.results,
            ) {
            return Err(ForeignOrders)
          }
        }
      }
    }
    let (candidates, used) = match
      collect_target_row_candidates(
        context.capacity,
        @results.pipeline(context.results),
        @results.target(result),
        None,
        max_work - work,
        max_requirements - requirements,
      ) {
      Ok(value) => value
      Err(CandidateBudget) => return Err(BudgetExceeded)
      Err(CandidateTarget(issue)) => return Err(RowTarget(index, issue))
      Err(CandidateSourceInput(issue)) => return Err(SourceInput(index, issue))
      Err(CandidateMembership(issue)) => return Err(RowMembership(index, issue))
    }
    work += used
    requirements += candidates.length()
    // Host row and byte restrictions are distinct candidates and quantities.
    if max_requirements - requirements < 2 ||
      max_work - work < 2 ||
      candidates.length() > max_work - work - 2 {
      return Err(BudgetExceeded)
    }
    work += candidates.length() + 2
    requirements += 2
    let maximum_rows = publication_row_candidate_minimum(
      row_host,
      candidates.length(),
      candidate => candidates[candidate],
    )
    selections.push({ port, candidates, row_host, byte_host, maximum_rows, })
  }
  Ok({ owner, ports, selections, work, })
}

///|
pub fn authoring_publication_owner(
  value : AuthoringPublicationChecks,
) -> PipelineAuthoringContext {
  value.owner
}

///|
pub fn authoring_publication_ports(
  value : AuthoringPublicationChecks,
) -> @results.ResultPorts {
  value.ports
}

///|
pub fn authoring_publication_count(value : AuthoringPublicationChecks) -> Int {
  value.selections.length()
}

///|
pub fn authoring_publication_at(
  value : AuthoringPublicationChecks,
  index : Int,
) -> AuthoringPublicationSelection? {
  value.selections.get(index)
}

///|
pub fn authoring_publication_port(
  value : AuthoringPublicationSelection,
) -> @results.ResultPort {
  value.port
}

///|
pub fn authoring_publication_row_host(
  value : AuthoringPublicationSelection,
) -> @policy.Ceiling {
  value.row_host
}

///|
pub fn authoring_publication_byte_host(
  value : AuthoringPublicationSelection,
) -> @policy.Ceiling {
  value.byte_host
}

///|
pub fn authoring_publication_maximum_rows(
  value : AuthoringPublicationSelection,
) -> Int64 {
  value.maximum_rows
}

///|
pub fn authoring_publication_candidate_count(
  value : AuthoringPublicationSelection,
) -> Int {
  value.candidates.length()
}

///|
pub fn authoring_publication_candidate_at(
  value : AuthoringPublicationSelection,
  index : Int,
) -> @capacity.TargetMembership? {
  value.candidates.get(index)
}

///|
pub fn authoring_publication_work(value : AuthoringPublicationChecks) -> Int {
  value.work
}
