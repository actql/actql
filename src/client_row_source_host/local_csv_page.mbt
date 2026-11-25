///|
/// Closed Local CSV page from bounded, already acquired original file bytes.
pub(all) enum LocalCsvPageIssue {
  InvalidLocalCsvLimits
  InvalidLocalCsvColumns
  InvalidLocalCsvKey
  InvalidLocalCsvHeader
  InvalidLocalCsvWidth
  InvalidLocalCsvQuote
  InvalidLocalCsvSeparator
  InvalidLocalCsvEncoding
  InvalidLocalCsvValue
  InvalidLocalCsvInt64
  DuplicateLocalCsvKey
  LocalCsvBytesLimit
  LocalCsvFieldLimit
  LocalCsvRowsLimit
  LocalFilesPageBytesLimit
} derive(Eq, Debug)

///|
/// Preserve the Local Source refusal code at each installed Host boundary.
pub fn local_csv_page_issue_code(issue : LocalCsvPageIssue) -> String {
  match issue {
    InvalidLocalCsvLimits => "InvalidLocalCsvLimits"
    InvalidLocalCsvColumns => "InvalidLocalCsvColumns"
    InvalidLocalCsvKey => "InvalidLocalCsvKey"
    InvalidLocalCsvHeader => "InvalidLocalCsvHeader"
    InvalidLocalCsvWidth => "InvalidLocalCsvWidth"
    InvalidLocalCsvQuote => "InvalidLocalCsvQuote"
    InvalidLocalCsvSeparator => "InvalidLocalCsvSeparator"
    InvalidLocalCsvEncoding => "InvalidLocalCsvEncoding"
    InvalidLocalCsvValue => "InvalidLocalCsvValue"
    InvalidLocalCsvInt64 => "InvalidLocalCsvInt64"
    DuplicateLocalCsvKey => "DuplicateLocalCsvKey"
    LocalCsvBytesLimit => "LocalCsvBytesLimit"
    LocalCsvFieldLimit => "LocalCsvFieldLimit"
    LocalCsvRowsLimit => "LocalCsvRowsLimit"
    LocalFilesPageBytesLimit => "LocalFilesPageBytesLimit"
  }
}

///|
priv struct LocalCsvCursor {
  bytes : Bytes
  mut offset : Int
  width : Int
  max_field_bytes : Int
}

///|
fn read_local_csv_field(
  cursor : LocalCsvCursor,
) -> Result[String, LocalCsvPageIssue] {
  let bytes = cursor.bytes
  let length = bytes.length()
  let quoted = cursor.offset < length && bytes[cursor.offset] == b'"'
  if quoted {
    cursor.offset += 1
  }
  let start = cursor.offset
  let end = if quoted {
    for offset = cursor.offset {
      if offset == length {
        return Err(InvalidLocalCsvQuote)
      }
      if bytes[offset] != b'"' {
        continue offset + 1
      }
      if offset - start > cursor.max_field_bytes {
        return Err(LocalCsvFieldLimit)
      }
      if offset + 1 < length && bytes[offset + 1] == b'"' {
        continue offset + 2
      }
      cursor.offset = offset + 1
      break offset
    }
  } else {
    while cursor.offset < length {
      match bytes[cursor.offset] {
        b',' | b'\n' | b'\r' => break
        b'"' => return Err(InvalidLocalCsvQuote)
        _ => ()
      }
      if cursor.offset - start == cursor.max_field_bytes {
        return Err(LocalCsvFieldLimit)
      }
      cursor.offset += 1
    }
    cursor.offset
  }
  let text = @utf8.decode(bytes[start:end]) catch {
    _ => return Err(InvalidLocalCsvEncoding)
  }
  if text.contains("\u0000") {
    return Err(InvalidLocalCsvValue)
  }
  Ok(if quoted { text.replace_all(old="\"\"", new="\"") } else { text })
}

///|
fn read_local_csv_record(
  cursor : LocalCsvCursor,
) -> Result[Array[String], LocalCsvPageIssue] {
  let fields : Array[String] = []
  while true {
    if fields.length() == cursor.width {
      return Err(InvalidLocalCsvWidth)
    }
    match read_local_csv_field(cursor) {
      Ok(field) => fields.push(field)
      Err(issue) => return Err(issue)
    }
    if cursor.offset == cursor.bytes.length() {
      break
    }
    let separator = cursor.bytes[cursor.offset]
    cursor.offset += 1
    match separator {
      b',' => continue
      b'\n' => break
      b'\r' if cursor.offset < cursor.bytes.length() &&
        cursor.bytes[cursor.offset] == b'\n' => {
        cursor.offset += 1
        break
      }
      _ => return Err(InvalidLocalCsvSeparator)
    }
  }
  if fields.length() != cursor.width {
    return Err(InvalidLocalCsvWidth)
  }
  Ok(fields)
}

