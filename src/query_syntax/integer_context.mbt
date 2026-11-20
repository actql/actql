///|
priv struct IntegerContextBudget {
  mut remaining : Int
  mut rewrites : Int
}

///|
priv suberror IntegerContextStop {
  IntegerContextStop
}

///|
priv struct IntegerQueryContext {
  original : Query
  mut visible : IntegerContextScope?
  bindings : Array[Int]
  sets : Array[Int]
  wanted : Array[Int]
}

///|
// Query-local immutable scope links share the original declaration names.
// A copied visible-name vector per CTE would require quadratic live storage.
priv struct IntegerContextScope {
  name : NamePart
  target : Int
  parent : IntegerContextScope?
}

///|
fn integer_context_spend(
  budget : IntegerContextBudget,
  amount? : Int = 1,
) -> Unit raise IntegerContextStop {
  if amount < 0 || amount > budget.remaining {
    raise IntegerContextStop
  }
  budget.remaining -= amount
}

///|
// Same ASCII-insensitive query-local name rule, without allocating folded
// copies before their work has been admitted.
fn integer_context_name(
  left : NamePart,
  right : NamePart,
  budget : IntegerContextBudget,
) -> Bool raise IntegerContextStop {
  if left.value.length() != right.value.length() {
    return false
  }
  for index in 0..<left.value.length() {
    integer_context_spend(budget)
    let a = left.value[index].to_int()
    let b = right.value[index].to_int()
    let a = if a >= 97 && a <= 122 { a - 32 } else { a }
    let b = if b >= 97 && b <= 122 { b - 32 } else { b }
    if a != b {
      return false
    }
  }
  true
}

///|
fn integer_context_call(
  path : Array[NamePart],
  budget : IntegerContextBudget,
) -> Bool raise IntegerContextStop {
  path.length() == 1 &&
  (
    integer_context_name(path[0], { value: "MOD", quoted: false, }, budget) ||
    integer_context_name(path[0], { value: "DIV", quoted: false, }, budget)
  )
}

///|
fn integer_context_projections(
  query : Query,
  budget : IntegerContextBudget,
) -> Array[Projection] raise IntegerContextStop {
  let mut selected = []
  for operation in query.operations {
    integer_context_spend(budget)
    if operation is Select(projections, _) {
      selected = projections
    }
  }
  selected
}

///|
fn integer_context_projection_name(projection : Projection) -> NamePart? {
  if projection.name is Some(name) {
    return Some(name)
  }
  guard projection.expression is Some(expression) else { return None }
  match expression.nodes[expression.root].kind {
    Reference(path) => path.last()
    Property(_, name) => Some(name)
    _ => None
  }
}

///|
fn integer_context_column(
  query : Query,
  name : NamePart,
  budget : IntegerContextBudget,
) -> Int? raise IntegerContextStop {
  let mut found = None
  for index, projection in integer_context_projections(query, budget) {
    integer_context_spend(budget)
    if integer_context_projection_name(projection) is Some(candidate) &&
      integer_context_name(candidate, name, budget) {
      if found is Some(_) {
        return None
      }
      found = Some(index)
    }
  }
  found
}

///|
fn integer_context_source(
  task : IntegerQueryContext,
  path : Array[NamePart],
  budget : IntegerContextBudget,
) -> (Int, NamePart)? raise IntegerContextStop {
  let query = task.original
  guard query.relation is [relation] && query.joins.is_empty() else {
    return None
  }
  let column = match path {
    [column] => column
    [range, column] if integer_context_name(
        range,
        query.source_alias.unwrap_or(relation),
        budget,
      ) => column
    _ => return None
  }
  let mut visible = task.visible
  while visible is Some(scope) {
    integer_context_spend(budget)
    if integer_context_name(scope.name, relation, budget) {
      return Some((scope.target, column))
    }
    visible = scope.parent
  }
  None
}

///|
fn integer_context_request(
  tasks : Array[IntegerQueryContext],
  pending : Array[(Int, Int)],
  target : Int,
  column : Int,
  budget : IntegerContextBudget,
) -> Unit raise IntegerContextStop {
  integer_context_spend(budget, amount=tasks[target].wanted.length() + 1)
  if !tasks[target].wanted.contains(column) {
    tasks[target].wanted.push(column)
    pending.push((target, column))
  }
}

///|
fn integer_context_expressions(
  operation : QueryOperation,
  budget : IntegerContextBudget,
) -> Array[Expression] raise IntegerContextStop {
  let entries = match operation {
    Extend(projections) | Select(projections, _) => projections.length()
    Group(keys, projections, _) => {
      integer_context_spend(budget, amount=keys.length())
      projections.length()
    }
    Order(terms) => terms.length()
    _ => 1
  }
  integer_context_spend(budget, amount=entries)
  match operation {
    Where(expression) | Having(expression, _) | Qualify(expression, _) =>
      [expression]
    Extend(projections) | Select(projections, _) =>
      projections.filter_map(p => p.expression)
    Group(keys, projections, _) =>
      keys + projections.filter_map(p => p.expression)
    Order(terms) => terms.map(term => term.expression)
    _ => []
  }
}

