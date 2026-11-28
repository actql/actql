///|
/// Container lengths do not allocate detached child arrays or field maps.
pub fn array_length(cursor : Cursor) -> Int? {
  match cursor.tree[cursor.index].value {
    ArrayValue(items) => Some(items.length())
    _ => None
  }
}

///|
/// Wrong container kinds and out-of-range indices return None; null is a cursor.
pub fn element_at(cursor : Cursor, position : Int) -> Cursor? {
  match cursor.tree[cursor.index].value {
    ArrayValue(items) => items.get(position).map(index => { ..cursor, index, })
    _ => None
  }
}

///|
pub fn object_length(cursor : Cursor) -> Int? {
  match cursor.tree[cursor.index].value {
    ObjectValue(fields) => Some(fields.length())
    _ => None
  }
}

///|
/// Field order is admitted source order, not canonical key order.
pub fn field_at(cursor : Cursor, position : Int) -> (String, Cursor)? {
  match cursor.tree[cursor.index].value {
    ObjectValue(fields) =>
      fields
      .get(position)
      .map(field => (field.key, { ..cursor, index: field.index, }))
    _ => None
  }
}

///|
/// Borrow one field of a small original object without building a field map.
/// Missing fields and other container kinds return None; null is a cursor.
pub fn lookup_original_field(cursor : Cursor, name : String) -> Cursor? {
  guard cursor.tree[cursor.index].value is ObjectValue(fields) else {
    return None
  }
  for field in fields {
    if field.key == name {
      return Some({ ..cursor, index: field.index, })
    }
  }
  None
}
