///|
// This frame belongs to one original expression and its immutable slot scope.
// It records SQL names, not value validation, current facts or permission.
priv struct ExpressionNamespace {
  root : NamespaceView?
  rows : Array[(Array[@query.NamePart], Array[(String, String)])]
  remaining : Int
}

///|
fn slot_namespace(
  columns : Array[ResultColumn]?,
  slot : String,
) -> NamespaceView? {
  guard columns is Some(columns) else { return None }
  for column in columns {
    if column.slot == slot && column.name_view is Some(view) {
      return Some(view)
    }
  }
  None
}

///|
// A type join cannot turn a display key into an SQL name. A branch with no
// private view has only ordinary named DATA; retain every anonymous restriction
// from the other branch. The existing value checker still owns shape/type joins.
fn merge_namespace_views(
  left : NamespaceView?,
  right : NamespaceView?,
  spend : (Int) -> Unit raise Abort,
) -> NamespaceView? raise Abort {
  spend(1)
  match (left, right) {
    (None, _) => right
    (_, None) => left
    (Some(a), Some(b)) => Some(Joined(a, b))
  }
}

///|
priv enum NamespaceAccess {
  Field(@query.NamePart)
  Item
}

///|
priv enum NamespaceUndo {
  Pop
  Push(NamespaceAccess)
}

///|
priv enum NamespaceVisit {
  Enter(NamespaceView)
  Restore(Int)
}

///|
// Walk shared original links with one mutable path and rollback log. Branches
// save indices, never a copied path or a retained validation result. The live
// path/log/DFS stack are bounded by the original namespace graph depth even
// when a repeated DAG path consumes more Work than its live representation.
fn namespace_validate_access(
  view : NamespaceView,
  access : NamespaceAccess,
  spend : (Int) -> Unit raise Abort,
  expression : @query.Expression,
  node : Int,
) -> Unit raise Abort {
  let path = [access]
  let undo : Array[NamespaceUndo] = []
  let pending : Array[NamespaceVisit] = [Enter(view)]
  while pending.pop() is Some(visit) {
    spend(1)
    match visit {
      Restore(mark) =>
        while undo.length() > mark {
          spend(1)
          match undo.pop().unwrap() {
            Pop => ignore(path.pop())
            Push(original) => path.push(original)
          }
        }
      Enter(view) => {
        spend(1)
        pending.push(Restore(undo.length()))
        match view {
          Joined(left, right) => {
            spend(2)
            pending.push(Enter(right))
            pending.push(Enter(left))
          }
          Member(receiver, name) => {
            spend(2)
            path.push(Field(name))
            undo.push(Pop)
            pending.push(Enter(receiver))
          }
          Element(receiver) => {
            spend(2)
            path.push(Item)
            undo.push(Pop)
            pending.push(Enter(receiver))
          }
          Array(item) =>
            if path.last() is Some(Item) {
              spend(2)
              ignore(path.pop())
              undo.push(Push(Item))
              if !path.is_empty() {
                pending.push(Enter(item))
              }
            }
          Row(fields) =>
            if path.last() is Some(Field(name)) {
              let mut found = false
              for field in fields {
                spend(1)
                if field.name is Some(original) {
                  spend(original.value.length())
                  spend(name.value.length())
                  if same_name(original, name) {
                    found = true
                    spend(2)
                    ignore(path.pop())
                    undo.push(Push(Field(name)))
                    if field.name_view is Some(child) && !path.is_empty() {
                      pending.push(Enter(child))
                    }
                    break
                  }
                }
              }
              if !found {
                raise Abort(
                  Expression({
                    issue: @expression.UnknownReference,
                    origin: @query.expression_origin(expression, node),
                  }),
                )
              }
            }
          Captured(fields, profiles) =>
            if path.last() is Some(Field(name)) {
              let mut found = false
              for field in fields {
                spend(1)
                spend(profiles.map(columns => columns.length()).unwrap_or(0))
                let original = result_column_profile(profiles, field.0, field.1)
                let public_name = match original {
                  Some(column) => column.name
                  None => Some({ value: field.0, quoted: false, })
                }
                if public_name is Some(public_name) {
                  spend(public_name.value.length())
                  spend(name.value.length())
                  if same_name(public_name, name) {
                    found = true
                    spend(2)
                    ignore(path.pop())
                    undo.push(Push(Field(name)))
                    if original.bind(column => column.name_view) is Some(child) &&
                      !path.is_empty() {
                      pending.push(Enter(child))
                    }
                    break
                  }
                }
              }
              if !found {
                raise Abort(
                  Expression({
                    issue: @expression.UnknownReference,
                    origin: @query.expression_origin(expression, node),
                  }),
                )
              }
            }
        }
      }
    }
  }
}

///|
fn namespace_member(
  view : NamespaceView?,
  name : @query.NamePart,
  spend : (Int) -> Unit raise Abort,
  expression : @query.Expression,
  node : Int,
) -> NamespaceView? raise Abort {
  guard view is Some(view) else { return None }
  namespace_validate_access(view, Field(name), spend, expression, node)
  Some(Member(view, name))
}

