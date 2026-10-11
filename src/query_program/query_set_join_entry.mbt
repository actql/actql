///|
// JOIN operands need the existing script composition path: it binds inputs
// once and lowers every branch before the ordinary set owner combines them.
// Parsing already bounds this finite query tree. No names or predicates are
// resolved here; CTE/JOIN scopes and all limits stay with their current owners.
fn query_has_join_set_operand(query : @query.Query) -> Bool {
  // Derived tables are parser-owned CTE producers. A JOIN consuming a set
  // producer needs the same shared binding as a set consuming a JOIN; the
  // stage-per-term CTE route otherwise adds unnecessary Result boundaries.
  if @query.join_part_count(query) > 0 &&
    Array::makei(@query.cte_count(query), index => {
      @query.set_part_count(@query.cte_at(query, index).unwrap().query) > 0
    }).any(value => value) {
    return true
  }
  if @query.set_part_count(query) > 0 &&
    query_terms(query).any(term => @query.join_part_count(term) > 0) {
    return true
  }
  for index in 0..<@query.set_part_count(query) {
    if query_has_join_set_operand(
        @query.set_part_at(query, index).unwrap().right,
      ) {
      return true
    }
  }
  for index in 0..<@query.cte_count(query) {
    if query_has_join_set_operand(@query.cte_at(query, index).unwrap().query) {
      return true
    }
  }
  false
}
