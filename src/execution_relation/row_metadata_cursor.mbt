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
