///|
// This frame belongs to one original expression and its immutable slot scope.
// It records SQL names, not value validation, current facts or permission.
priv struct ExpressionNamespace {
  root : NamespaceView?
  rows : Array[(Array[@query.NamePart], Array[(String, String)])]
  remaining : Int
}

///|
fn slot_namespace(columns : Array[ResultColumn]?, slot : String) -> NamespaceView? {
  guard columns is Some(columns) else { return None }
  for column in columns {
    if column.slot == slot && column.name_view is Some(view) { return Some(view) }
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
    (Some(Array(a)), Some(Array(b))) =>
      merge_namespace_views(Some(a), Some(b), spend).map(view => Array(view))
    (Some(Row(a)), Some(Row(b))) => {
      let fields : Array[NamespaceField] = []
      for field in a {
        spend(1)
        let mut other : NamespaceField? = None
        for candidate in b {
          spend(1)
          if candidate.key == field.key { other = Some(candidate); break }
        }
        fields.push(match other {
          None => field
          Some(other) => {
            ..field,
            name: if field.name == other.name { field.name } else { None },
            name_view: merge_namespace_views(field.name_view, other.name_view, spend),
          }
        })
      }
      for field in b {
        spend(1)
        let mut found = false
        for original in a {
          spend(1)
          if original.key == field.key { found = true; break }
        }
        if !found { fields.push(field) }
      }
      Some(Row(fields))
    }
    // Incompatible scalar/array/object branches remain the type owner's error.
    _ => None
  }
}

///|
fn expression_namespace(
  expression : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  resolve_row : (Array[@query.NamePart]) -> Array[(String, String)]?,
  columns : Array[ResultColumn]?,
  max_work : Int,
) -> ExpressionNamespace raise Abort {
  if columns is None { return { root: None, rows: [], remaining: max_work, } }
  let mut remaining = max_work
  let mut current = @query.expression_root(expression)
  let spend = fn(amount : Int) -> Unit raise Abort {
    if amount < 0 || amount > remaining {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: @query.expression_origin(expression, current), }))
    }
    remaining -= amount
  }
  let select_member = fn(view : NamespaceView?, name : @query.NamePart) -> NamespaceView? raise Abort {
    guard view is Some(Row(fields)) else { return None }
    for field in fields {
      spend(1)
      if field.name is Some(original) {
        spend(original.value.length())
        spend(name.value.length())
        if same_name(original, name) { return field.name_view }
      }
    }
    raise Abort(Expression({ issue: @expression.UnknownReference, origin: @query.expression_origin(expression, current), }))
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
          for part in path[length:] { view = select_member(view, part) }
          view
        } else if resolve_row(path) is Some(fields) {
          spend(fields.length())
          let profiles : Array[ResultColumn] = []
          for field in fields {
            spend(columns.unwrap().length())
            profiles.push(result_column_profile(columns, field.0, field.1).unwrap_or({
              slot: field.1, label: field.0,
              name: Some({ value: field.0, quoted: false, }), name_view: None,
            }))
          }
          let (names, after_names) = result_column_display_names_work(profiles, remaining)
          remaining = after_names
          spend(fields.length())
          rows.push((path, fields.mapi((index, field) => (names[index], field.1))))
          Some(Row(profiles.mapi((index, field) => {
            { key: names[index], name: field.name, name_view: field.name_view, }
          })))
        } else { None }
      }
      Property(child, name) => select_member(views[child], name)
      Parenthesized(child) => views[child]
      ArrayOffset(child, _, _) => match views[child] {
        Some(Array(view)) => Some(view)
        _ => None
      }
      StructConstructor(fields) => {
        spend(fields.length())
        if fields.any(field => views[field.1] is Some(_)) {
          Some(Row(fields.map(field => {
            { key: field.0.value, name: Some(field.0), name_view: views[field.1], }
          })))
        } else { None }
      }
      ArrayConstructor(items, _) => {
        let mut view : NamespaceView? = None
        for item in items { view = merge_namespace_views(view, views[item], spend) }
        view.map(view => Array(view))
      }
      SearchedCase(branches, otherwise) => {
        let mut view = views[otherwise]
        for branch in branches { view = merge_namespace_views(view, views[branch.1], spend) }
        view
      }
      Call(path, arguments) => {
        spend(path.length())
        if path.length() != 1 { None } else {
          spend(path[0].value.length())
          let name = ascii_upper(path[0].value)
          if name == "IF" && arguments.length() == 3 {
            merge_namespace_views(views[arguments[1]], views[arguments[2]], spend)
          } else if name == "IFNULL" || name == "COALESCE" {
            let mut view : NamespaceView? = None
            for argument in arguments { view = merge_namespace_views(view, views[argument], spend) }
            view
          } else if name == "NULLIF" && arguments.length() == 2 {
            views[arguments[0]]
          } else { None }
        }
      }
      _ => None
    }
    views.push(view)
  }
  { root: views[@query.expression_root(expression)], rows, remaining, }
}