///|
fn integer_context_reference(
  expression : Expression,
  index : Int,
  budget : IntegerContextBudget,
) -> Array[NamePart]? raise IntegerContextStop {
  let mut index = index
  while expression.nodes[index].kind is Parenthesized(child) {
    integer_context_spend(budget)
    index = child
  }
  match expression.nodes[index].kind {
    Reference(path) => Some(path)
    _ => None
  }
}

///|
fn integer_context_literal(
  expression : Expression,
  index : Int,
  budget : IntegerContextBudget,
) -> Int64?? raise IntegerContextStop {
  let mut index = index
  while expression.nodes[index].kind is Parenthesized(child) {
    integer_context_spend(budget)
    index = child
  }
  if expression.nodes[index].kind is Null {
    return Some(None)
  }
  if expression.nodes[index].kind is ContextualInteger(value) {
    return Some(value)
  }
  let mut negative = false
  if expression.nodes[index].kind is Unary("-" | "+" as sign, child) {
    negative = sign == "-"
    index = child
    while expression.nodes[index].kind is Parenthesized(child) {
      integer_context_spend(budget)
      index = child
    }
  }
  guard expression.nodes[index].kind is Number(text) else { return None }
  integer_context_spend(budget, amount=text.length())
  contextual_integer_literal(text, negative).map(value => Some(value))
}

///|
fn integer_context_expression(
  expression : Expression,
  force : Bool,
  budget : IntegerContextBudget,
) -> Expression raise IntegerContextStop {
  let targets = if force { [expression.root] } else { [] }
  for node in expression.nodes {
    integer_context_spend(budget)
    if node.kind is Call(path, arguments) && integer_context_call(path, budget) {
      targets.append(arguments)
    }
  }
  if targets.is_empty() {
    return expression
  }
  // Admit the copy before allocating it; untouched expressions keep their
  // original node vector. No caller-authored array is mutated.
  integer_context_spend(budget, amount=expression.nodes.length())
  let nodes = expression.nodes.copy()
  let mut changed = false
  for target in targets {
    integer_context_spend(budget)
    if integer_context_literal(expression, target, budget) is Some(value) &&
      !(nodes[target].kind is ContextualInteger(_)) {
      nodes[target] = { ..nodes[target], kind: ContextualInteger(value), }
      changed = true
    }
  }
  if !changed {
    return expression
  }
  budget.rewrites += 1
  // The existing bounded source-subtree constructor removes the consumed
  // unsigned child of a signed literal without ever admitting it as Double.
  for _ in 0..<3 {
    integer_context_spend(budget, amount=nodes.length())
  }
  expression_subtree({ ..expression, nodes, }, expression.root, []).unwrap()
}

///|
fn integer_context_operation(
  operation : QueryOperation,
  wanted : Array[Int],
  budget : IntegerContextBudget,
) -> QueryOperation raise IntegerContextStop {
  match operation {
    Select(projections, distinct) =>
      Select(
        projections.mapi((index, p) => {
          integer_context_spend(budget, amount=wanted.length() + 1)
          {
            ..p,
            expression: p.expression.map(e => {
              integer_context_expression(e, wanted.contains(index), budget)
            }),
          }
        }),
        distinct,
      )
    Extend(projections) =>
      Extend(
        projections.map(p => {
          ..p,
          expression: p.expression.map(e => {
            integer_context_expression(e, false, budget)
          }),
        }),
      )
    Where(expression) =>
      Where(integer_context_expression(expression, false, budget))
    Having(expression, calls) =>
      Having(integer_context_expression(expression, false, budget), calls)
    Qualify(expression, calls) =>
      Qualify(integer_context_expression(expression, false, budget), calls)
    Group(keys, projections, scope) =>
      Group(
        keys.map(e => integer_context_expression(e, false, budget)),
        projections.map(p => {
          ..p,
          expression: p.expression.map(e => {
            integer_context_expression(e, false, budget)
          }),
        }),
        scope,
      )
    Order(terms) =>
      Order(
        terms.map(term => {
          ..term,
          expression: integer_context_expression(term.expression, false, budget),
        }),
      )
    operation => operation
  }
}

