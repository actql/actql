///|
// Share CTE validation between standalone queries and logical DATA composition.
// Producer scheduling is separate: this function neither builds a Stage nor
// acquires a source, and unused declarations retain their existing refusal.
fn validate_cte_scope(
  query : @query.Query,
  inputs : Array[Input],
) -> Unit raise Abort {
  let used = Array::make(@query.cte_count(query), false)
  for index in 0..<@query.cte_count(query) {
    let cte = @query.cte_at(query, index).unwrap()
    for earlier in 0..<index {
      if same_relation_name(
          cte.name,
          @query.cte_at(query, earlier).unwrap().name,
        ) {
        raise Abort(UnsupportedCte)
      }
    }
    let body = cte.query
    // RESULT is a statement-level publication obligation. A CTE or a
    // derived-table body cannot add externally visible exports.
    for operation_index in 0..<@query.operation_count(body) {
      if @query.operation_at(body, operation_index) is Some(RetainResult(_)) {
        raise Abort(UnsupportedResult)
      }
    }
    if @query.cte_count(body) != 0 {
      raise Abort(UnsupportedCte)
    }
    for term in query_terms(body) {
      let body_relation = @query.relation(term)
      let known_outer = body_relation.is_empty() ||
        inputs.any(input => input_relation_matches(body_relation, input))
      for future in index..<@query.cte_count(query) {
        if same_relation_path(body_relation, [
            @query.cte_at(query, future).unwrap().name,
          ]) &&
          !known_outer {
          raise Abort(UnsupportedCte)
        }
      }
      // A nonrecursive body can still name an outer producer before its own
      // CTE alias is bound. The parser has already selected the lexical scope.
      let mut known_relation = known_outer
      for earlier in 0..<index {
        if same_relation_path(body_relation, [
            @query.cte_at(query, earlier).unwrap().name,
          ]) {
          known_relation = true
        }
      }
      if !known_relation {
        raise Abort(UnknownRelation)
      }
      for join_index in 0..<@query.join_part_count(term) {
        let right = @query.join_part_at(term, join_index).unwrap().relation
        let mut known_right = inputs.any(input => {
          input_relation_matches(right, input)
        })
        for earlier in 0..<index {
          if same_relation_path(right, [
              @query.cte_at(query, earlier).unwrap().name,
            ]) {
            known_right = true
          }
        }
        if !known_right {
          raise Abort(UnsupportedCte)
        }
      }
    }
    let mut joined = false
    for term in query_terms(query) {
      for join_index in 0..<@query.join_part_count(term) {
        if same_relation_path(
            @query.join_part_at(term, join_index).unwrap().relation,
            [cte.name],
          ) {
          joined = true
        }
      }
    }
    if query_terms(query).any(term => {
        same_relation_path(@query.relation(term), [cte.name])
      }) ||
      joined {
      used[index] = true
    }
  }
  if !used.any(value => value) {
    raise Abort(UnsupportedCte)
  }
  let mut index = @query.cte_count(query) - 1
  while index >= 0 {
    if used[index] {
      for term in query_terms(@query.cte_at(query, index).unwrap().query) {
        let relation = @query.relation(term)
        for earlier in 0..<index {
          let name = [@query.cte_at(query, earlier).unwrap().name]
          let mut joined = false
          for join_index in 0..<@query.join_part_count(term) {
            if same_relation_path(
                @query.join_part_at(term, join_index).unwrap().relation,
                name,
              ) {
              joined = true
            }
          }
          if same_relation_path(relation, name) || joined {
            used[earlier] = true
          }
        }
      }
    }
    index -= 1
  }
  // An unused declaration still needs full semantic checking. Until the
  // frontend can check it without scheduling its acquisition, reject it.
  if used.any(value => !value) {
    raise Abort(UnsupportedCte)
  }
}
