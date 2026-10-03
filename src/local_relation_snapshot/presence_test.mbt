///|
test "snapshot retains column presence separately from nullable value contracts" {
  let body =
    #|{"column_presence":{"p":"conditional"},"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"p":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"source_ref":"source:local/s/rows","version":"actql-local-input-schema/0.1"}
  let bytes = @utf8.encode(body)
  let snapshot = read(bytes, "sha256:" + @sha.hex(bytes), caps()).unwrap()
  let schema = schema(snapshot)
  assert_eq(@schema.lookup_reference(schema, "id").unwrap().presence, Required)
  let p = @schema.lookup_reference(schema, "p").unwrap()
  assert_eq(p.presence, Conditional)
  assert_true(p.contract.nullable)
  assert_true(@schema.as_object(schema) is None)
  let writer = @encode.writer(10000, 1000, 100)
  emit(snapshot, writer)
  assert_eq(@encode.finish(writer), body)
  let projection = @encode.writer(10000, 1000, 100)
  emit_type_projection(snapshot, projection)
  assert_eq(@encode.finish(projection), body)
  let rebuilt = @encode.writer(10000, 1000, 100)
  emit_schema_type_projection(source_reference(snapshot), schema, rebuilt)
  assert_eq(@encode.finish(rebuilt), body)
}

///|
test "snapshot refuses unknown presence columns and noncanonical metadata" {
  for
    presence in [
      "{}", "{\"unknown\":\"conditional\"}", "{\"p\":\"required\"}", "{\"p\":null}",
    ] {
    let body = "{\"column_presence\":" +
      presence +
      ",\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"p\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/s/rows\",\"version\":\"actql-local-input-schema/0.1\"}"
    let bytes = @utf8.encode(body)
    assert_true(
      read(bytes, "sha256:" + @sha.hex(bytes), caps()) is Err(InvalidSnapshot),
    )
  }
}
