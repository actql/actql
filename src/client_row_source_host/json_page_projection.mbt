///|
/// Provider-neutral envelope DATA. The original RowRun separately admits the
/// complete row objects under its declared schema and owns physical charges.
struct RowSourceJsonPage {
  rows_wire : String
  row_count : Int
  next_cursor : String?
}

///|
pub(all) enum RowSourceJsonPageIssue {
  InvalidLimits
  InvalidPage
  InvalidItems
  InvalidCursor
  NoNextCursor
} derive(Eq, Debug)

///|
fn json_page_path(
  root : @source.Node,
  path : Array[String],
) -> Result[@source.Node?, RowSourceJsonPageIssue] {
  let mut current = root
  for name in path {
    match current.value {
      @source.Null => return Ok(None)
      @source.Object(fields) => {
        let mut found = None
        for field in fields {
          if field.key == name {
            found = Some(field.value)
            break
          }
        }
        match found {
          Some(value) => current = value
          None => return Ok(None)
        }
      }
      _ => return Err(InvalidPage)
    }
  }
  Ok(Some(current))
}

///|
/// Validate the whole original document before selecting any output. Its
/// array span preserves numeric tokens, whitespace, keys and literal values;
/// no parser Double is converted back to a number or a row value here.
pub fn project_row_source_json_page(
  bytes : Bytes,
  items_path : Array[String],
  cursor_present : Bool,
  cursor_path : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
) -> Result[RowSourceJsonPage, RowSourceJsonPageIssue] {
  if max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_rows < 0 ||
    max_cursor_bytes < 0 ||
    items_path.length() > max_depth ||
    cursor_path.length() > max_depth ||
    (!cursor_present && !cursor_path.is_empty()) {
    return Err(InvalidLimits)
  }
  for path in [items_path, cursor_path] {
    for name in path {
      if @scalar.admit_utf8_length(name, max_bytes) is Err(_) {
        return Err(InvalidLimits)
      }
    }
  }
  let root = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Err(_) => return Err(InvalidPage)
    Ok(value) => value
  }
  guard json_page_path(root, items_path) is Ok(Some(selected)) &&
    selected.value is @source.Array(rows) &&
    rows.length() <= max_rows else {
    return Err(InvalidItems)
  }
  for row in rows {
    if !(row.value is @source.Object(_)) {
      return Err(InvalidItems)
    }
  }
  let cursor = if cursor_present {
    match json_page_path(root, cursor_path) {
      Ok(None) => None
      Ok(Some({ value: @source.Null, .. })) => None
      Ok(Some({ value: @source.String(text), .. })) => {
        if @scalar.admit_utf8_length(text, max_cursor_bytes) is Err(_) {
          return Err(InvalidCursor)
        }
        Some(text)
      }
      _ => return Err(InvalidCursor)
    }
  } else {
    None
  }
  let span = selected.span
  if span.start_byte < 0 ||
    span.end_byte <= span.start_byte ||
    span.end_byte > bytes.length() {
    return Err(InvalidPage)
  }
  let rows_wire = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
    _ => return Err(InvalidPage)
  }
  Ok({ rows_wire, row_count: rows.length(), next_cursor: cursor, })
}

///|
pub fn row_source_json_page_rows_wire(value : RowSourceJsonPage) -> String {
  value.rows_wire
}

///|
pub fn row_source_json_page_row_count(value : RowSourceJsonPage) -> Int {
  value.row_count
}

///|
pub fn row_source_json_page_has_next_cursor(value : RowSourceJsonPage) -> Bool {
  value.next_cursor is Some(_)
}

///|
pub fn row_source_json_page_next_cursor(
  value : RowSourceJsonPage,
) -> Result[String, RowSourceJsonPageIssue] {
  match value.next_cursor {
    Some(text) => Ok(text)
    None => Err(NoNextCursor)
  }
}
