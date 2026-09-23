///|
/// The initial ActSQL dialect accepts only SELECT signed-Int AS name clauses.
/// Its output is a Program document; the common checker remains authoritative.
pub(all) struct LiteralSelectLimits {
  max_source_bytes : Int
  max_columns : Int
  max_program_bytes : Int
}

///|
pub(all) enum LiteralSelectIssue {
  InvalidLimits
  UnsupportedSyntax(Int)
  DuplicateColumn(Int)
  InvalidInteger(Int)
  OutputLimit
} derive(Eq, Debug)

///|
pub(all) struct LiteralColumnSource {
  name : String
  literal_offset : Int
  alias_offset : Int
} derive(Eq, Debug)

///|
pub(all) struct LiteralSelectProgram {
  document : String
  columns : Array[LiteralColumnSource]
} derive(Eq, Debug)

///|
priv struct Token {
  text : String
  offset : Int
  integer : Bool
}

///|
fn letter(value : Int) -> Bool {
  (value >= 65 && value <= 90) || (value >= 97 && value <= 122) || value == 95
}

///|
fn digit(value : Int) -> Bool {
  value >= 48 && value <= 57
}

///|
fn identifier(text : String) -> Bool {
  let bytes = @utf8.encode(text)
  if bytes.length() == 0 || !letter(bytes[0].to_int()) {
    return false
  }
  for byte in bytes[1:] {
    let value = byte.to_int()
    if !letter(value) && !digit(value) {
      return false
    }
  }
  !["select", "as", "from", "where"].contains(text.to_lower()) &&
  text != "__cid" &&
  !text.has_prefix("__actql_")
}

///|
fn lex(source : Bytes) -> Result[Array[Token], LiteralSelectIssue] {
  let tokens : Array[Token] = []
  let mut offset = 0
  while offset < source.length() {
    let value = source[offset].to_int()
    if value == 32 || value == 9 || value == 10 || value == 13 {
      offset += 1
      continue
    }
    let start = offset
    let mut integer = false
    if value == 44 || value == 59 {
      offset += 1
    } else if letter(value) {
      offset += 1
      while offset < source.length() {
        let next = source[offset].to_int()
        if !letter(next) && !digit(next) {
          break
        }
        offset += 1
      }
    } else if digit(value) || value == 45 {
      integer = true
      if value == 45 {
        offset += 1
      }
      if offset >= source.length() || !digit(source[offset].to_int()) {
        return Err(UnsupportedSyntax(start))
      }
      while offset < source.length() && digit(source[offset].to_int()) {
        offset += 1
      }
    } else {
      return Err(UnsupportedSyntax(start))
    }
    let word = @utf8.decode(source[start:offset]) catch {
      _ => return Err(UnsupportedSyntax(start))
    }
    tokens.push({ text: word, offset: start, integer, })
  }
  Ok(tokens)
}

