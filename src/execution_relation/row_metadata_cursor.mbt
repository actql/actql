///|
priv struct RowMetadataLookup {
  schema : @schema.Schema
  name : @schema.FieldName
  workspace : RowWorkspace
  mut column : Int
  mut offset : Int
  mut closed : Bool
}

///|
/// Borrow checked schema fields and virtual qualification. No whole-name
/// flattening, hashing or equality scan occurs between resume boundaries.
fn start_row_metadata_lookup(
  schema : @schema.Schema,
  name : @schema.FieldName,
  workspace : RowWorkspace,
) -> RowMetadataLookup? {
  if !reserve_slots(workspace, 1) {
    return None
  }
  Some({ schema, name, workspace, column: 0, offset: 0, closed: false, })
}

///|
fn close_row_metadata_lookup(cursor : RowMetadataLookup) -> Unit {
  if !cursor.closed {
    cursor.closed = true
    release_slots(cursor.workspace, 1)
  }
}

///|
/// None means another bounded comparison is needed. A terminal -1 is absence,
/// not a NULL column; the caller retains its existing typed refusal.
fn advance_row_metadata_lookup(cursor : RowMetadataLookup) -> Int? {
  if cursor.closed {
    return Some(-1)
  }
  guard @schema.field_at(cursor.schema, cursor.column) is Some(field) else {
    close_row_metadata_lookup(cursor)
    return Some(-1)
  }
  let (order, offset, _) = @schema.compare_reference_fragment(
    cursor.name,
    field.name,
    cursor.offset,
    64,
  )
  cursor.offset = offset
  match order {
    None => None
    Some(0) => {
      let column = cursor.column
      close_row_metadata_lookup(cursor)
      Some(column)
    }
    Some(_) => {
      cursor.column += 1
      None
    }
  }
}

///|
/// Preserve the original per-candidate lookup charge without scanning a whole
/// spelling between stop observations. The underlying lookup owns one slot;
/// the wrapper borrows the schema and virtual qualification, never an array.
priv struct ChargedRowMetadataLookup {
  lookup : RowMetadataLookup
  charge_candidate : Bool
  mut phase : Int
  mut offset : Int
}

///|
fn start_charged_row_metadata_lookup(
  schema : @schema.Schema,
  field : @schema.FieldName,
  workspace : RowWorkspace,
  charge_candidate : Bool,
) -> ChargedRowMetadataLookup? {
  start_row_metadata_lookup(schema, field, workspace).map(lookup => {
    lookup,
    charge_candidate,
    phase: 0,
    offset: 0,
  })
}

///|
fn advance_charged_row_metadata_lookup(
  cursor : ChargedRowMetadataLookup,
  control : ControlBudget,
) -> Result[Int?, RowIssue] {
  let lookup = cursor.lookup
  if lookup.closed {
    return Err(InvalidRows)
  }
  guard @schema.field_reference_name_at(lookup.schema, lookup.column)
    is Some(candidate) else {
    close_row_metadata_lookup(lookup)
    return Ok(Some(-1))
  }
  match cursor.phase {
    0 => {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      cursor.phase = 1
    }
    1 => {
      let (prefix, text) = match lookup.name {
        @schema.Unqualified(text) => (0, text)
        @schema.Qualified(@schema.Left, text) => (5, text)
        @schema.Qualified(@schema.Right, text) => (6, text)
      }
      if cursor.offset < prefix {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        cursor.offset += 1
      } else if cursor.offset - prefix < text.length() {
        guard text_function_scalar(text, cursor.offset - prefix)
          is Some((_, next, width, _)) &&
          spend_control(control, width) else {
          return Err(RowLimit)
        }
        cursor.offset = prefix + next
      } else {
        cursor.offset = 0
        cursor.phase = if cursor.charge_candidate { 2 } else { 3 }
      }
    }
    2 =>
      if cursor.offset < candidate.length() {
        guard text_function_scalar(candidate, cursor.offset)
          is Some((_, next, width, _)) &&
          spend_control(control, width) else {
          return Err(RowLimit)
        }
        cursor.offset = next
      } else {
        cursor.offset = 0
        cursor.phase = 3
      }
    _ => {
      let before = lookup.column
      let result = advance_row_metadata_lookup(lookup)
      if result is Some(_) {
        return Ok(result)
      }
      if lookup.column != before {
        cursor.phase = 0
      }
    }
  }
  Ok(None)
}

///|
fn bounded_small_schema_names(schema : @schema.Schema) -> Bool {
  let count = @schema.field_count(schema)
  if count > 8 {
    return false
  }
  for column in 0..<count {
    guard @schema.field_reference_name_at(schema, column) is Some(name) &&
      name.length() <= 64 else {
      return false
    }
  }
  true
}

///|
/// Resolve a checked key once, reserve its eventual entries once, and charge
/// its original spelling across resumable scalar boundaries. Lookup authority
/// remains the admitted input schema; absence retains the typed row failure.
fn advance_row_term_preparation(
  state : BoundedBindingRowsState,
  field : @schema.FieldName,
  slots : Int,
) -> Result[Int?, RowIssue] {
  if state.term_column is None {
    let schema = bounded_binding_input_schema(state.input)
    let column = if state.stepped_metadata {
      if state.metadata_lookup is None {
        guard start_row_metadata_lookup(schema, field, state.workspace)
          is Some(cursor) else {
          return Err(RowLimit)
        }
        state.metadata_lookup = Some(cursor)
      }
      match advance_row_metadata_lookup(state.metadata_lookup.unwrap()) {
        None => return Ok(None)
        Some(column) => {
          state.metadata_lookup = None
          column
        }
      }
    } else {
      state.input_ordinals.get(@schema.reference_name(field)).unwrap_or(-1)
    }
    if column < 0 {
      return Err(InvalidRows)
    }
    if !reserve_slots(state.workspace, slots) ||
      !spend_control(state.control, 1) {
      return Err(RowLimit)
    }
    state.term_column = Some(column)
  }
  let column = state.term_column.unwrap()
  guard @schema.field_reference_name_at(
      bounded_binding_input_schema(state.input),
      column,
    )
    is Some(name) else {
    return Err(InvalidRows)
  }
  match advance_binding_name_control_bytes(state, name) {
    Err(issue) => Err(issue)
    Ok(false) => Ok(None)
    Ok(true) => {
      state.term_column = None
      Ok(Some(column))
    }
  }
}
