///|
/// Physical per-row parsing limits. Cumulative value/identity/row budgets remain
/// owned by CompletedOutputImport; these limits cannot reset those budgets.
pub(all) struct RetainedRowDecodeLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) enum RetainedRowDecodeIssue {
  InvalidLimits
  InputLimit
  ShapeLimit
  InvalidJson
  InvalidShape
  Decode(@decode.Issue)
  Value(Int, @admitted.Issue)
}

///|
/// Failure while decoding one retained row directly into provisional admitted
/// output. This operation grants no completion or execution authority.
pub(all) enum AdmittedOutputWireIssue {
  Wire(RetainedRowDecodeIssue)
  Admission(CaptureIssue)
}

///|
fn preflight_retained_row(
  text : String,
  limits : RetainedRowDecodeLimits,
) -> Bool {
  let stack : Array[(Char, Bool)] = []
  let mut quoted = false
  let mut escaped = false
  let mut literal = false
  let mut nodes = 0
  for char in text.iter() {
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
    let mut node = false
    match char {
      '{' | '[' => {
        if stack.length() > limits.max_depth {
          return false
        }
        stack.push((char, char == '{'))
        node = true
        literal = false
      }
      '}' | ']' => {
        guard stack.pop() is Some((opening, _)) &&
          ((opening == '{' && char == '}') || (opening == '[' && char == ']')) else {
          return false
        }
        literal = false
      }
      ':' => {
        if stack.length() == 0 {
          return false
        }
        let (opening, _) = stack[stack.length() - 1]
        stack[stack.length() - 1] = (opening, false)
        literal = false
      }
      ',' => {
        if stack.length() == 0 {
          return false
        }
        let (opening, _) = stack[stack.length() - 1]
        stack[stack.length() - 1] = (opening, opening == '{')
        literal = false
      }
      '"' => {
        quoted = true
        node = !(stack.last() is Some(('{', true)))
        literal = false
      }
      ' ' | '\t' | '\n' | '\r' => literal = false
      _ =>
        if !literal {
          node = true
          literal = true
        }
    }
    if node {
      if nodes >= limits.max_nodes {
        return false
      }
      nodes += 1
    }
  }
  !quoted && stack.is_empty()
}

///|
fn decode_retained_row(
  schema : @schema.Schema,
  text : String,
  limits : RetainedRowDecodeLimits,
  reference_cells? : Array[Array[@admitted.ReferenceValue]],
) -> Result[Array[@admitted.CheckedValue], RetainedRowDecodeIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 ||
    limits.max_depth > 64 {
    return Err(InvalidLimits)
  }
  let bytes = match @scalar.admit_utf8_length(text, limits.max_bytes) {
    Ok(bytes) => bytes
    Err(_) => return Err(InputLimit)
  }
  if !preflight_retained_row(text, limits) {
    return Err(ShapeLimit)
  }
  let parsed = @json.parse(text) catch { _ => return Err(InvalidJson) }
  let span : @source.Span = {
    start_byte: 0,
    end_byte: bytes,
    start_line: 1,
    end_line: 1,
    start_column: 1,
    end_column: 1,
    source_path: "<retained-row>",
  }
  let cursor = match
    @decode.admit_raw_json(parsed, span, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_text_bytes,
      max_total_string_bytes: limits.max_text_bytes,
    }) {
    Ok(cursor) => cursor
    Err(issue) => return Err(Decode(issue))
  }
  let width = @schema.field_count(schema)
  if width > limits.max_nodes ||
    @decode.object_length(cursor) != Some(width) ||
    (reference_cells is Some(cells) && cells.length() != width) {
    return Err(InvalidShape)
  }
  let names = Array::makei(width, column => {
    @schema.reference_name(@schema.field_at(schema, column).unwrap().name)
  })
  let object = match @decode.closed_object(cursor, names) {
    Ok(object) => object
    Err(issue) => return Err(Decode(issue))
  }
  let values = []
  for column in 0..<width {
    // required() rejects explicit null; field presence and nullable admission
    // are separate obligations for retained typed rows.
    let cell = match @decode.lookup(object, names[column]) {
      Some(cell) => cell
      None => return Err(InvalidShape)
    }
    let contract = @schema.field_at(schema, column).unwrap().contract
    let used = Ref(0)
    let references = match reference_cells {
      Some(cells) => cells[column]
      None => []
    }
    let admitted = match reference_cells {
      Some(_) => {
        let issuer = @admitted.bind_reference_reissuer((required, wire) => {
          guard references.get(used.val) is Some(reference) &&
            @admitted.reference_wire(reference) == wire &&
            @admitted.reference_compatible(reference, required) else {
            return None
          }
          used.val += 1
          Some(reference)
        })
        @admitted.admit_host(
          issuer,
          contract,
          cell,
          {
            max_nodes: limits.max_nodes,
            max_text_bytes: limits.max_text_bytes,
            max_depth: limits.max_depth,
          },
          {
            max_bytes: limits.max_bytes,
            max_nodes: limits.max_nodes,
            max_depth: limits.max_depth,
            max_text_units: limits.max_text_bytes,
          },
        )
      }
      None =>
        @admitted.admit(contract, cell, {
          max_nodes: limits.max_nodes,
          max_text_bytes: limits.max_text_bytes,
          max_depth: limits.max_depth,
        })
    }
    match admitted {
      Ok(value) => {
        if used.val != references.length() {
          return Err(
            Value(
              column,
              @admitted.ValueIssue(
                @admitted.InvalidReference,
                path=@decode.cursor_path(cell),
                span=@decode.cursor_span(cell),
              ),
            ),
          )
        }
        values.push(value)
      }
      Err(issue) => return Err(Value(column, issue))
    }
  }
  Ok(values)
}

///|
/// Decode one bounded canonical row against the exact checked output schema.
/// Provider code must still establish completion through its registered
/// evidence verifier after every row and physical integrity check succeeds.
pub fn append_admitted_output_wire(
  output : AdmittedOutput,
  text : String,
  limits : RetainedRowDecodeLimits,
) -> Result[Unit, AdmittedOutputWireIssue] {
  if !output.buffer.open || output.buffer.reading {
    return Err(Admission(ClosedCapture))
  }
  let values = match decode_retained_row(output.buffer.schema, text, limits) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Wire(issue))
    }
  }
  match append_admitted_output(output, values) {
    Ok(_) => Ok(())
    Err(issue) => Err(Admission(issue))
  }
}

///|
pub fn append_completed_output_import_wire(
  value : CompletedOutputImport,
  text : String,
  limits : RetainedRowDecodeLimits,
) -> Result[Unit, CompletedImportIssue] {
  if !value.open || value.reading {
    return Err(Closed)
  }
  if !completed_output_available(value.source) {
    cancel_completed_output_import(value) |> ignore
    return Err(Unavailable)
  }
  let schema = value.source.representation.unwrap().receipt.schema
  match decode_retained_row(schema, text, limits) {
    Ok(values) => append_completed_output_import(value, values)
    Err(issue) => {
      cancel_completed_output_import(value) |> ignore
      Err(WireRow(issue))
    }
  }
}
