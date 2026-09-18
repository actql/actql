///|
/// Portable owner of the three canonical Result delivery formats. The
/// environment adapter supplies one already bounded canonical row at a time;
/// it never decides field order, scalar spelling, or CSV quoting.
struct ResultDeliverySerializer {
  format : String
  schema : @json.CanonicalValue
  fields : Array[String]
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut state : Int
  mut rows : Int
}

///|
pub(all) enum DeliverySerializationIssue {
  DeliverySerializationUnsupportedFormat(String)
  DeliverySerializationInvalidLimits
  DeliverySerializationInvalidSchema
  DeliverySerializationInvalidFields
  DeliverySerializationInvalidRow
  DeliverySerializationTypeMismatch(String)
  DeliverySerializationNul
  DeliverySerializationOutputLimit
  DeliverySerializationClosed
} derive(Eq, Debug)

///|
fn delivery_output(
  text : String,
  max_wire_bytes : Int,
) -> Result[String, DeliverySerializationIssue] {
  if @utf8.encode(text).length() > max_wire_bytes {
    Err(DeliverySerializationOutputLimit)
  } else {
    Ok(text)
  }
}

///|
fn delivery_value_has_nul(value : @json.CanonicalValue) -> Bool {
  match value {
    @json.String(text) => text.contains("\u{0}")
    @json.Array(items) => @json.array_values(items).any(delivery_value_has_nul)
    @json.Object(_) =>
      @json.object_fields(value)
      .unwrap()
      .any(entry => entry.0.contains("\u{0}") || delivery_value_has_nul(entry.1))
    _ => false
  }
}

///|
fn delivery_schema_type(
  schema : @json.CanonicalValue,
  field : String,
) -> (String, Bool)? {
  guard @json.object_field(schema, field) is Some(contract) else { return None }
  guard optional_string(@json.object_field(contract, "type")) is Some(kind) else {
    return None
  }
  guard @json.object_field(contract, "nullable") is Some(@json.Bool(nullable)) else {
    return None
  }
  Some((kind, nullable))
}

///|
fn csv_quote(text : String) -> Result[String, DeliverySerializationIssue] {
  if text.contains("\u{0}") {
    return Err(DeliverySerializationNul)
  }
  let output = StringBuilder(size_hint=text.length() + 2)
  output.write_char('"')
  for character in text {
    if character == '"' {
      output.write_char('"')
    }
    output.write_char(character)
  }
  output.write_char('"')
  Ok(output.to_string())
}

///|
fn canonical_delivery_value(
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, DeliverySerializationIssue] {
  if delivery_value_has_nul(value) {
    return Err(DeliverySerializationNul)
  }
  Ok(@json.stringify_value(value, max_wire_bytes, max_nodes, max_depth)) catch {
    _ => Err(DeliverySerializationOutputLimit)
  }
}

///|
fn csv_delivery_value(
  value : @json.CanonicalValue,
  kind : String,
  nullable : Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, DeliverySerializationIssue] {
  if value is @json.Null {
    if nullable {
      return Ok("\\N")
    }
    return Err(DeliverySerializationTypeMismatch(kind))
  }
  match kind {
    "string" | "timestamp" | "date" =>
      match value {
        @json.String(text) => csv_quote(text)
        _ => Err(DeliverySerializationTypeMismatch(kind))
      }
    "number" =>
      match value {
        @json.Number(_) =>
          canonical_delivery_value(value, max_wire_bytes, max_nodes, max_depth)
        _ => Err(DeliverySerializationTypeMismatch(kind))
      }
    "decimal" =>
      match value {
        @json.String(text) =>
          if text.contains("\u{0}") {
            Err(DeliverySerializationNul)
          } else {
            Ok(text)
          }
        _ => Err(DeliverySerializationTypeMismatch(kind))
      }
    "boolean" =>
      match value {
        @json.Bool(flag) => Ok(if flag { "true" } else { "false" })
        _ => Err(DeliverySerializationTypeMismatch(kind))
      }
    "array" | "object" | "vector" | "json" | "resource_ref" | "artifact_ref" => {
      let text = match
        canonical_delivery_value(value, max_wire_bytes, max_nodes, max_depth) {
        Ok(text) => text
        Err(issue) => return Err(issue)
      }
      csv_quote(text)
    }
    _ => Err(DeliverySerializationTypeMismatch(kind))
  }
}

///|
fn validate_delivery_fields(
  schema : @json.CanonicalValue,
  fields : Array[String],
) -> Bool {
  guard @json.object_fields(schema) is Some(schema_fields) else { return false }
  if schema_fields.length() != fields.length() {
    return false
  }
  let seen : Map[String, Unit] = Map([])
  for field in fields {
    if field.is_empty() ||
      field.contains("\u{0}") ||
      seen.contains(field) ||
      delivery_schema_type(schema, field) is None {
      return false
    }
    seen[field] = ()
  }
  true
}

