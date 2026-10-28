///|
/// Shared REST response DATA, not a RowRun, Source or response authority.
struct ManagedJsonPage {
  rows_wire : String
  row_count : Int
  next_cursor : String?
}

///|
pub(all) enum ManagedJsonPageIssue {
  InvalidLimits
  Parse(@source.ParseError)
  ItemsPath
  ItemsShape
  RowLimit
  CursorShape
  CursorLimit
  Wire
} derive(Debug)

///|
fn managed_json_path(
  root : @source.Node,
  path : Array[String],
) -> @source.Node? {
  let mut current = root
  for name in path {
    guard current.value is Object(fields) else { return None }
    let mut found = None
    for field in fields {
      if field.key == name {
        found = Some(field.value)
        break
      }
    }
    guard found is Some(next) else { return None }
    current = next
  }
  Some(current)
}

///|
/// Parse once with the existing preserving parser. Select the original byte
/// span instead of interpreting rounded numeric Nodes or re-encoding rows.
/// The caller has already retained/charged the same physical response; this
/// function does not admit a Source, authorize I/O or reserve a second Ledger.
pub fn project_managed_json_page(
  body : Bytes,
  items_path : Array[String],
  cursor_path : Array[String]?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
) -> Result[ManagedJsonPage, ManagedJsonPageIssue] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 || max_rows < 0 ||
    max_cursor_bytes < 0 || items_path.length() > max_depth ||
    cursor_path is Some(path) && path.length() > max_depth {
    return Err(InvalidLimits)
  }
  let root = @source.parse_json_bytes_preserving(body, {
    max_input_bytes: max_bytes,
    max_nodes,
    max_depth,
  }).map_err(Parse)?
  guard managed_json_path(root, items_path) is Some(selected) else {
    return Err(ItemsPath)
  }
  guard selected.value is Array(items) else { return Err(ItemsShape) }
  if items.length() > max_rows { return Err(RowLimit) }
  let next_cursor = match cursor_path {
    None => None
    Some(path) =>
      match managed_json_path(root, path) {
        None | Some({ value: Null, .. }) => None
        Some({ value: String(text), .. }) => {
          // Bound before allocating the encoded copy. A UTF16 code unit
          // always contributes at least one UTF8 byte for admitted text.
          if text.length() > max_cursor_bytes ||
            @utf8.encode(text).length() > max_cursor_bytes {
            return Err(CursorLimit)
          }
          Some(text)
        }
        _ => return Err(CursorShape)
      }
  }
  let span = selected.span
  if span.start_byte < 0 || span.end_byte < span.start_byte ||
    span.end_byte > body.length() { return Err(Wire) }
  let rows_wire = @utf8.decode(body[span.start_byte:span.end_byte]) catch {
    _ => return Err(Wire)
  }
  Ok({ rows_wire, row_count: items.length(), next_cursor })
}

///|
pub fn managed_json_page_rows_wire(page : ManagedJsonPage) -> String {
  page.rows_wire
}

///|
pub fn managed_json_page_row_count(page : ManagedJsonPage) -> Int {
  page.row_count
}

///|
pub fn managed_json_page_next_cursor(page : ManagedJsonPage) -> String? {
  page.next_cursor
}
