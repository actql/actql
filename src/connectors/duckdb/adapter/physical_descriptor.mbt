///|
/// Decode the private Node transport descriptor, not a shared wire contract.
/// In particular, naive timestamps stay distinguishable and cannot acquire a
/// timezone by passing through the descriptor decoder.
pub fn decode_physical_type(
  cursor : @decode.Cursor,
) -> Result[PhysicalType, ValueIssue] {
  let object = match @decode.open_object(cursor) {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let id_cursor = match @decode.required(object, "id") {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let id = match @decode.text(id_cursor) {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let fields = if id == "DECIMAL" {
    ["id", "precision", "scale"]
  } else {
    ["id"]
  }
  match @decode.closed_object(cursor, fields) {
    Ok(_) => ()
    Err(issue) => return Err(Decode(issue))
  }
  let physical = match id {
    "BOOLEAN" => Boolean
    "VARCHAR" => Varchar
    "TINYINT" => Integer(bits=8, signed=true)
    "SMALLINT" => Integer(bits=16, signed=true)
    "INTEGER" => Integer(bits=32, signed=true)
    "BIGINT" => Integer(bits=64, signed=true)
    "HUGEINT" => Integer(bits=128, signed=true)
    "UTINYINT" => Integer(bits=8, signed=false)
    "USMALLINT" => Integer(bits=16, signed=false)
    "UINTEGER" => Integer(bits=32, signed=false)
    "UBIGINT" => Integer(bits=64, signed=false)
    "UHUGEINT" => Integer(bits=128, signed=false)
    "FLOAT" => Float32
    "DOUBLE" => Float64
    "DATE" => Date
    "TIMESTAMP_TZ" => TimestampTZ
    "TIMESTAMP" | "TIMESTAMP_S" | "TIMESTAMP_MS" | "TIMESTAMP_NS" =>
      NaiveTimestamp
    "DECIMAL" => {
      let precision = match @decode.required(object, "precision") {
        Ok(value) =>
          match @decode.int32(value) {
            Ok(value) => value
            Err(issue) => return Err(Decode(issue))
          }
        Err(issue) => return Err(Decode(issue))
      }
      let scale = match @decode.required(object, "scale") {
        Ok(value) =>
          match @decode.int32(value) {
            Ok(value) => value
            Err(issue) => return Err(Decode(issue))
          }
        Err(issue) => return Err(Decode(issue))
      }
      if precision < 1 || precision > 38 || scale < 0 || scale > precision {
        return Err(InvalidPhysicalValue)
      }
      Decimal(precision~, scale~)
    }
    _ => return Err(UnsupportedType)
  }
  Ok(physical)
}

///|
pub(all) enum PhysicalFieldsIssue {
  Transport(TransportColumnIssue)
  InvalidFields
  Descriptor(ValueIssue)
} derive(Eq, Debug)

///|
/// Decode connector-private result metadata. This is physical type matching,
/// not logical value admission or execution evidence. Node and native Hosts
/// use this one Connector-owned implementation.
pub fn decode_physical_fields(
  text : String,
  limits : TransportColumnLimits,
) -> Result[Array[(String, PhysicalType)], PhysicalFieldsIssue] {
  let records = match
    decode_transport_columns(text, { ..limits, max_rows: 4, }) {
    Ok(value) => value
    Err(issue) => return Err(Transport(issue))
  }
  let output = []
  for record in records {
    if @decode.array_length(record) != Some(4) {
      return Err(InvalidFields)
    }
    let name = match @decode.text(@decode.element_at(record, 0).unwrap()) {
      Ok(value) => value
      Err(_) => return Err(InvalidFields)
    }
    let id = match @decode.text(@decode.element_at(record, 1).unwrap()) {
      Ok(value) => value
      Err(_) => return Err(InvalidFields)
    }
    let span = @decode.cursor_span(record)
    let members : Array[@source.Field] = [
      { key: "id", key_span: span, value: { value: String(id), span, }, },
    ]
    for (index, key) in [(2, "precision"), (3, "scale")] {
      let cell = @decode.element_at(record, index).unwrap()
      if @decode.is_null(cell) {
        continue
      }
      let digits = match @decode.text(cell) {
        Ok(value) => value
        Err(_) => return Err(InvalidFields)
      }
      if digits.length() == 0 || digits.length() > 2 {
        return Err(InvalidFields)
      }
      let mut number = 0
      for c in digits.iter() {
        if c < '0' || c > '9' {
          return Err(InvalidFields)
        }
        number = number * 10 + c.to_int() - 48
      }
      members.push({
        key,
        key_span: span,
        value: { value: Number(number.to_double()), span, },
      })
    }
    let descriptor = match
      @decode.admit({ value: Object(members), span, }, {
        max_nodes: 8,
        max_depth: 2,
        max_string_bytes: limits.max_text_bytes,
        max_total_string_bytes: limits.max_text_bytes,
      }) {
      Ok(value) => value
      Err(_) => return Err(InvalidFields)
    }
    let physical = match decode_physical_type(descriptor) {
      Ok(value) => value
      Err(issue) => return Err(Descriptor(issue))
    }
    output.push((name, physical))
  }
  Ok(output)
}