///|
fn emit_program(
  columns : Array[(String, Int)],
  program_id : String,
  limits : LiteralSelectLimits,
) -> Result[String, LiteralSelectIssue] {
  let output = @encode.writer(
    limits.max_program_bytes,
    limits.max_columns * 10 + 100,
    16,
  ) catch {
    _ => return Err(OutputLimit)
  }
  try {
    @encode.begin_object(output)
    @encode.key(output, "version")
    @encode.string_value(output, "actql/0.1")
    @encode.key(output, "id")
    @encode.string_value(output, program_id)
    @encode.key(output, "stages")
    @encode.begin_array(output)
    @encode.begin_object(output)
    @encode.key(output, "id")
    @encode.string_value(output, "sql_source")
    @encode.key(output, "inputs")
    @encode.begin_object(output)
    @encode.end_object(output)
    @encode.key(output, "steps")
    @encode.begin_array(output)
    @encode.begin_object(output)
    @encode.key(output, "values")
    @encode.begin_object(output)
    @encode.key(output, "schema")
    @encode.begin_object(output)
    for column in columns {
      @encode.key(output, column.0)
      @encode.begin_object(output)
      @encode.key(output, "type")
      @encode.string_value(output, "number")
      @encode.key(output, "nullable")
      @encode.bool_value(output, false)
      @encode.end_object(output)
    }
    @encode.end_object(output)
    @encode.key(output, "rows")
    @encode.begin_array(output)
    @encode.begin_object(output)
    for column in columns {
      @encode.key(output, column.0)
      @encode.number_value(output, column.1.to_double())
    }
    @encode.end_object(output)
    @encode.end_array(output)
    @encode.end_object(output)
    @encode.key(output, "as")
    @encode.string_value(output, "selected")
    @encode.end_object(output)
    @encode.end_array(output)
    @encode.key(output, "results")
    @encode.begin_object(output)
    @encode.key(output, "rows")
    @encode.begin_object(output)
    @encode.key(output, "from")
    @encode.string_value(output, "selected")
    @encode.key(output, "fields")
    @encode.begin_array(output)
    for column in columns {
      @encode.string_value(output, column.0)
    }
    @encode.end_array(output)
    @encode.end_object(output)
    @encode.end_object(output)
    @encode.end_object(output)
    @encode.end_array(output)
    @encode.key(output, "results")
    @encode.begin_object(output)
    @encode.key(output, "answer")
    @encode.begin_object(output)
    @encode.key(output, "from")
    @encode.begin_object(output)
    @encode.key(output, "stage")
    @encode.string_value(output, "sql_source")
    @encode.key(output, "result")
    @encode.string_value(output, "rows")
    @encode.end_object(output)
    @encode.end_object(output)
    @encode.end_object(output)
    @encode.end_object(output)
    Ok(@encode.finish(output))
  } catch {
    _ => Err(OutputLimit)
  }
}

///|
/// Compile the documented literal SELECT subset to a normal JSON Program.
/// The byte offset in syntax issues refers to the original UTF-8 SQL source.
pub fn compile_literal_select(
  source : String,
  program_id : String,
  limits : LiteralSelectLimits,
) -> Result[LiteralSelectProgram, LiteralSelectIssue] {
  if limits.max_source_bytes < 1 ||
    limits.max_columns < 1 ||
    limits.max_program_bytes < 1 ||
    limits.max_columns > 128 ||
    program_id.is_empty() {
    return Err(InvalidLimits)
  }
  let bytes = @utf8.encode(source)
  if bytes.length() > limits.max_source_bytes {
    return Err(InvalidLimits)
  }
  let tokens = match lex(bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if tokens.length() < 4 || tokens[0].text.to_lower() != "select" {
    return Err(UnsupportedSyntax(0))
  }
  let columns : Array[(String, Int)] = []
  let sources : Array[LiteralColumnSource] = []
  let seen = Map([])
  let mut at = 1
  while at < tokens.length() {
    let number_at = tokens[at].offset
    if !tokens[at].integer {
      return Err(UnsupportedSyntax(number_at))
    }
    let number : Int = @string.from_str(tokens[at].text) catch {
      _ => return Err(InvalidInteger(number_at))
    }
    at += 1
    if at >= tokens.length() || tokens[at].text.to_lower() != "as" {
      return Err(UnsupportedSyntax(number_at))
    }
    at += 1
    if at >= tokens.length() || !identifier(tokens[at].text) {
      return Err(
        UnsupportedSyntax(
          if at < tokens.length() {
            tokens[at].offset
          } else {
            bytes.length()
          },
        ),
      )
    }
    let name = tokens[at].text
    if seen.get(name.to_lower()) is Some(_) {
      return Err(DuplicateColumn(tokens[at].offset))
    }
    seen[name.to_lower()] = true
    columns.push((name, number))
    sources.push({
      name,
      literal_offset: number_at,
      alias_offset: tokens[at].offset,
    })
    if columns.length() > limits.max_columns {
      return Err(InvalidLimits)
    }
    at += 1
    if at == tokens.length() {
      break
    }
    if tokens[at].text == ";" && at + 1 == tokens.length() {
      break
    }
    if tokens[at].text != "," || at + 1 == tokens.length() {
      return Err(UnsupportedSyntax(tokens[at].offset))
    }
    at += 1
  }
  match emit_program(columns, program_id, limits) {
    Ok(document) => Ok({ document, columns: sources, })
    Err(issue) => Err(issue)
  }
}
