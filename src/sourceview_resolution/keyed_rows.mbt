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
  requirements : Array[KeyedRowRequirement]
  work : Int
}

///|
/// A checked estimate is planning information, never allocation or dispatch
/// permission. An unknown estimate retains the exact original checked join.
pub enum KeyedRowRequirement {
  CheckedEstimate(@capacity.TargetRows)
  RuntimeAdmission(KeyedJoin)
}

///|
/// Compatibility entrance for callers supplying real estimates for every join.
pub fn check_keyed_row_bounds(
  facts : CheckedKeyedFacts,
  bounds : Array[@capacity.TargetRows],
  max_work : Int,
) -> Result[KeyedRowBounds, KeyedRowsIssue] {
  check_keyed_row_estimates(facts, bounds.map(bound => Some(bound)), max_work)
}

///|
/// Validate each supplied estimate against its exact left target. Absence is
/// an explicit runtime admission obligation, not zero, infinity or a proof.
pub fn check_keyed_row_estimates(
  facts : CheckedKeyedFacts,
  bounds : Array[@capacity.TargetRows?],
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
    guard bounds[i] is Some(bound) else {
      owned.push(KeyedRowRequirement::RuntimeAdmission(facts.entries[i].join))
      continue
    }
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
    if @capacity.target_rows_value(bound) < 0 {
      return Err(NonPositiveBound(i))
    }
    owned.push(CheckedEstimate(bound))
  }
  Ok({ facts, requirements: owned, work, })
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
  v.requirements.length()
}

///|
pub fn keyed_rows_at(v : KeyedRowBounds, i : Int) -> @capacity.TargetRows? {
  match v.requirements.get(i) {
    Some(CheckedEstimate(bound)) => Some(bound)
    _ => None
  }
}

///|
pub fn keyed_rows_requirement_at(
  v : KeyedRowBounds,
  i : Int,
) -> KeyedRowRequirement? {
  v.requirements.get(i)
}
