///|
test "raw JSON and flat columns retain the same original scalar dimensions without source conversion" {
  let span : @span.Span = {
    start_byte: 0,
    end_byte: 0,
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 1,
    source_path: "<original-dimensions>",
  }
  let limits : Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }
  let value = @json.parse(
    "{\"é\":\"" + "🙂".repeat(40) + "\",\"rows\":[1,\"x\"]}",
  )
  let root = admit_raw_json(value, span, limits).unwrap()
  assert_eq(admission_preparation_data(root), {
    fields: 2,
    texts: 2,
    max_key_utf16: 4,
    total_utf16: 86L,
  })
  let values : Array[Json] = [
    Json::string("é"),
    Json::null(),
    Json::string("🙂"),
  ]
  let flat = admit_raw_scalar_column(values, span, limits).unwrap()
  let generic = admit_raw_json(Json::array(values), span, limits).unwrap()
  assert_eq(admission_preparation_data(flat), {
    fields: 0,
    texts: 2,
    max_key_utf16: 0,
    total_utf16: 3L,
  })
  assert_eq(
    admission_preparation_data(flat),
    admission_preparation_data(generic),
  )
}
