///|
/// One bounded transport frame, not admission or a cumulative execution budget.
pub(all) struct TransportColumnLimits {
  max_bytes : Int
  max_nodes : Int
  max_columns : Int
  max_rows : Int
  max_text_bytes : Int
}

///|
pub(all) enum TransportColumnIssue {
  InvalidLimits
  InputLimit
  NodeLimit
  ColumnLimit
  RowLimit
  TextLimit
  InvalidShape
  InvalidJson
  InvalidUnicode
  Decode(@decode.Issue)
} derive(Eq, Debug)

///|
/// Raw physical scalars must not use the authoring JSON parser, which normalizes
/// NFC/LF. Preflight forbids nesting beyond columns and bounds allocation before
/// the general JSON parser runs. SQL scalar meaning remains in value admission.
pub fn decode_transport_columns(
  text : String,
  limits : TransportColumnLimits,
) -> Result[Array[@decode.Cursor], TransportColumnIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_columns < 0 ||
    limits.max_rows < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let bytes = match @scalar.admit_utf8_length(text, limits.max_bytes) {
    Ok(bytes) => bytes
    Err(MalformedUtf16(_)) => return Err(InvalidUnicode)
    Err(_) => return Err(InputLimit)
  }
  let (end_line, end_column) = match preflight_transport_columns(text, limits) {
    Err(issue) => return Err(issue)
    Ok(position) => position
  }
  let parsed = @json.parse(text) catch { _ => return Err(InvalidJson) }
  guard parsed is Array(columns) else { return Err(InvalidShape) }
  let span : @source.Span = {
    start_byte: 0,
    end_byte: bytes,
    start_line: 1,
    start_column: 1,
    end_line,
    end_column,
    source_path: "<duckdb-column-transport>",
  }
  let output = []
  let mut remaining_text = limits.max_text_bytes
  for column in columns {
    guard column is Array(values) else { return Err(InvalidShape) }
    let cursor = match
      @decode.admit_raw_scalar_column(values, span, {
        max_nodes: limits.max_nodes,
        max_depth: 1,
        max_string_bytes: limits.max_text_bytes,
        max_total_string_bytes: remaining_text,
      }) {
      Ok(cursor) => cursor
      Err(issue) =>
        match issue.kind {
          @decode.InvalidUnicode => return Err(InvalidUnicode)
          @decode.WrongType => return Err(InvalidShape)
          // Depth and node count were bounded by the frame preflight.
          @decode.BudgetExceeded => return Err(TextLimit)
          _ => return Err(Decode(issue))
        }
    }
    remaining_text -= @decode.admission_usage(cursor).total_string_bytes
    output.push(cursor)
  }
  Ok(output)
}

///|
fn preflight_transport_columns(
  text : String,
  limits : TransportColumnLimits,
) -> Result[(Int, Int), TransportColumnIssue] {
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  let mut nodes = 0
  let mut columns = 0
  let mut rows = 0
  let mut end_line = 1
  let mut end_column = 1
  for char in text.iter() {
    if char == '\n' {
      end_line += 1
      end_column = 1
    } else {
      end_column += 1
    }
    if quoted {
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        quoted = false
      }
      continue
    }
    let mut value = false
    match char {
      '[' => {
        if depth >= 2 {
          return Err(InvalidShape)
        }
        depth += 1
        if depth == 2 {
          if columns == limits.max_columns {
            return Err(ColumnLimit)
          }
          columns += 1
          rows = 0
        }
        value = true
      }
      ']' => {
        if depth == 0 {
          return Err(InvalidShape)
        }
        depth -= 1
      }
      '"' => {
        if depth != 2 {
          return Err(InvalidShape)
        }
        quoted = true
        value = true
      }
      't' | 'f' | 'n' => {
        if depth != 2 {
          return Err(InvalidShape)
        }
        value = true
      }
      ',' | ' ' | '\n' | '\r' | '\t' | 'r' | 'u' | 'e' | 'a' | 'l' | 's' => ()
      _ => return Err(InvalidShape)
    }
    if value {
      if nodes == limits.max_nodes {
        return Err(NodeLimit)
      }
      nodes += 1
      if depth == 2 && char != '[' {
        if rows == limits.max_rows {
          return Err(RowLimit)
        }
        rows += 1
      }
    }
  }
  if quoted || depth != 0 {
    return Err(InvalidJson)
  }
  Ok((end_line, end_column))
}
