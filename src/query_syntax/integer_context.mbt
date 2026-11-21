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
  companions : Array[NamePart]
  ordinary : Array[Int]
  omitted : Array[Int]
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
fn integer_context_call_name(
  path : Array[NamePart],
  argument_count : Int,
) -> Bool {
  guard path.length() == 1 else { return false }
  let name = path[0].value
  if name.length() == 14 || (name.length() == 4 && argument_count == 3) {
    let expected = if name.length() == 14 { "GENERATE_ARRAY" } else { "DATE" }
    for index in 0..<expected.length() {
      let actual = name[index].to_int()
      let unit = if actual >= 97 && actual <= 122 {
        actual - 32
      } else {
        actual
      }
      if unit != expected[index].to_int() {
        return false
      }
    }
    return true
  }
  guard name.length() == 3 else { return false }
  let a = name[0].to_int()
  let b = name[1].to_int()
  let c = name[2].to_int()
  let a = if a >= 97 && a <= 122 { a - 32 } else { a }
  let b = if b >= 97 && b <= 122 { b - 32 } else { b }
  let c = if c >= 97 && c <= 122 { c - 32 } else { c }
  (a == 77 && b == 79 && c == 68) || (a == 68 && b == 73 && c == 86)
}

///|
fn integer_context_call(
  path : Array[NamePart],
  argument_count : Int,
  budget : IntegerContextBudget,
) -> Bool raise IntegerContextStop {
  if path.length() == 1 &&
    (
      path[0].value.length() == 14 ||
      (path[0].value.length() == 4 && argument_count == 3)
    ) {
    integer_context_spend(budget, amount=path[0].value.length())
    return integer_context_call_name(path, argument_count)
  }
  // Preserve the existing short-circuit character Work accounting. The same
  // fixed predicate supplies both the parser fact and the selected pass.
  ignore(
    path.length() == 1 &&
    (
      integer_context_name(path[0], { value: "MOD", quoted: false, }, budget) ||
      integer_context_name(path[0], { value: "DIV", quoted: false, }, budget)
    ),
  )
  integer_context_call_name(path, argument_count)
}

///|
/// Completed parser DATA only, never caller authority or a permission cache.
pub fn integer_function_context_required(query : Query) -> Bool {
  query.source.integer_context_required
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
  companion? : NamePart? = None,
) -> Unit raise IntegerContextStop {
  integer_context_spend(budget, amount=tasks[target].wanted.length() + 1)
  if !tasks[target].wanted.contains(column) {
    let name = match companion {
      Some(name) => name
      None => {
        let mut suffix = 0
        let mut name = {
          value: "aql_integer_\{target}_\{column}_0",
          quoted: false,
        }
        let mut collision = true
        while collision {
          integer_context_spend(budget)
          collision = false
          for task in tasks {
            if integer_context_column(task.original, name, budget) is Some(_) {
              collision = true
            }
          }
          if collision {
            suffix += 1
            name = {
              value: "aql_integer_\{target}_\{column}_\{suffix}",
              quoted: false,
            }
          }
        }
        name
      }
    }
    tasks[target].wanted.push(column)
    tasks[target].companions.push(name)
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
    UnnestSource(expression, _, _) => [expression]
    Extend(projections) | Select(projections, _) =>
      projections.filter_map(p => p.expression)
    Group(keys, projections, _) =>
      keys + projections.filter_map(p => p.expression)
    Order(terms) => terms.map(term => term.expression)
    _ => []
  }
}

///|
fn integer_context_companion(
  task : IntegerQueryContext,
  column : Int,
  budget : IntegerContextBudget,
) -> NamePart? raise IntegerContextStop {
  for i, wanted in task.wanted {
    integer_context_spend(budget)
    if wanted == column {
      return Some(task.companions[i])
    }
  }
  None
}

///|
/// Private compiler projection names, derived only from the syntax wrapper.
/// Author lookup and SELECT * retain the original public column view.
pub fn integer_context_companion_columns(query : Query) -> Array[String] {
  let names = []
  for operation in query.operations {
    if operation is Select(projections, _) {
      for p in projections {
        if p.expression is Some(e) &&
          e.nodes[e.root].kind is ContextualIntegerCompanion(_, _) &&
          p.name is Some(name) {
          names.push(name.value)
        }
      }
    }
  }
  names
}

