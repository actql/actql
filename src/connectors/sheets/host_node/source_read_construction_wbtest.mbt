///|
test "Sheets standard Source request constructor composes through same Core reader without an HTTP grant" {
  let schema = "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false}]"
  let native = sheets_grid_read_construction_capacity(
    @utf8.encode(schema).length(),
    1,
    7,
    0,
    2,
    0,
    1,
  )
  assert_true(native is Some(_))
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let original = @client_host.installed_json_source_reader_capacity(
    limits, 1, 3,
  ).unwrap()
  let combined = @client_host.installed_json_source_reader_capacity_with_request(
    limits, 1, 3, native,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(combined) >
    @execution.execution_capacity_retained_bytes(original),
  )
  let output = sheets_grid_request_json(
    schema, 7, 0, 2, 0, 1, 4096, 100, 12, 100,
  )
  assert_eq(
    @json.parse(output),
    (
      {
        "body": "{\"dataFilters\":[{\"gridRange\":{\"sheetId\":7,\"startRowIndex\":0,\"endRowIndex\":2,\"startColumnIndex\":0,\"endColumnIndex\":1}}],\"includeGridData\":true}",
      } : Json),
  )
  assert_true(
    sheets_grid_read_construction_capacity(1, 0, 0, 0, 1, 0, 1) is None,
  )
  assert_true(
    sheets_grid_read_construction_capacity(1, 65, 0, 0, 1, 0, 1) is None,
  )
}
