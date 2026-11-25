///|
/// One admitted table from the original Local connector entry. The path is
/// relative DATA for the Host's selected Root and does not authorize reads.
pub(all) struct LocalCsvTable {
  path : String
  column_names : Array[String]
  integer_columns : Array[Bool]
  keys : Array[String]
  view : RowRelationViewSpec
}

///|
pub(all) enum LocalCsvTableIssue {
  InvalidLocalCsvResource
  InvalidLocalCsvPath
  InvalidLocalCsvColumns
  InvalidLocalCsvKey
} derive(Eq, Debug)

///|
pub fn local_csv_table_issue_code(issue : LocalCsvTableIssue) -> String {
  match issue {
    InvalidLocalCsvResource => "InvalidLocalCsvResource"
    InvalidLocalCsvPath => "InvalidLocalCsvPath"
    InvalidLocalCsvColumns => "InvalidLocalCsvColumns"
    InvalidLocalCsvKey => "InvalidLocalCsvKey"
  }
}

///|
fn local_csv_path_matches_limits(
  path : String,
  max_path_bytes : Int,
  max_depth : Int,
) -> Bool {
  if path.contains("\u{0000}") ||
    @scalar.admit_utf8_length(path, max_path_bytes) is Err(_) {
    return false
  }
  let mut depth = -1
  for component in path.split("/") {
    depth += 1
    if depth > max_depth ||
      component == "" ||
      component == "." ||
      component == ".." {
      return false
    }
  }
  true
}

///|
/// Select CSV by the authored format, or by the existing .csv rule when
/// the format is omitted. Other table types remain with their own Prepare.
pub fn prepare_local_csv_table(
  resource : String,
  table : @decode.Cursor,
  max_path_bytes : Int,
  max_depth : Int,
) -> Result[LocalCsvTable?, LocalCsvTableIssue] {
  guard @decode.open_object(table) is Ok(entry) else { return Ok(None) }
  let path = @decode.lookup(entry, "path").bind(value => {
    @decode.text(value).to_option()
  })
  match @decode.field(entry, "format") {
    Missing =>
      if !path.map(value => value.has_suffix(".csv")).unwrap_or(false) {
        return Ok(None)
      }
    Present(format) => if @decode.text(format) != Ok("csv") { return Ok(None) }
    ExplicitNull => return Ok(None)
  }
  guard !resource.is_empty() &&
    resource != "files" &&
    resource != "contents" &&
    !resource.contains("\u{0000}") &&
    @scalar.admit_utf8_length(resource, 128) is Ok(_) else {
    return Err(InvalidLocalCsvResource)
  }
  guard path is Some(path) &&
    local_csv_path_matches_limits(path, max_path_bytes, max_depth) else {
    return Err(InvalidLocalCsvPath)
  }
  guard @decode.lookup(entry, "columns") is Some(columns) &&
    @decode.object_length(columns) is Some(width) &&
    width > 0 else {
    return Err(InvalidLocalCsvColumns)
  }
  let column_names = []
  let integer_columns = []
  for index in 0..<width {
    guard @decode.field_at(columns, index) is Some((name, kind)) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") else {
      return Err(InvalidLocalCsvColumns)
    }
    let integer = match @decode.text(kind) {
      Ok("int64") => true
      Ok("string") => false
      _ => return Err(InvalidLocalCsvColumns)
    }
    column_names.push(name)
    integer_columns.push(integer)
  }
  let keys : Array[String] = []
  match @decode.field(entry, "key") {
    Missing => ()
    ExplicitNull => return Err(InvalidLocalCsvKey)
    Present(key) => {
      guard @decode.array_length(key) is Some(count) &&
        count > 0 &&
        count <= width else {
        return Err(InvalidLocalCsvKey)
      }
      let names = @decode.open_object(columns).unwrap()
      for index in 0..<count {
        guard @decode.element_at(key, index) is Some(element) &&
          @decode.text(element) is Ok(name) &&
          @decode.lookup(names, name) is Some(_) &&
          !keys.contains(name) else {
          return Err(InvalidLocalCsvKey)
        }
        keys.push(name)
      }
    }
  }
  match
    project_local_csv_relation_view(
      resource, column_names, integer_columns, keys,
    ) {
    Ok(view) => Ok(Some({ path, column_names, integer_columns, keys, view, }))
    Err(_) => Err(InvalidLocalCsvColumns)
  }
}
