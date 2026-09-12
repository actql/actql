///|
pub(all) enum KeyedRowsIssue {
  InvalidLimits
  CountMismatch
  WorkLimit(Int)
  ForeignPipeline(Int)
  WrongTarget(Int)
  NonPositiveBound(Int)
} derive(Eq, Debug)

///|
struct KeyedRowBounds {
  facts : CheckedKeyedFacts
  bounds : Array[@capacity.TargetRows]
  work : Int
}

///|
/// Requires one exact left-target proof per keyed join, in checked join order.
/// Does not establish producer closure, Host bounds or runtime response validity.
pub fn check_keyed_row_bounds(
  facts : CheckedKeyedFacts,
  bounds : Array[@capacity.TargetRows],
  max_work : Int,
) -> Result[KeyedRowBounds, KeyedRowsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if bounds.length() != facts.entries.length() {
    return Err(CountMismatch)
  }
  let pipeline = @collection.pipeline(
    @stages.collection(facts.joins.requests.uses.attachment.stage),
  )
  let mut work = 0
  let owned = []
  for i in 0..<bounds.length() {
    if work >= max_work {
      return Err(WorkLimit(i))
    }
    work += 1
    let bound = bounds[i]
    let traversal = @capacity.target_rows_work(bound)
    if traversal > max_work - work {
      return Err(WorkLimit(i))
    }
    work += traversal
    if !physical_equal(@capacity.target_rows_pipeline(bound), pipeline) {
      return Err(ForeignPipeline(i))
    }
    if @capacity.target_rows_target(bound) != facts.entries[i].join.left {
      return Err(WrongTarget(i))
    }
    if @capacity.target_rows_value(bound) <= 0 {
      return Err(NonPositiveBound(i))
    }
    owned.push(bound)
  }
  Ok({ facts, bounds: owned, work, })
}

///|
pub fn keyed_rows_facts(v : KeyedRowBounds) -> CheckedKeyedFacts {
  v.facts
}

///|
pub fn keyed_rows_work(v : KeyedRowBounds) -> Int {
  v.work
}

///|
pub fn keyed_rows_count(v : KeyedRowBounds) -> Int {
  v.bounds.length()
}

///|
pub fn keyed_rows_at(v : KeyedRowBounds, i : Int) -> @capacity.TargetRows? {
  v.bounds.get(i)
}
