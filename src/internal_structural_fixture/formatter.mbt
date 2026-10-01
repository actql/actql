///|
priv enum EmitWork {
  Emit(@decode.Cursor)
  ArrayNext(@decode.Cursor, Int)
  ObjectNext(@decode.Cursor, Int)
}

///|
// Traverse admitted, immutable cursors. No metadata-stripped projection or
// optimizer participates in the structural formatter.
fn emit_body(
  root : @decode.Cursor,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let work = [Emit(root)]
  while work.pop() is Some(task) {
    match task {
      Emit(cursor) =>
        match @decode.view(cursor) {
          NullValue => @encode.null_value(out)
          BoolValue(b) => @encode.bool_value(out, b)
          NumberValue(n) => @encode.number_value(out, n)
          TextValue(s) => @encode.string_value(out, s)
          ArrayValue(_) => {
            @encode.begin_array(out)
            work.push(ArrayNext(cursor, 0))
          }
          ObjectValue(_) => {
            @encode.begin_object(out)
            work.push(ObjectNext(cursor, 0))
          }
        }
      ArrayNext(cursor, i) =>
        match @decode.element_at(cursor, i) {
          Some(child) => {
            work.push(ArrayNext(cursor, i + 1))
            work.push(Emit(child))
          }
          None => @encode.end_array(out)
        }
      ObjectNext(cursor, i) =>
        match @decode.field_at(cursor, i) {
          Some((key, child)) => {
            @encode.key(out, key)
            work.push(ObjectNext(cursor, i + 1))
            work.push(Emit(child))
          }
          None => @encode.end_object(out)
        }
    }
  }
}

///|
priv struct Printer {
  output : StringBuilder
  mut remaining : Int
}

///|
fn Printer::append(
  self : Printer,
  text : String,
) -> Unit raise @encode.EncodeFailure {
  let bytes = match @scalar.admit_utf8_length(text, self.remaining) {
    Ok(n) => n
    Err(_) => raise @encode.OutputLimit
  }
  self.remaining -= bytes
  self.output.write_string(text)
}

///|
fn Printer::quoted(
  self : Printer,
  text : String,
) -> Unit raise @encode.EncodeFailure {
  self.append("'")
  for ch in text.iter() {
    match ch {
      '\'' => self.append("\\'")
      '\\' => self.append("\\\\")
      '\n' => self.append("\\n")
      '\r' => self.append("\\r")
      '\t' => self.append("\\t")
      _ if ch.to_int() < 0x20 => {
        let n = ch.to_int()
        let hex = "0123456789abcdef"
        self.append("\\u00")
        self.append(hex[n / 16:n / 16 + 1].to_owned())
        self.append(hex[n % 16:n % 16 + 1].to_owned())
      }
      _ => self.append(ch.to_string())
    }
  }
  self.append("'")
}

///|
fn Printer::json(
  self : Printer,
  value : @decode.Cursor,
) -> Unit raise @encode.EncodeFailure {
  let out = @encode.writer(self.remaining, self.remaining, self.remaining)
  emit_body(value, out)
  self.append(@encode.finish(out))
}

///|
fn source_field(cursor : @decode.Cursor, key : String) -> @decode.Cursor? {
  match @decode.open_object(cursor) {
    Ok(object) => @decode.lookup(object, key)
    Err(_) => None
  }
}

///|
fn Printer::optional(
  self : Printer,
  cursor : @decode.Cursor,
  key : String,
  label : String,
) -> Unit raise @encode.EncodeFailure {
  if source_field(cursor, key) is Some(value) {
    self.append(label)
    self.json(value)
    self.append(";\n")
  }
}

///|
fn Printer::named(
  self : Printer,
  cursor : @decode.Cursor,
  key : String,
  label : String,
) -> Unit raise @encode.EncodeFailure {
  if source_field(cursor, key) is Some(values) {
    let count = @decode.object_length(values).unwrap()
    for i in 0..<count {
      let (name, value) = @decode.field_at(values, i).unwrap()
      self.append(label)
      self.quoted(name)
      self.append(" = ")
      self.json(value)
      self.append(";\n")
    }
  }
}

///|
/// Format a normally admitted Program without dropping authored structure.
/// The bound covers the complete UTF-8 output, including punctuation/trivia.
pub fn format_fixture(
  program : @syntax.Program,
  max_output_bytes : Int,
) -> Result[String, @encode.EncodeFailure] {
  try {
    if max_output_bytes < 0 || max_output_bytes == 2147483647 {
      raise @encode.OutputLimit
    }
    let printer : Printer = {
      output: StringBuilder(),
      remaining: max_output_bytes,
    }
    let root = @syntax.program_body(program)
    printer.append("AQL '0.1';\nPROGRAM ")
    printer.quoted(@decode.text(source_field(root, "id").unwrap()).unwrap())
    printer.append(" {\n")
    printer.optional(root, "meta", "  META ")
    printer.optional(root, "params", "  PARAMS ")
    printer.optional(root, "bindings", "  BINDINGS ")
    let stages = source_field(root, "stages").unwrap()
    for i in 0..<@decode.array_length(stages).unwrap() {
      let stage = @decode.element_at(stages, i).unwrap()
      printer.append("  STAGE ")
      printer.quoted(@decode.text(source_field(stage, "id").unwrap()).unwrap())
      if source_field(stage, "after") is Some(after) {
        let value = @decode.text(after).unwrap()
        printer.append(
          if value == "accepted" {
            " AFTER ACCEPTED"
          } else {
            " AFTER COMPLETED"
          },
        )
      }
      printer.append(" {\n")
      printer.optional(stage, "meta", "    META ")
      printer.named(stage, "inputs", "    INPUT ")
      if source_field(stage, "from") is Some(from) {
        printer.append("    FROM ")
        printer.quoted(@decode.text(from).unwrap())
        printer.append(";\n")
      }
      let steps = source_field(stage, "steps").unwrap()
      for j in 0..<@decode.array_length(steps).unwrap() {
        printer.append("    STEP ")
        printer.json(@decode.element_at(steps, j).unwrap())
        printer.append(";\n")
      }
      printer.named(stage, "results", "    RESULT ")
      if source_field(stage, "effects") is Some(effects) {
        if @decode.object_length(effects) == Some(0) {
          printer.append("    EFFECTS {};\n")
        } else {
          printer.named(stage, "effects", "    EFFECT ")
        }
      }
      printer.append("  }\n")
    }
    printer.named(root, "results", "  RESULT ")
    printer.append("}\n")
    Ok(printer.output.to_string())
  } catch {
    e => Err(e)
  }
}
