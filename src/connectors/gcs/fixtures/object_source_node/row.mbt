// Test-only actual Value admission with the exact installed carrier schema.
// No reference issuer, Source completion, read grant or replacement RowRun.

///|
fn cursor(wire : String) -> Result[@decode.Cursor, String] {
  let parsed = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 32768,
      max_nodes: 4096,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return Err("FixtureObjectDataParse")
  }
  @decode.admit(parsed, {
    max_nodes: 4096,
    max_depth: 64,
    max_string_bytes: 32768,
    max_total_string_bytes: 32768,
  }).map_err(_ => "FixtureObjectDataDecode")
}

///|
#export_name("fixtureGcsObjectDataWire")
pub fn fixture_gcs_object_data_wire(
  schema_wire : String,
  row_wire : String,
) -> Result[String, String] {
  let schema = match cursor(schema_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (schema, _) = match
    @environment.read_relation_schema_fields(schema, 32768, 4096, 64, 100000) {
    Ok(value) => value
    Err(_) => return Err("FixtureObjectSchema")
  }
  let row = match cursor(row_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(row) is Ok(row) else {
    return Err("FixtureObjectRow")
  }
  let values = []
  for name in ["size", "generation", "metageneration", "metadata"] {
    let mut selected = None
    for index in 0..<@schema.field_count(schema) {
      let field = @schema.field_at(schema, index).unwrap()
      if @schema.field_reference_name(field) == name {
        selected = Some(field.contract)
      }
    }
    guard selected is Some(contract) && @decode.lookup(row, name) is Some(cell) else {
      return Err("FixtureObjectField")
    }
    let checked = match
      @admitted.admit(contract, cell, {
        max_nodes: 4096,
        max_depth: 64,
        max_text_bytes: 32768,
      }) {
      Ok(value) => value
      Err(_) => return Err("FixtureObjectValue")
    }
    if name == "metadata" {
      match checked.value {
        JsonData(_) | Null => ()
        _ => return Err("FixtureObjectWrongCarrier")
      }
    } else {
      guard checked.value is Signed64(_) else {
        return Err("FixtureObjectWrongCarrier")
      }
    }
    values.push(checked)
  }
  try {
    let output = @encode.writer(32768, 4096, 64)
    @encode.begin_array(output)
    for value in values {
      @admitted.emit_checked_wire_value(value, output)
    }
    @encode.end_array(output)
    Ok(@encode.finish(output))
  } catch {
    _ => Err("FixtureObjectWire")
  }
}
