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
/// One complete raw CSV file and its typed page share the Source's workspace.
/// This quote does not reserve capacity or authorize a Root read.
pub(all) struct LocalCsvPageTransport {
  transfer_bytes : Int64
  execution_bytes : Int64
  max_rows : Int64
}

///|
/// Keep the installed Local File transport dimensions for this exact table.
/// Cover the read block, raw file, decoded fields, key index and RowRun wire
/// that coexist before the original reader can close.
pub fn LocalCsvTable::page_transport(
  self : LocalCsvTable,
  max_file_bytes : Int64,
  max_page_bytes : Int64,
  max_files : Int64,
  max_page_rows : Int64,
) -> LocalCsvPageTransport? {
  if max_file_bytes < 0L ||
    max_page_bytes <= 0L ||
    max_files <= 0L ||
    max_page_rows <= 0L {
    return None
  }
  let transfer_bytes = Int64::min(max_file_bytes, max_page_bytes)
  let max_rows = Int64::min(max_files, max_page_rows)
  guard @execution.checked_preparation_add_product(65536L, transfer_bytes, 32L)
    is Some(input_and_fields) &&
    @execution.checked_preparation_add_product(
      input_and_fields, max_page_bytes, 8L,
    )
    is Some(through_row_run) &&
    @execution.checked_preparation_add_product(through_row_run, max_rows, 256L)
    is Some(through_keys) &&
    @execution.checked_preparation_add_product(
      through_keys,
      self.column_names.length().to_int64(),
      256L,
    )
    is Some(execution_bytes) else {
    return None
  }
  Some({ transfer_bytes, execution_bytes, max_rows, })
}

///|
/// Quote the same selected one-page format for a fenced file size.
/// The stat is only a physical size bound. It does not authorize the file,
/// claim an acquired row count or change the declared page/transfer ceilings.
pub fn LocalCsvTable::observed_extent_transport(
  self : LocalCsvTable,
  declared : LocalCsvPageTransport,
  declared_page_bytes : Int,
  observed_bytes : Int64,
) -> (LocalCsvPageTransport, Int)? {
  let width = self.column_names.length().to_int64()
  if width < 1L ||
    observed_bytes < 0L ||
    observed_bytes > declared.transfer_bytes ||
    declared_page_bytes < 1 ||
    declared.max_rows < 1L {
    return None
  }
  let mut key_bytes = 0L
  for name in self.column_names {
    guard @execution.checked_preparation_add_product(
        key_bytes, name.length().to_int64(), 6L,
      ) is Some(total) else {
      return None
    }
    key_bytes = total
  }
  // Each record consumes its field separators and a line separator,
  // except the last. The header can only lower this upper bound.
  let raw = Int64::max(1L, observed_bytes)
  guard @execution.checked_preparation_add_product(raw, 1L, 1L)
    is Some(terminated) else {
    return None
  }
  let rows = Int64::min(declared.max_rows, Int64::max(1L, terminated / width))
  // JSON strings can escape a raw byte to six bytes. Count the declared
  // keys and all object, member, string, array and comma punctuation.
  guard @execution.checked_preparation_add_product(key_bytes + 3L, width, 6L)
    is Some(row_overhead) &&
    @execution.checked_preparation_add_product(2L, raw, 6L)
    is Some(value_bytes) &&
    @execution.checked_preparation_add_product(value_bytes, rows, row_overhead)
    is Some(wire_upper) else {
    return None
  }
  let page = Int64::min(declared_page_bytes.to_int64(), wire_upper)
  self.page_transport(raw, page, rows, rows)
  .map(quote => (quote, page.to_int()))
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
  if max_depth < 0 || @scalar.admit_utf8_length(path, max_path_bytes) is Err(_) {
    return false
  }
  let mut depth = 0
  let mut component_length = 0
  let mut only_dots = true
  for index in 0..<path.length() {
    let unit = path.code_unit_at(index).to_int()
    if unit == 0 {
      return false
    }
    if unit == 47 {
      if component_length == 0 ||
        (only_dots && component_length <= 2) ||
        depth == max_depth {
        return false
      }
      depth += 1
      component_length = 0
      only_dots = true
    } else {
      component_length += 1
      only_dots = only_dots && unit == 46
    }
  }
  component_length > 0 && (!only_dots || component_length > 2)
}

///|
/// A Local source declaration reserves two view slots for files and contents.
pub fn local_file_max_csv_views() -> Int {
  declaration_limits.max_views - 2
}

///|
/// Select CSV by the authored format, or by the existing .csv rule when
/// the format is omitted. No table schema or column inventory is constructed.
pub fn local_csv_table_is_selected(table : @decode.Cursor) -> Bool {
  match @decode.lookup_original_field(table, "format") {
    Some(format) => @decode.is_text(format) && @decode.text(format) == Ok("csv")
    None =>
      if @decode.lookup_original_field(table, "path") is Some(path) &&
        @decode.is_text(path) &&
        @decode.text(path) is Ok(value) {
        value.has_suffix(".csv")
      } else {
        false
      }
  }
}

///|
/// Project one selected descriptor. Other formats retain their own preparation.
pub fn prepare_local_csv_table(
  resource : String,
  table : @decode.Cursor,
  max_path_bytes : Int,
  max_depth : Int,
) -> Result[LocalCsvTable?, LocalCsvTableIssue] {
  guard local_csv_table_is_selected(table) else { return Ok(None) }
  guard !resource.is_empty() &&
    resource != "files" &&
    resource != "contents" &&
    !resource.contains("\u{0000}") &&
    @scalar.admit_utf8_length(resource, 128) is Ok(_) else {
    return Err(InvalidLocalCsvResource)
  }
  guard @decode.lookup_original_field(table, "path") is Some(path) &&
    @decode.is_text(path) &&
    @decode.text(path) is Ok(path) &&
    local_csv_path_matches_limits(path, max_path_bytes, max_depth) else {
    return Err(InvalidLocalCsvPath)
  }
  guard @decode.lookup_original_field(table, "columns") is Some(columns) &&
    @decode.object_length(columns) is Some(width) &&
    local_csv_column_count_is_valid(width) else {
    return Err(InvalidLocalCsvColumns)
  }
  let column_names : Array[String] = Array(capacity=width)
  let integer_columns : Array[Bool] = Array(capacity=width)
  for index in 0..<width {
    guard @decode.field_at(columns, index) is Some((name, kind)) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") &&
      @decode.is_text(kind) else {
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
  match @decode.lookup_original_field(table, "key") {
    None => ()
    Some(key) => {
      guard @decode.array_length(key) is Some(count) &&
        count > 0 &&
        count <= width else {
        return Err(InvalidLocalCsvKey)
      }
      let names = @decode.open_object(columns).unwrap()
      for index in 0..<count {
        guard @decode.element_at(key, index) is Some(element) &&
          @decode.is_text(element) &&
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
