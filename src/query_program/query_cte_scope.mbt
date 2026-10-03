///|
// Share CTE validation between standalone queries and logical DATA composition.
// Producer scheduling is separate: this function neither builds a Stage nor
// acquires a source, and unused declarations retain their existing refusal.
fn validate_cte_scope(
  query : @query.Query,
  inputs : Array[Input],
) -> Unit raise Abort {
  let used = Array::make(@query.cte_count(query), false)
  let joined_relation = if @query.join_part_count(query) == 1 {
    Some(@query.join_part_at(query, 0).unwrap().relation)
  } else {
    None
  }
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
    if @query.cte_count(body) != 0 || @query.join_part_count(body) > 1 {
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
      if @query.join_part_count(term) == 1 {
        let right = @query.join_part_at(term, 0).unwrap().relation
        let mut known_right = false
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
    let joined = match joined_relation {
      Some(path) => same_relation_path(path, [cte.name])
      None => false
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
        let right = if @query.join_part_count(term) == 1 {
          Some(@query.join_part_at(term, 0).unwrap().relation)
        } else {
          None
        }
        for earlier in 0..<index {
          let name = [@query.cte_at(query, earlier).unwrap().name]
          if same_relation_path(relation, name) ||
            (
              right is Some(right_relation) &&
              same_relation_path(right_relation, name)
            ) {
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
