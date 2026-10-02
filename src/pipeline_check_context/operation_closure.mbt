///|
pub enum OperationClosureIssue {
  InvalidLimits
  BudgetExceeded
  IncompleteResolution(Int)
  ForeignOccurrence(Int)
}

///|
pub(all) enum OperationDisposition {
  StaticResolution(OperationResolution)
  ExecutionCheck(OperationExecutionCheck)
}

///|
struct ProgramOperationClosure {
  index : ProgramOperationResolutionIndex
  entries : Array[OperationDisposition]
  work : Int
}

///|
/// Close this operation inventory, not the Program's other obligation families.
/// Execution bindings remain mandatory future checks, never success receipts.
pub fn close_program_operations(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_requirements : Int,
) -> Result[ProgramOperationClosure, OperationClosureIssue] {
  if max_work < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let count = index.requirements.entries.length()
  if index.work >= max_work ||
    count > max_requirements ||
    count > max_work - index.work - 1 {
    return Err(BudgetExceeded)
  }
  if index.states.length() != count {
    return Err(IncompleteResolution(count))
  }
  let entries = []
  for i in 0..<count {
    let expected = index.requirements.entries[i]
    let disposition = match index.states[i] {
      Unresolved => return Err(IncompleteResolution(i))
      Resolved(resolution) => {
        let (position, site) = resolution_occurrence(resolution)
        if position != i || !physical_equal(site, expected) {
          return Err(ForeignOccurrence(i))
        }
        StaticResolution(resolution)
      }
      Execution(check) => {
        // Exhaustive over typed execution bindings. A new variant must provide
        // its owned subject here instead of defaulting to a runtime permission.
        let site = match check {
          NestValues(v) => v.site
          NestItems(v) => v.site
          NestExecution(v) => v.site
          GraphSelectorExecution(v) => v.site
          GraphMatchExecution(v) => v.site
          VectorExecution(v) => v.site
          NearestExecution(v) => v.site
          PoolExecution(v) => v.site
          RankingExecution(v) => v.site
          TextRankExecution(v) => v.site
          TraversalLimits(v) => v.site
          TraversalOutputGuard(v) => v.site
          TraversalExecution(v) => v.site
          PropertyGraphConstructionExecution(v) => v.site
          GraphProjection(v) => v.site
          GraphProjectionOutput(v) => v.site
          AsOfExecution(v) => v.site
          IntervalExecution(v) => v.site
          IntervalSearch(v) => v.site
          AsOfSearch(v) => v.site
          SessionExecution(v) => v.site
          SeriesExecution(v) => v.site
          CalendarExecution(v) => v.site
          SequenceExecution(v) => v.site
          SequenceMatch(v) => v.site
          SequenceLimits(v) => v.site
          EventEnvelope(v) => v.site
          EventExecution(v) => v.site
          WatermarkExecution(v) => v.site
          WindowMembershipLimit(v) => v.site
          AnalyticExecution(v) => v.site
          WindowExecution(v) => v.site
          AnalyticEnvelope(v) => v.site
          ExpansionExecution(v) => v.site
          JsonPickExecution(v) => v.site
          LagExecution(v) => v.site
          TopKExecution(v) => v.site
          GroupExecution(v) => v.site
          PivotExecution(v) => v.site
          RowAssertion(v) => v.site
          DedupeTopTie(v) => v.site
          ValuesPublication(v) => v.site
          JoinOutputLimit(v) => v.site
          JoinRowOrder(v) => v.site
          JoinInputValidation(v) => v.site
          JoinIdentity(v) => v.site
          CrossJoinRows(v) => v.site
          CrossJoinIdentity(v) => v.site
          AppendRows(v) => v.site
          SetRows(v) => v.site
        }
        if !physical_equal(site, expected) {
          return Err(ForeignOccurrence(i))
        }
        ExecutionCheck(check)
      }
    }
    entries.push(disposition)
  }
  Ok({ index, entries, work: index.work + count + 1, })
}

///|
pub fn operation_closure_index(
  v : ProgramOperationClosure,
) -> ProgramOperationResolutionIndex {
  v.index
}

///|
pub fn operation_closure_count(v : ProgramOperationClosure) -> Int {
  v.entries.length()
}

///|
pub fn operation_closure_at(
  v : ProgramOperationClosure,
  index : Int,
) -> OperationDisposition? {
  v.entries.get(index)
}

///|
pub fn operation_closure_work(v : ProgramOperationClosure) -> Int {
  v.work
}