///|
/// Preserve the complete page's typed values and exact key uniqueness. The
/// File Source owner reserves the original raw buffer and page workspace and
/// admits the returned wire through the same RowRun.
pub fn encode_local_csv_page(
  bytes : Bytes,
  column_names : Array[String],
  integer_columns : Array[Bool],
  keys : Array[String],
  max_bytes : Int,
  max_field_bytes : Int,
  max_rows : Int,
  max_page_bytes : Int,
) -> Result[String, LocalCsvPageIssue] {
  if max_bytes <= 0 || max_field_bytes <= 0 || max_rows <= 0 {
    return Err(InvalidLocalCsvLimits)
  }
  if bytes.length() > max_bytes {
    return Err(LocalCsvBytesLimit)
  }
  let width = column_names.length()
  if width == 0 || width != integer_columns.length() {
    return Err(InvalidLocalCsvColumns)
  }
  let declared : Map[String, Bool] = Map([])
  for index in 0..<width {
    let name = column_names[index]
    if name.is_empty() || name.contains("\u0000") || declared.contains(name) {
      return Err(InvalidLocalCsvColumns)
    }
    declared[name] = integer_columns[index]
  }
  let offset = if bytes.length() >= 3 &&
    bytes[0] == 0xef &&
    bytes[1] == 0xbb &&
    bytes[2] == 0xbf {
    3
  } else {
    0
  }
  if offset == bytes.length() {
    return Err(InvalidLocalCsvHeader)
  }
  let cursor = { bytes, offset, width, max_field_bytes, }
  let header = match read_local_csv_record(cursor) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let header_positions : Map[String, Int] = Map([])
  let exact_integers : Array[Bool] = []
  for index in 0..<width {
    let name = header[index]
    guard declared.get(name) is Some(integer) &&
      !header_positions.contains(name) else {
      return Err(InvalidLocalCsvHeader)
    }
    header_positions[name] = index
    exact_integers.push(integer)
  }
  let key_fields : Array[Int] = []
  for key in keys {
    guard header_positions.get(key) is Some(index) &&
      !key_fields.contains(index) else {
      return Err(InvalidLocalCsvKey)
    }
    key_fields.push(index)
  }
  let observed_keys : Map[String, Unit] = Map([])
  let page = StringBuilder()
  page.write_char('[')
  let mut count = 0
  let mut used_bytes = 2
  while cursor.offset < bytes.length() {
    let record = match read_local_csv_record(cursor) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if count == max_rows {
      return Err(LocalCsvRowsLimit)
    }
    let row : Map[String, Json] = Map([])
    for index in 0..<width {
      let text = record[index]
      if exact_integers[index] &&
        (text.length() > 20 || @scalar.read_decimal_int64(text) is Err(_)) {
        return Err(InvalidLocalCsvInt64)
      }
      row[header[index]] = Json::string(text)
    }
    if !key_fields.is_empty() {
      let identity = Json::array(
        key_fields.map(index => Json::string(record[index])),
      ).stringify()
      if observed_keys.contains(identity) {
        return Err(DuplicateLocalCsvKey)
      }
      observed_keys[identity] = ()
    }
    let row_wire = Json::object(row).stringify()
    let separator_bytes = if count == 0 { 0 } else { 1 }
    guard max_page_bytes >= used_bytes &&
      max_page_bytes - used_bytes >= separator_bytes &&
      @scalar.admit_utf8_length(
        row_wire,
        max_page_bytes - used_bytes - separator_bytes,
      )
      is Ok(row_bytes) else {
      return Err(LocalFilesPageBytesLimit)
    }
    if separator_bytes == 1 {
      page.write_char(',')
    }
    page.write_string(row_wire)
    used_bytes += row_bytes + separator_bytes
    count += 1
  }
  if used_bytes > max_page_bytes {
    return Err(LocalFilesPageBytesLimit)
  }
  page.write_char(']')
  Ok(page.to_string())
}