///|
pub fn prepare_result_delivery_serializer(
  format : String,
  schema_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResultDeliverySerializer, DeliverySerializationIssue] {
  if !["json", "jsonl", "csv"].contains(format) {
    return Err(DeliverySerializationUnsupportedFormat(format))
  }
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(DeliverySerializationInvalidLimits)
  }
  let schema = match
    parse_contract_wire(schema_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(DeliverySerializationInvalidSchema)
  }
  if !validate_delivery_fields(schema, fields) {
    return Err(DeliverySerializationInvalidFields)
  }
  Ok({
    format,
    schema,
    fields: fields.copy(),
    max_wire_bytes,
    max_nodes,
    max_depth,
    state: 0,
    rows: 0,
  })
}

///|
pub fn begin_result_delivery(
  serializer : ResultDeliverySerializer,
) -> Result[String, DeliverySerializationIssue] {
  if serializer.state != 0 {
    return Err(DeliverySerializationClosed)
  }
  serializer.state = 1
  let text = match serializer.format {
    "json" => "["
    "jsonl" => ""
    _ => {
      let output = StringBuilder()
      for index, field in serializer.fields {
        if index > 0 {
          output.write_char(',')
        }
        let quoted = match csv_quote(field) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        output.write_string(quoted)
      }
      output.write_char('\n')
      output.to_string()
    }
  }
  delivery_output(text, serializer.max_wire_bytes)
}

///|
fn exact_delivery_row(
  serializer : ResultDeliverySerializer,
  row_wire : String,
) -> Result[@json.CanonicalValue, DeliverySerializationIssue] {
  let row = match
    parse_contract_wire(
      row_wire,
      serializer.max_wire_bytes,
      serializer.max_nodes,
      serializer.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(DeliverySerializationInvalidRow)
  }
  guard @json.object_fields(row) is Some(row_fields) else {
    return Err(DeliverySerializationInvalidRow)
  }
  if row_fields.length() != serializer.fields.length() {
    return Err(DeliverySerializationInvalidRow)
  }
  for field in serializer.fields {
    if @json.object_field(row, field) is None {
      return Err(DeliverySerializationInvalidRow)
    }
  }
  Ok(row)
}

///|
fn ordered_json_delivery_row(
  serializer : ResultDeliverySerializer,
  row : @json.CanonicalValue,
) -> Result[String, DeliverySerializationIssue] {
  let writer = @encode.writer(
    serializer.max_wire_bytes,
    serializer.max_nodes,
    serializer.max_depth,
  ) catch {
    _ => return Err(DeliverySerializationOutputLimit)
  }
  try {
    @encode.begin_object(writer)
    for field in serializer.fields {
      @encode.key(writer, field)
      @json.emit_value(@json.object_field(row, field).unwrap(), writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(DeliverySerializationOutputLimit)
  }
}

///|
fn csv_delivery_row(
  serializer : ResultDeliverySerializer,
  row : @json.CanonicalValue,
) -> Result[String, DeliverySerializationIssue] {
  let output = StringBuilder()
  for index, field in serializer.fields {
    if index > 0 {
      output.write_char(',')
    }
    guard delivery_schema_type(serializer.schema, field)
      is Some((kind, nullable)) else {
      return Err(DeliverySerializationInvalidSchema)
    }
    let cell = match
      csv_delivery_value(
        @json.object_field(row, field).unwrap(),
        kind,
        nullable,
        serializer.max_wire_bytes,
        serializer.max_nodes,
        serializer.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    output.write_string(cell)
  }
  output.write_char('\n')
  delivery_output(output.to_string(), serializer.max_wire_bytes)
}

///|
pub fn next_result_delivery_row(
  serializer : ResultDeliverySerializer,
  row_wire : String,
) -> Result[String, DeliverySerializationIssue] {
  if serializer.state != 1 {
    return Err(DeliverySerializationClosed)
  }
  let row = match exact_delivery_row(serializer, row_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = if serializer.format == "csv" {
    match csv_delivery_row(serializer, row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  } else {
    let text = match ordered_json_delivery_row(serializer, row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match serializer.format {
      "json" => if serializer.rows == 0 { text } else { "," + text }
      _ => text + "\n"
    }
  }
  serializer.rows += 1
  delivery_output(output, serializer.max_wire_bytes)
}

///|
pub fn finish_result_delivery(
  serializer : ResultDeliverySerializer,
) -> Result[String, DeliverySerializationIssue] {
  if serializer.state != 1 {
    return Err(DeliverySerializationClosed)
  }
  serializer.state = 2
  Ok(if serializer.format == "json" { "]" } else { "" })
}
