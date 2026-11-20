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

///|
// Resolve only the original row/type-join links needed by this checked Object
// star. DATA keys select its values; optional names retain the SQL namespace.
// The first original row keeps its local field order across a type join.
fn namespace_object_columns(
  view : NamespaceView?,
  checked_names : Array[String],
  max_work : Int,
) -> (Array[ResultColumn]?, Int) raise Abort {
  guard view is Some(view) else { return (None, max_work) }
  let mut remaining = max_work
  let spend = fn(amount : Int) -> Unit raise Abort {
    if amount < 0 || amount > remaining {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
    }
    remaining -= amount
  }
  let path : Array[NamespaceAccess] = []
  let undo : Array[NamespaceUndo] = []
  let pending : Array[NamespaceVisit] = [Enter(view)]
  let mut selected : Array[ResultColumn]? = None
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
              pending.push(Enter(item))
            }
          Row(_) | Captured(_, _) => {
            let columns : Array[ResultColumn] = match view {
              Row(fields) => {
                spend(fields.length())
                fields.map(field => {
                  label: "",
                  slot: "",
                  name: field.name,
                  name_view: field.name_view,
                })
              }
              Captured(fields, profiles) => {
                spend(fields.length())
                fields.map(field => {
                  spend(profiles.map(columns => columns.length()).unwrap_or(0))
                  result_column_profile(profiles, field.0, field.1).unwrap_or({
                    label: field.0,
                    slot: field.1,
                    name: Some({ value: field.0, quoted: false, }),
                    name_view: None,
                  })
                })
              }
              _ => raise Abort(InvalidContext)
            }
            if path.last() is Some(Field(name)) {
              for column in columns {
                spend(1)
                if column.name is Some(original) {
                  spend(original.value.length())
                  spend(name.value.length())
                  if same_name(original, name) {
                    spend(2)
                    ignore(path.pop())
                    undo.push(Push(Field(name)))
                    if column.name_view is Some(child) {
                      pending.push(Enter(child))
                    }
                    break
                  }
                }
              }
            } else if path.is_empty() {
              let (names, after_names) = match
                result_column_display_names_work(columns, remaining) {
                Ok(result) => result
                Err(issue) => raise Abort(Expression({ issue, origin: None, }))
              }
              remaining = after_names
              spend(columns.length())
              let incoming = columns.mapi((index, column) => {
                ..column,
                label: names[index],
                slot: names[index],
              })
              match selected {
                None => selected = Some(incoming)
                Some(original) => {
                  if original.length() != incoming.length() {
                    raise Abort(InvalidContext)
                  }
                  for index, column in original {
                    spend(incoming.length())
                    let mut matched : ResultColumn? = None
                    for candidate in incoming {
                      if candidate.label == column.label {
                        matched = Some(candidate)
                        break
                      }
                    }
                    guard matched is Some(matched) else {
                      raise Abort(InvalidContext)
                    }
                    original[index] = {
                      ..column,
                      name: if matched.name is None {
                        None
                      } else {
                        column.name
                      },
                      name_view: merge_namespace_views(
                        column.name_view,
                        matched.name_view,
                        spend,
                      ),
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  if selected is Some(columns) {
    if columns.length() != checked_names.length() {
      raise Abort(InvalidContext)
    }
    for column in columns {
      spend(checked_names.length())
      if !checked_names.contains(column.label) {
        raise Abort(InvalidContext)
      }
    }
  }
  (selected, remaining)
}

///|
fn scope_namespace_before_reuse(
  expression : @query.Expression,
  scope : JoinChainScope,
  max_work : Int,
  resolve? : ((Array[@query.NamePart]) -> String?)? = None,
) -> NamespaceView? raise Abort {
  guard scope.result_columns is Some(_) else { return None }
  let value_ranges = value_range_names(scope.receivers, scope.scalar_ranges)
  let resolve = resolve.unwrap_or(path => {
    if path.length() == 1 &&
      ordinary_range_name(path[0], scope.ranges, value_ranges) {
      return None
    }
    profiled_pipe_slot(path, scope.visible, scope.ranges, scope.result_columns)
  })
  let row_ranges = scope.ranges.filter(range => {
    !value_ranges.any(name => same_name(name, range.0))
  })
  let (lowered, slots, remaining) = bind_range_property_expression(
    expression,
    resolve,
    name => resolve([name]) is Some(_),
    max_work,
  )
  let bound_resolve = fn(path : Array[@query.NamePart]) -> String? {
    if path.length() == 1 {
      for (name, slot) in slots {
        if path[0].value == name {
          return Some(slot)
        }
      }
    }
    resolve(path)
  }
  expression_namespace(
    lowered,
    bound_resolve,
    path => {
      row_reference_fields(path, name => resolve([name]) is Some(_), row_ranges)
    },
    scope.result_columns,
    remaining,
  ).root
}