///|
/// Select exact integer literal context from original function/producer syntax.
/// No row is read and no declared Number, parameter or external Source is
/// reclassified. All ordinary checking, current and authority gates follow.
pub fn with_integer_function_context(
  query : Query,
  max_work : Int,
) -> Result[Query, Diagnostic] {
  if max_work < 0 {
    return Err({ issue: InvalidLimits, span: None, })
  }
  let budget = { remaining: max_work, rewrites: 0, }
  try {
    let tasks : Array[IntegerQueryContext] = [
      { original: query, visible: None, bindings: [], sets: [], wanted: [], },
    ]
    let mut cursor = 0
    while cursor < tasks.length() {
      integer_context_spend(budget)
      let task = tasks[cursor]
      let mut visible = task.visible
      for binding in task.original.bindings {
        integer_context_spend(budget)
        let index = tasks.length()
        tasks.push({
          original: binding.query,
          visible,
          bindings: [],
          sets: [],
          wanted: [],
        })
        task.bindings.push(index)
        visible = Some({ name: binding.name, target: index, parent: visible, })
      }
      task.visible = visible
      for part in task.original.sets {
        integer_context_spend(budget)
        task.sets.push(tasks.length())
        tasks.push({
          original: part.right,
          visible,
          bindings: [],
          sets: [],
          wanted: [],
        })
      }
      cursor += 1
    }
    let pending : Array[(Int, Int)] = []
    let mut required = false
    for task in tasks {
      for operation in task.original.operations + task.original.final_operations {
        for expression in integer_context_expressions(operation, budget) {
          for node in expression.nodes {
            integer_context_spend(budget)
            if node.kind is Call(path, arguments) &&
              integer_context_call(path, budget) {
              required = true
              for argument in arguments {
                if integer_context_reference(expression, argument, budget)
                  is Some(path) &&
                  integer_context_source(task, path, budget)
                  is Some((producer, column)) &&
                  integer_context_column(
                    tasks[producer].original,
                    column,
                    budget,
                  )
                  is Some(index) {
                  integer_context_request(
                    tasks, pending, producer, index, budget,
                  )
                }
              }
            }
          }
        }
      }
    }
    if !required {
      return Ok(query)
    }
    while pending.pop() is Some((target, column)) {
      integer_context_spend(budget)
      let task = tasks[target]
      let projections = integer_context_projections(task.original, budget)
      if projections.get(column) is Some({ expression: Some(expression), .. }) &&
        integer_context_reference(expression, expression.root, budget)
        is Some(path) &&
        integer_context_source(task, path, budget) is Some((producer, field)) &&
        integer_context_column(tasks[producer].original, field, budget)
        is Some(index) {
        integer_context_request(tasks, pending, producer, index, budget)
      }
      for index, part in task.original.sets {
        let right = task.sets[index]
        let position = if part.by_name {
          if projections.get(column) is Some(projection) &&
            integer_context_projection_name(projection) is Some(name) {
            integer_context_column(tasks[right].original, name, budget)
          } else {
            None
          }
        } else {
          Some(column)
        }
        if position is Some(position) {
          integer_context_request(tasks, pending, right, position, budget)
        }
      }
    }
    integer_context_spend(budget, amount=tasks.length())
    let completed : Array[Query?] = Array::make(tasks.length(), None)
    for index = tasks.length() - 1; index >= 0; index = index - 1 {
      let task = tasks[index]
      integer_context_spend(budget)
      let before = budget.rewrites
      let mut last_select = -1
      for i, operation in task.original.operations {
        integer_context_spend(budget)
        if operation is Select(_, _) {
          last_select = i
        }
      }
      let operations = task.original.operations.mapi((i, op) => {
        integer_context_operation(
          op,
          if i == last_select {
            task.wanted
          } else {
            []
          },
          budget,
        )
      })
      let final_operations = task.original.final_operations.map(op => {
        integer_context_operation(op, [], budget)
      })
      let mut child_changed = false
      let bindings = task.original.bindings.mapi((i, b) => {
        let query = completed[task.bindings[i]].unwrap()
        if !physical_equal(query, b.query) {
          child_changed = true
        }
        { ..b, query, }
      })
      let sets = task.original.sets.mapi((i, s) => {
        let right = completed[task.sets[i]].unwrap()
        if !physical_equal(right, s.right) {
          child_changed = true
        }
        { ..s, right, }
      })
      // Reentering the compiler on the same already-contextualized subtree
      // must not retain another copy of its entire producer tree.
      completed[index] = Some(
        if before == budget.rewrites && !child_changed {
          task.original
        } else {
          {
            ..task.original,
            bindings,
            sets,
            operations: if before == budget.rewrites {
              task.original.operations
            } else {
              operations
            },
            final_operations: if before == budget.rewrites {
              task.original.final_operations
            } else {
              final_operations
            },
          }
        },
      )
    }
    Ok(completed[0].unwrap())
  } catch {
    IntegerContextStop => Err({ issue: Limit(Work), span: None, })
  }
}
