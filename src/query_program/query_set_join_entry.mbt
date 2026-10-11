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
    Array::makei(@query.query_binding_count(query), index => {
      @query.set_part_count(@query.query_binding_at(query, index).unwrap().query) > 0
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
  for index in 0..<@query.query_binding_count(query) {
    if query_has_join_set_operand(@query.query_binding_at(query, index).unwrap().query) {
      return true
    }
  }
  false
}

///|
// The stage-per-CTE path requires both JOIN ports to be CTE Results. A
// mixed CTE/ordinary-input JOIN needs the existing producer binding path,
// independent of operand order. Detect references, not generated-name text.
fn query_has_mixed_cte_join_input(query : @query.Query) -> Bool {
  let is_cte = fn(relation : Array[@query.NamePart]) -> Bool {
    Array::makei(@query.query_binding_count(query), index => {
      same_relation_path(relation, [@query.query_binding_at(query, index).unwrap().name])
    }).any(value => value)
  }
  if @query.join_part_count(query) > 0 {
    let left_is_cte = is_cte(@query.relation(query))
    for index in 0..<@query.join_part_count(query) {
      if is_cte(@query.join_part_at(query, index).unwrap().relation) !=
        left_is_cte {
        return true
      }
    }
  }
  for index in 0..<@query.query_binding_count(query) {
    if query_has_mixed_cte_join_input(
        @query.query_binding_at(query, index).unwrap().query,
      ) {
      return true
    }
  }
  for index in 0..<@query.set_part_count(query) {
    if query_has_mixed_cte_join_input(
        @query.set_part_at(query, index).unwrap().right,
      ) {
      return true
    }
  }
  false
}