///|
fn namespace_array_item(
  view : NamespaceView?,
  spend : (Int) -> Unit raise Abort,
) -> NamespaceView? raise Abort {
  spend(1)
  view.map(view => Element(view))
}

///|
// Materialize only when the expression owner actually consumes this row. The
// returned work is charged by that same owner before its Object construction.
fn namespace_row_fields(
  fields : Array[(String, String)],
  columns : Array[ResultColumn]?,
  max_work : Int,
) -> Result[(Array[(String, String)], Int), @expression.Issue] {
  let mut remaining = max_work
  if fields.length() > remaining {
    return Err(@expression.WorkLimit)
  }
  remaining -= fields.length()
  let profiles : Array[ResultColumn] = []
  for field in fields {
    let scan = columns.map(columns => columns.length()).unwrap_or(0)
    if scan > remaining {
      return Err(@expression.WorkLimit)
    }
    remaining -= scan
    profiles.push(
      result_column_profile(columns, field.0, field.1).unwrap_or({
        slot: field.1,
        label: field.0,
        name: Some({ value: field.0, quoted: false, }),
        name_view: None,
      }),
    )
  }
  let (names, after_names) = match
    result_column_display_names_work(profiles, remaining) {
    Ok(result) => result
    Err(issue) => return Err(issue)
  }
  remaining = after_names
  if fields.length() > remaining {
    return Err(@expression.WorkLimit)
  }
  remaining -= fields.length()
  Ok(
    (
      fields.mapi((index, field) => (names[index], field.1)),
      max_work - remaining,
    ),
  )
}

///|
fn expression_namespace(
  expression : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  resolve_row : (Array[@query.NamePart]) -> Array[(String, String)]?,
  columns : Array[ResultColumn]?,
  max_work : Int,
) -> ExpressionNamespace raise Abort {
  if columns is None {
    return { root: None, rows: [], remaining: max_work, }
  }
  let mut remaining = max_work
  let mut current = @query.expression_root(expression)
  let spend = fn(amount : Int) -> Unit raise Abort {
    if amount < 0 || amount > remaining {
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @query.expression_origin(expression, current),
        }),
      )
    }
    remaining -= amount
  }
  let count = @query.expression_node_count(expression)
  spend(count)
  let views : Array[NamespaceView?] = []
  let rows : Array[(Array[@query.NamePart], Array[(String, String)])] = []
  for node in 0..<count {
    current = node
    spend(1)
    let view = match @query.expression_node(expression, node).unwrap().kind {
      Reference(path) => {
        let mut length = path.length()
        let mut selected = resolve(path)
        while selected is None && length > 1 {
          spend(length)
          length -= 1
          selected = resolve(path[:length].to_owned())
        }
        if selected is Some(slot) {
          spend(columns.unwrap().length())
          let mut view = slot_namespace(columns, slot)
          for part in path[length:] {
            view = namespace_member(view, part, spend, expression, current)
          }
          view
        } else if resolve_row(path) is Some(fields) {
          spend(fields.length())
          rows.push((path, fields))
          Some(Captured(fields, columns))
        } else {
          None
        }
      }
      Property(child, name) =>
        namespace_member(views[child], name, spend, expression, current)
      Parenthesized(child) => views[child]
      ArrayOffset(child, _, _) => namespace_array_item(views[child], spend)
      StructConstructor(fields) => {
        spend(fields.length())
        if fields.any(field => views[field.1] is Some(_)) {
          Some(
            Row(
              fields.map(field => {
                name: Some(field.0),
                name_view: views[field.1],
              }),
            ),
          )
        } else {
          None
        }
      }
      ArrayConstructor(items, _) => {
        let mut view : NamespaceView? = None
        for item in items {
          view = merge_namespace_views(view, views[item], spend)
        }
        view.map(view => Array(view))
      }
      SearchedCase(branches, otherwise) => {
        let mut view = views[otherwise]
        for branch in branches {
          view = merge_namespace_views(view, views[branch.1], spend)
        }
        view
      }
      Call(path, arguments) => {
        spend(path.length())
        if path.length() != 1 {
          None
        } else {
          spend(path[0].value.length())
          let name = ascii_upper(path[0].value)
          if name == "IF" && arguments.length() == 3 {
            merge_namespace_views(
              views[arguments[1]],
              views[arguments[2]],
              spend,
            )
          } else if name == "IFNULL" || name == "COALESCE" {
            let mut view : NamespaceView? = None
            for argument in arguments {
              view = merge_namespace_views(view, views[argument], spend)
            }
            view
          } else if name == "NULLIF" && arguments.length() == 2 {
            views[arguments[0]]
          } else {
            None
          }
        }
      }
      _ => None
    }
    views.push(view)
  }
  { root: views[@query.expression_root(expression)], rows, remaining, }
}
