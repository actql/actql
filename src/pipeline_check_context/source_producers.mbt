///|
pub enum SourceProducerIssue {
  InvalidLimits
  StageCountMismatch
  JoinCountMismatch(Int)
  BudgetExceeded
  Membership(Int, Int, @capacity.TargetMembershipIssue)
}

///|
struct SourceProducerContext {
  capacity : SourceCapacityContext
  memberships : Array[Array[@capacity.TargetMembership]]
  work : Int
}

///|
/// Connect each acquisition's left bound to the exact admitted stage closure.
/// Locations only select candidates; no caller-supplied closure is accepted.
pub fn bind_source_producers(
  capacity : SourceCapacityContext,
  locations : Array[Array[(Int, Int)]],
  max_work : Int,
) -> Result[SourceProducerContext, SourceProducerIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if locations.length() != capacity.stages.length() {
    return Err(StageCountMismatch)
  }
  let mut work = capacity.work
  if work > max_work {
    return Err(BudgetExceeded)
  }
  let stages = capacity.context.policy.context.wired.stages
  let memberships = []
  for i in 0..<locations.length() {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let bounds = @sourceviews.lookup_bounds_rows(capacity.stages[i])
    if locations[i].length() != @sourceviews.keyed_rows_count(bounds) {
      return Err(JoinCountMismatch(i))
    }
    let closure = stages.contexts[i].context.capacity
    let owned = []
    for j in 0..<locations[i].length() {
      if work >= max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let (visit, claim) = locations[i][j]
      let result = match
        @capacity.bind_target_membership(
          closure,
          @sourceviews.keyed_rows_at(bounds, j).unwrap(),
          visit,
          claim,
        ) {
        Ok(v) => v
        Err(e) => return Err(Membership(i, j, e))
      }
      owned.push(result)
    }
    memberships.push(owned)
  }
  Ok({ capacity, memberships, work, })
}

///|
pub fn source_producer_capacity(
  v : SourceProducerContext,
) -> SourceCapacityContext {
  v.capacity
}

///|
pub fn source_producer_work(v : SourceProducerContext) -> Int {
  v.work
}

///|
pub fn source_producer_at(
  v : SourceProducerContext,
  stage : Int,
  join : Int,
) -> @capacity.TargetMembership? {
  v.memberships.get(stage).bind(entries => entries.get(join))
}
