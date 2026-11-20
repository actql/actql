///|
// The physical slot retains the evaluated value. None is an anonymous SQL
// output, not an alias awaiting insertion into the SQL name environment.
priv struct ResultColumn {
  slot : String
  label : String
  name : @query.NamePart?
  name_view : NamespaceView?
}

///|
// A SQL namespace view is compiler DATA attached to the same evaluated value.
// Object DATA keys remain Strings; optional SQL names never become grants.
priv enum NamespaceView {
  Row(Array[NamespaceField])
  Array(NamespaceView)
  Joined(NamespaceView, NamespaceView)
  Captured(Array[(String, String)], Array[ResultColumn]?)
  Member(NamespaceView, @query.NamePart)
  Element(NamespaceView)
}

///|
priv struct NamespaceField {
  name : @query.NamePart?
  name_view : NamespaceView?
}

///|
fn result_column_profile(
  columns : Array[ResultColumn]?,
  label : String,
  slot : String,
) -> ResultColumn? {
  guard columns is Some(columns) else { return None }
  for column in columns {
    if column.label == label && column.slot == slot {
      return Some(column)
    }
  }
  None
}

///|
// Filter by the original occurrence and slot, never by a generated spelling.
// A different, authored Object/column with the same String remains named.
fn scope_named_columns(
  columns : Array[(String, String)],
  profiles : Array[ResultColumn]?,
) -> Array[(String, String)] {
  guard profiles is Some(_) else { return columns }
  let named : Array[(String, String)] = []
  for (label, slot) in columns {
    match result_column_profile(profiles, label, slot) {
      Some({ name: None, .. }) => ()
      Some({ name: Some(name), .. }) => named.push((name.value, slot))
      None => named.push((label, slot))
    }
  }
  named
}

///|
fn projection_result_column(
  projection : @query.Projection,
  label : String,
  name_view? : NamespaceView? = None,
) -> ResultColumn {
  { slot: label, label, name: projection_alias(projection), name_view, }
}

///|
fn selected_result_columns(
  columns : Array[ResultColumn]?,
  names : Array[String],
) -> Array[ResultColumn]? {
  guard columns is Some(columns) else { return None }
  if !columns.any(column => column.name is None || column.name_view is Some(_)) {
    return None
  }
  Some(columns.mapi((index, column) => {
    { ..column, slot: names[index], label: names[index], }
  }))
}

///|
// Result display spelling is assigned only after SQL resolution. Every authored
// or implicit name, including later columns, reserves its spelling first.
// Different anonymous positions have different decimal stems; only authored
// names can collide with a generated stem or its underscore suffixes.
fn result_column_display_names(
  columns : Array[ResultColumn],
  max_work : Int,
) -> Array[String] raise Abort {
  match result_column_display_names_work(columns, max_work) {
    Ok((names, _)) => names
    Err(issue) => raise Abort(Expression({ issue, origin: None, }))
  }
}

///|
fn result_column_display_names_work(
  columns : Array[ResultColumn],
  max_work : Int,
) -> Result[(Array[String], Int), @expression.Issue] {
  let mut remaining = max_work
  let result : Array[String] = []
  for index, column in columns {
    guard remaining > 0 else { return Err(@expression.WorkLimit) }
    remaining -= 1
    match column.name {
      Some(name) => result.push(name.value)
      None => {
        let mut candidate = "f" + index.to_string() + "_"
        let mut searching = true
        while searching {
          searching = false
          for other in columns {
            guard remaining > 0 else { return Err(@expression.WorkLimit) }
            remaining -= 1
            if other.name is Some(name) {
              // Charge the original name comparison before its temporary
              // case-folded strings, using the existing column-name law.
              if name.value.length() > remaining ||
                candidate.length() > remaining - name.value.length() {
                return Err(@expression.WorkLimit)
              }
              remaining -= name.value.length() + candidate.length()
              if same_name(name, { value: candidate, quoted: false, }) {
                guard remaining >= candidate.length() + 1 else {
                  return Err(@expression.WorkLimit)
                }
                remaining -= candidate.length() + 1
                candidate += "_"
                searching = true
                break
              }
            }
          }
        }
        result.push(candidate)
      }
    }
  }
  Ok((result, remaining))
}

