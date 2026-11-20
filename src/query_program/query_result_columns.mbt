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
}

///|
priv struct NamespaceField {
  key : String
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
fn scope_named_ranges(
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  profiles : Array[ResultColumn]?,
) -> Array[(@query.NamePart, Array[(String, String)])] {
  guard profiles is Some(_) else { return ranges }
  ranges.map(range => (range.0, scope_named_columns(range.1, profiles)))
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
  columns : Array[ResultColumn],
  names : Array[String],
) -> Array[ResultColumn]? {
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
  result_column_display_names_work(columns, max_work).0
}

///|
fn result_column_display_names_work(
  columns : Array[ResultColumn],
  max_work : Int,
) -> (Array[String], Int) raise Abort {
  let mut remaining = max_work
  let result : Array[String] = []
  for index, column in columns {
    guard remaining > 0 else { raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, })) }
    remaining -= 1
    match column.name {
      Some(name) => result.push(name.value)
      None => {
        let mut candidate = "f" + index.to_string() + "_"
        let mut searching = true
        while searching {
          searching = false
          for other in columns {
            guard remaining > 0 else { raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, })) }
            remaining -= 1
            if other.name is Some(name) {
              // Charge the original name comparison before its temporary
              // case-folded strings, using the existing column-name law.
              if name.value.length() > remaining ||
                candidate.length() > remaining - name.value.length() {
                raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
              }
              remaining -= name.value.length() + candidate.length()
              if same_name(name, { value: candidate, quoted: false, }) {
                guard remaining >= candidate.length() + 1 else {
                  raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
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
  (result, remaining)
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
  guard sources.result_columns.get(input.name) is Some(columns) &&
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
  sources.result_columns[producer] = columns.mapi((index, column) => {
    { ..column, slot: displayed[index], label: displayed[index], }
  })
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
