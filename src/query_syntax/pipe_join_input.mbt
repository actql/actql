///|
// The ordinary projected-producer path retains one range over the current row.
// Original snapshots displaced by SET/DROP/RENAME/EXTEND need the separate
// private continuation scope. Projection removes snapshots; AS binds anew.
fn pipe_join_input_alias(query : Query) -> NamePart?? {
  if query.graph is Some(_) {
    return None
  }
  let mut safe = query.joins.is_empty()
  let mut relation = true
  let mut current_range : NamePart? = if safe {
    match query.source_alias {
      Some(name) => Some(name)
      None => query.relation.last()
    }
  } else {
    None
  }
  for operation in query.operations {
    match operation {
      Select(_, _) | Group(_, _, _) | Pivot(_) | Unpivot(_) => {
        safe = true
        current_range = None
      }
      Alias(name) => {
        safe = true
        current_range = Some(name)
      }
      Set(_)
      | Drop(_)
      | Rename(_)
      | Extend(_)
      | Analytic(_)
      | AnalyticExpressions(_, _)
      | OrderAnalytic(_, _) => if current_range is Some(_) { safe = false }
      Where(_)
      | Having(_, _)
      | Qualify(_)
      | Order(_)
      | Limit(_, _)
      | AssertUnique(_)
      | Distinct => ()
      // These operations have their own placement/carrier contracts. Do not
      // move them into a synthetic CTE as a side effect of JOIN composition.
      GraphCall(call) => {
        // A row Bridge ends the Graph prefix and starts a fresh Relation scope.
        // Earlier Graph-returning calls cannot themselves be JOIN inputs.
        relation = has_sga_relation_lowering(call.operation)
        safe = relation
        current_range = None
      }
      Infer(_) | Nearest(_) | RetainResult(_) => return None
      UnnestSource(_, _, _) => safe = false
    }
  }
  if safe && relation {
    Some(current_range)
  } else {
    None
  }
}

///|
// A projected/set output has closed its input ranges. Transparent unnamed
// parentheses preserve the remaining row scopes through the existing binding.
fn query_output_carries_ranges(query : Query) -> Bool {
  query.primary is None &&
  query.graph is None &&
  query.sets.is_empty() &&
  !(pipe_join_input_alias(query) is Some(None))
}

///|
// Only ordinary Relation operations may carry an immutable row scope into
// another JOIN. Model, Graph and Result boundaries keep their own admission.
fn pipe_join_range_input(query : Query) -> Bool {
  query.graph is None &&
  query.operations.all(operation => {
    match operation {
      Infer(_) | Nearest(_) | RetainResult(_) | GraphCall(_) => false
      _ => true
    }
  })
}