///|
// This is the last public projection, after all SQL name/order resolution.
// Retain None in compiler DATA even though the wire Result needs String keys.
fn publish_script_result_columns(
  construction : Construction,
  sources : ScriptSources,
  input : Input,
  steps : Array[@builder.Node],
  reserved : Array[String],
  max_work : Int,
) -> Input raise Abort {
  guard script_result_columns(sources, input.name) is Some(columns) &&
    columns.any(column => column.name is None) else {
    return input
  }
  let displayed = result_column_display_names(columns, max_work)
  let producer = pipe_physical_name(reserved, "aql_result_display_")
  reserved.push(producer)
  steps.push(
    construction.object([
      ("from", construction.text(input.name)),
      (
        "select",
        set_select_fields(construction, displayed, columns.map(column => column.slot)),
      ),
      ("as", construction.text(producer)),
    ]),
  )
  put_script_result_columns(sources, producer, columns.mapi((index, column) => {
    { ..column, slot: displayed[index], label: displayed[index], }
  }))
  { ..input, name: producer, visible_fields: displayed, }
}

///|
fn join_result_columns(
  left : Array[ResultColumn]?,
  right : Array[ResultColumn]?,
  left_slots : Map[String, String]?,
  right_slots : Map[String, String],
) -> Array[ResultColumn]? {
  if left is None && right is None { return None }
  let result : Array[ResultColumn] = []
  if left is Some(columns) {
    for column in columns {
      result.push({ ..column, slot: left_slots.map(slots => slots[column.slot]).unwrap_or(column.slot), })
    }
  }
  if right is Some(columns) {
    for column in columns {
      result.push({ ..column, slot: right_slots[column.slot], })
    }
  }
  Some(result)
}

///|
// Set correspondence uses the same proven physical alignment as the operation.
// The left public column role survives; nested anonymous restrictions from
// either operand survive the value/type join. This does not validate values.
fn merge_set_result_columns(
  left : Array[ResultColumn]?,
  right : Array[ResultColumn]?,
  output : Array[String],
  left_matched : Array[String],
  right_matched : Array[String],
  max_work : Int,
) -> Array[ResultColumn]? raise Abort {
  if left is None && right is None { return None }
  guard output.length() == left_matched.length() && output.length() == right_matched.length() else { raise Abort(InvalidContext) }
  let mut remaining = max_work
  let spend = fn(amount : Int) -> Unit raise Abort {
    if amount < 0 || amount > remaining { raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, })) }
    remaining -= amount
  }
  let result : Array[ResultColumn] = []
  for index, name in output {
    spend(1)
    spend(left.map(columns => columns.length()).unwrap_or(0))
    spend(right.map(columns => columns.length()).unwrap_or(0))
    let original = result_column_profile(left, left_matched[index], left_matched[index])
    let incoming = result_column_profile(right, right_matched[index], right_matched[index])
    result.push({
      label: name, slot: name,
      name: original.map(column => column.name).unwrap_or(Some({ value: name, quoted: false, })),
      name_view: merge_namespace_views(original.bind(column => column.name_view), incoming.bind(column => column.name_view), spend),
    })
  }
  Some(result)
}

///|
fn script_result_columns(sources : ScriptSources, input : String) -> Array[ResultColumn]? {
  sources.result_columns.bind(columns => columns.get(input))
}

///|
// No namespace Map is constructed on the proven all-named path. This is the
// same private compiler table; entries never contain a checked/current grant.
fn put_script_result_columns(sources : ScriptSources, input : String, columns : Array[ResultColumn]) -> Unit {
  if sources.result_columns is None { sources.result_columns = Some(Map([])) }
  sources.result_columns.unwrap()[input] = columns
}

///|
// A newly evaluated slot has its own namespace. Keep the old vector immutable
// for captured AS rows and sibling expressions; never update an old slot's view.
fn retain_column_view(
  columns : Array[ResultColumn]?,
  name : @query.NamePart,
  slot : String,
  view : NamespaceView?,
) -> Array[ResultColumn]? {
  guard view is Some(_) else { return columns }
  Some(columns.unwrap_or([]) + [{ label: name.value, slot, name: Some(name), name_view: view, }])
}