///|
/// A physical exact companion identified by its original syntax wrapper.
/// Anonymous positional right operands have no authored public name.
pub fn integer_context_is_companion_column(
  query : Query,
  physical : String,
) -> Bool {
  for operation in query.operations {
    if operation is Select(projections, _) {
      for p in projections {
        if p.name is Some(name) &&
          name.value == physical &&
          p.expression is Some(e) &&
          e.nodes[e.root].kind is ContextualIntegerCompanion(_, _) {
          return true
        }
      }
    }
  }
  false
}

///|
/// Original public column of this exact parser-owned physical companion.
/// This is immutable syntax provenance, not a public identifier or a value.
/// In particular it survives omission of an unavailable ordinary Number view.
pub fn integer_context_original_column(
  query : Query,
  physical : String,
) -> String? {
  for operation in query.operations {
    if operation is Select(projections, _) {
      for p in projections {
        if p.name is Some(name) &&
          name.value == physical &&
          p.expression is Some(e) &&
          e.nodes[e.root].kind is ContextualIntegerCompanion(_, Some(original)) {
          return Some(original.value)
        }
      }
    }
  }
  None
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
  tasks : Array[IntegerQueryContext],
  task : IntegerQueryContext,
) -> Expression raise IntegerContextStop {
  let targets = if force { [expression.root] } else { [] }
  for node in expression.nodes {
    integer_context_spend(budget)
    if node.kind is Call(path, arguments) &&
      integer_context_call(path, arguments.length(), budget) {
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
    } else if integer_context_reference(expression, target, budget)
      is Some(path) &&
      integer_context_source(task, path, budget) is Some((producer, column)) &&
      integer_context_column(tasks[producer].original, column, budget)
      is Some(column) &&
      integer_context_companion(tasks[producer], column, budget)
      is Some(companion) {
      nodes[target] = {
        ..nodes[target],
        kind: ContextualIntegerReference(path.copy(), companion),
      }
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
  tasks : Array[IntegerQueryContext],
  task : IntegerQueryContext,
) -> QueryOperation raise IntegerContextStop {
  match operation {
    Select(projections, distinct) => {
      let selected = []
      for i, p in projections {
        integer_context_spend(budget, amount=task.omitted.length() + 1)
        if wanted.is_empty() || !task.omitted.contains(i) {
          selected.push({
            ..p,
            expression: p.expression.map(e => {
              integer_context_expression(e, false, budget, tasks, task)
            }),
          })
        }
      }
      // Positional UNION aligns the original producer projection coordinates,
      // never the order in which independent demands happened to reach it.
      // Iterating that original coordinate space also avoids a new sort/copy.
      for index in 0..<projections.length() {
        integer_context_spend(budget, amount=wanted.length() + 1)
        if !wanted.contains(index) {
          continue
        }
        guard projections.get(index) is Some(p) &&
          p.expression is Some(original) &&
          integer_context_companion(task, index, budget) is Some(name) else {
          continue
        }
        let expression = integer_context_expression(
          original, true, budget, tasks, task,
        )
        integer_context_spend(budget, amount=expression.nodes.length() + 1)
        let nodes = expression.nodes.copy()
        let root = nodes.length()
        nodes.push({
          ..expression.nodes[expression.root],
          kind: ContextualIntegerCompanion(
            expression.root,
            integer_context_projection_name(p),
          ),
        })
        selected.push({
          ..p,
          name: Some(name),
          expression: Some({ ..expression, nodes, root, }),
        })
        budget.rewrites += 1
      }
      Select(selected, distinct)
    }
    Extend(projections) =>
      Extend(
        projections.map(p => {
          ..p,
          expression: p.expression.map(e => {
            integer_context_expression(e, false, budget, tasks, task)
          }),
        }),
      )
    Where(expression) =>
      Where(integer_context_expression(expression, false, budget, tasks, task))
    UnnestSource(expression, element, offset) =>
      UnnestSource(
        integer_context_expression(expression, false, budget, tasks, task),
        element,
        offset,
      )
    Having(expression, calls) =>
      Having(
        integer_context_expression(expression, false, budget, tasks, task),
        calls,
      )
    Qualify(expression, calls) =>
      Qualify(
        integer_context_expression(expression, false, budget, tasks, task),
        calls,
      )
    Group(keys, projections, scope) =>
      Group(
        keys.map(e => integer_context_expression(e, false, budget, tasks, task)),
        projections.map(p => {
          ..p,
          expression: p.expression.map(e => {
            integer_context_expression(e, false, budget, tasks, task)
          }),
        }),
        scope,
      )
    Order(terms) =>
      Order(
        terms.map(term => {
          ..term,
          expression: integer_context_expression(
            term.expression,
            false,
            budget,
            tasks,
            task,
          ),
        }),
      )
    operation => operation
  }
}

///|
fn integer_context_mark(
  indices : Array[Int],
  index : Int,
  budget : IntegerContextBudget,
) -> Bool raise IntegerContextStop {
  integer_context_spend(budget, amount=indices.length() + 1)
  if indices.contains(index) {
    false
  } else {
    indices.push(index)
    true
  }
}

///|
fn integer_context_ordinary_expression(
  expression : Expression,
  task : IntegerQueryContext,
  tasks : Array[IntegerQueryContext],
  pending : Array[(Int, Int)],
  budget : IntegerContextBudget,
) -> Unit raise IntegerContextStop {
  integer_context_spend(budget, amount=expression.nodes.length())
  let exact = Array::make(expression.nodes.length(), false)
  for node in expression.nodes {
    integer_context_spend(budget)
    if node.kind is Call(path, arguments) &&
      integer_context_call(path, arguments.length(), budget) {
      for argument in arguments {
        let mut index = argument
        while expression.nodes[index].kind is Parenthesized(child) {
          integer_context_spend(budget)
          index = child
        }
        exact[index] = true
      }
    }
  }
  for index, node in expression.nodes {
    integer_context_spend(budget)
    if !exact[index] &&
      node.kind is Reference(path) &&
      integer_context_source(task, path, budget) is Some((producer, column)) &&
      integer_context_column(tasks[producer].original, column, budget)
      is Some(column) &&
      integer_context_mark(tasks[producer].ordinary, column, budget) {
      pending.push((producer, column))
    }
    // A whole original range receiver also demands every public column; it
    // cannot silently lose an unrepresentable Number view to an exact sibling.
    if !exact[index] &&
      node.kind is Reference([range]) &&
      task.original.relation is [relation] &&
      integer_context_name(
        range,
        task.original.source_alias.unwrap_or(relation),
        budget,
      ) {
      let mut visible = task.visible
      while visible is Some(scope) {
        integer_context_spend(budget)
        if integer_context_name(scope.name, relation, budget) {
          let columns = integer_context_projections(
            tasks[scope.target].original,
            budget,
          )
          for column in 0..<columns.length() {
            if integer_context_mark(
                tasks[scope.target].ordinary,
                column,
                budget,
              ) {
              pending.push((scope.target, column))
            }
          }
          break
        }
        visible = scope.parent
      }
    }
  }
}

///|
// Trace ordinary demands independently of exact-function demands. This is
// compiler DATA over original lexical scopes, never an observed Number cast.
fn integer_context_ordinary_flow(
  tasks : Array[IntegerQueryContext],
  budget : IntegerContextBudget,
) -> Unit raise IntegerContextStop {
  let pending : Array[(Int, Int)] = []
  for index, task in tasks {
    let mut last_select = -1
    for i, operation in task.original.operations {
      integer_context_spend(budget)
      if operation is Select(_, _) {
        last_select = i
      }
    }
    for i, operation in task.original.operations {
      integer_context_spend(budget)
      if i == last_select && index != 0 {
        continue
      }
      for expression in integer_context_expressions(operation, budget) {
        integer_context_ordinary_expression(
          expression, task, tasks, pending, budget,
        )
      }
      // A bare or qualified star consumes the original public columns only.
      if operation is Select(projections, _) &&
        projections.any(p => p.star is Some(_)) &&
        task.original.relation is [relation] {
        let mut visible = task.visible
        while visible is Some(scope) {
          integer_context_spend(budget)
          if integer_context_name(scope.name, relation, budget) {
            for
              column in 0..<integer_context_projections(
                tasks[scope.target].original,
                budget,
              ).length() {
              if integer_context_mark(
                  tasks[scope.target].ordinary,
                  column,
                  budget,
                ) {
                pending.push((scope.target, column))
              }
            }
            break
          }
          visible = scope.parent
        }
      }
    }
    for operation in task.original.final_operations {
      for expression in integer_context_expressions(operation, budget) {
        integer_context_ordinary_expression(
          expression, task, tasks, pending, budget,
        )
      }
    }
  }
  while pending.pop() is Some((index, column)) {
    integer_context_spend(budget)
    let task = tasks[index]
    let projections = integer_context_projections(task.original, budget)
    if projections.get(column) is Some({ expression: Some(expression), .. }) {
      integer_context_ordinary_expression(
        expression, task, tasks, pending, budget,
      )
    }
    for i, part in task.original.sets {
      let right = task.sets[i]
      let position = if part.by_name {
        if projections.get(column) is Some(p) &&
          integer_context_projection_name(p) is Some(name) {
          integer_context_column(tasks[right].original, name, budget)
        } else {
          None
        }
      } else {
        Some(column)
      }
      if position is Some(position) &&
        integer_context_mark(tasks[right].ordinary, position, budget) {
        pending.push((right, position))
      }
    }
  }
}

///|
fn integer_context_unsafe_number(
  expression : Expression,
  budget : IntegerContextBudget,
) -> Bool raise IntegerContextStop {
  guard integer_context_literal(expression, expression.root, budget)
    is Some(value) else {
    return false
  }
  // An untyped NULL alone has no independently checked ordinary Number view.
  // Its demanded exact companion retains the selected nullable int64 context.
  guard value is Some(value) else { return true }
  // The ordinary NUMBER view did not admit these original integer lexemes.
  // Do not construct a rounded surrogate merely to populate an unused view.
  value < -9007199254740991L || value > 9007199254740991L
}

///|
fn integer_context_omit_unrepresentable_unused(
  tasks : Array[IntegerQueryContext],
  budget : IntegerContextBudget,
) -> Unit raise IntegerContextStop {
  let mut changed = true
  while changed {
    changed = false
    for task in tasks {
      let projections = integer_context_projections(task.original, budget)
      for column in task.wanted {
        integer_context_spend(budget, amount=task.ordinary.length() + 1)
        if task.ordinary.contains(column) {
          continue
        }
        guard projections.get(column)
          is Some({ expression: Some(expression), .. }) else {
          continue
        }
        let upstream_omitted = if integer_context_reference(
            expression,
            expression.root,
            budget,
          )
          is Some(path) &&
          integer_context_source(task, path, budget) is Some((source, name)) &&
          integer_context_column(tasks[source].original, name, budget)
          is Some(source_column) {
          integer_context_spend(budget, amount=tasks[source].omitted.length())
          tasks[source].omitted.contains(source_column)
        } else {
          false
        }
        if (
            upstream_omitted ||
            integer_context_unsafe_number(expression, budget)
          ) &&
          integer_context_mark(task.omitted, column, budget) {
          changed = true
        }
      }
      // Every UNION member keeps the identical column alignment. An ordinary
      // demand propagated above preserves the original invalid-Number refusal.
      for i, part in task.original.sets {
        let right = tasks[task.sets[i]]
        for column in task.wanted {
          let position = if part.by_name {
            if projections.get(column) is Some(p) &&
              integer_context_projection_name(p) is Some(name) {
              integer_context_column(right.original, name, budget)
            } else {
              None
            }
          } else {
            Some(column)
          }
          guard position is Some(position) else { continue }
          integer_context_spend(
            budget,
            amount=task.omitted.length() +
              right.omitted.length() +
              task.ordinary.length() +
              right.ordinary.length(),
          )
          if !task.ordinary.contains(column) &&
            !right.ordinary.contains(position) &&
            (task.omitted.contains(column) || right.omitted.contains(position)) {
            if integer_context_mark(task.omitted, column, budget) {
              changed = true
            }
            if integer_context_mark(right.omitted, position, budget) {
              changed = true
            }
          }
        }
      }
    }
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
  if !integer_function_context_required(query) {
    return Ok(query)
  }
  let budget = { remaining: max_work, rewrites: 0, }
  try {
    let tasks : Array[IntegerQueryContext] = [
      {
        original: query,
        visible: None,
        bindings: [],
        sets: [],
        wanted: [],
        companions: [],
        ordinary: [],
        omitted: [],
      },
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
          companions: [],
          ordinary: [],
          omitted: [],
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
          companions: [],
          ordinary: [],
          omitted: [],
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
              integer_context_call(path, arguments.length(), budget) {
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
          integer_context_request(
            tasks,
            pending,
            right,
            position,
            budget,
            companion=integer_context_companion(task, column, budget),
          )
        }
      }
    }
    integer_context_ordinary_flow(tasks, budget)
    integer_context_omit_unrepresentable_unused(tasks, budget)
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
          tasks,
          task,
        )
      })
      let final_operations = task.original.final_operations.map(op => {
        integer_context_operation(op, [], budget, tasks, task)
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
