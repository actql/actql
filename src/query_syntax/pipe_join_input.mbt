///|
// The ordinary projected-producer path retains one range over the current row.
// Original snapshots displaced by SET/DROP/RENAME/EXTEND need the separate
// private continuation scope. Projection removes snapshots; AS binds anew.
fn pipe_join_input_alias(query : Query) -> NamePart?? {
  if query.graph is Some(_) {
    return None
  }
  let mut safe = query.joins.is_empty()
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
      Select(_, _) | Group(_, _, _) => {
        safe = true
        current_range = None
      }
      Alias(name) => {
        safe = true
        current_range = Some(name)
      }
      Set(_) | Drop(_) | Rename(_) | Extend(_) | Analytic(_) =>
        if current_range is Some(_) {
          safe = false
        }
      Where(_)
      | Having(_, _)
      | Qualify(_)
      | Order(_)
      | Limit(_, _)
      | AssertUnique(_) => ()
      // These operations have their own placement/carrier contracts. Do not
      // move them into a synthetic CTE as a side effect of JOIN composition.
      Infer(_)
      | Nearest(_)
      | RetainResult(_)
      | GraphCall(_)
      | UnnestSource(_, _, _) => return None
    }
  }
  if safe {
    Some(current_range)
  } else {
    None
  }
}

///|
// Only ordinary Relation operations may carry an immutable row scope into
// another JOIN. Model, Graph and Result boundaries keep their own admission.
fn pipe_join_range_input(query : Query) -> Bool {
  query.graph is None &&
  query.operations.all(operation => {
    match operation {
      Infer(_)
      | Nearest(_)
      | RetainResult(_)
      | GraphCall(_)
      | UnnestSource(_, _, _) => false
      _ => true
    }
  })
}
