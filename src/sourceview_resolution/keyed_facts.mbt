///|
pub(all) enum KeyedFactsIssue {
  InvalidLimits
  ForeignFacts
  WorkLimit
  MissingFacts(Int)
  MissingCapacity(Int)
  IncompleteResponse(Int)
} derive(Eq, Debug)

///|
struct KeyedSourceFacts {
  join : KeyedJoin
  source : @environment.SourceLookupFacts
  capacity : @environment.LookupCapacity
}

///|
struct CheckedKeyedFacts {
  joins : CheckedKeyedJoins
  facts : @environment.LookupCapacities
  entries : Array[KeyedSourceFacts]
  work : Int
}

///|
/// Binds complete source declarations to actual keyed joins. Left bounds, Host
/// transport budgets, Catalog authority and response validation remain separate.
pub fn check_keyed_facts(
  joins : CheckedKeyedJoins,
  facts : @environment.LookupCapacities,
  max_work : Int,
) -> Result[CheckedKeyedFacts, KeyedFactsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      @environment.lookup_capacity_references(facts),
      pipeline_catalog_references(joins.requests.uses.attachment.inputs),
    ) {
    return Err(ForeignFacts)
  }
  let mut work = 0
  let entries = []
  for join in joins.joins {
    if work >= max_work {
      return Err(WorkLimit)
    }
    work += 1
    let input = keyed_request_input(join.request.request)
    let item = @environment.source_request_member(input.selected.contract)
    let source = match @environment.source_lookup_facts(facts, item) {
      Some(v) => v
      None => return Err(MissingFacts(join.step_index))
    }
    let capacity = match
      @environment.lookup_facts_capacity(
        @environment.source_lookup_body(source),
      ) {
      Some(v) => v
      None => return Err(MissingCapacity(join.step_index))
    }
    if @environment.lookup_capacity_completeness(capacity) !=
      @environment.CompletePerRequestedKey {
      return Err(IncompleteResponse(join.step_index))
    }
    entries.push({ join, source, capacity, })
  }
  Ok({ joins, facts, entries, work, })
}

///|
pub fn keyed_facts_joins(v : CheckedKeyedFacts) -> CheckedKeyedJoins {
  v.joins
}

///|
pub fn keyed_facts_owner(
  v : CheckedKeyedFacts,
) -> @environment.LookupCapacities {
  v.facts
}

///|
pub fn keyed_facts_work(v : CheckedKeyedFacts) -> Int {
  v.work
}

///|
pub fn keyed_facts_count(v : CheckedKeyedFacts) -> Int {
  v.entries.length()
}

///|
pub fn keyed_facts_at(v : CheckedKeyedFacts, i : Int) -> KeyedSourceFacts? {
  v.entries.get(i)
}

///|
pub fn keyed_source_join(v : KeyedSourceFacts) -> KeyedJoin {
  v.join
}

///|
pub fn keyed_source_facts(
  v : KeyedSourceFacts,
) -> @environment.SourceLookupFacts {
  v.source
}

///|
pub fn keyed_source_capacity(
  v : KeyedSourceFacts,
) -> @environment.LookupCapacity {
  v.capacity
}
