///|
extern "js" fn kintone_update_copy_request(
  request : @kintone_catalog.RecordUpdateRequest,
) -> @kintone_catalog.RecordUpdateRequest =
  #| request => ({...request})

///|
test "kintone UPDATE bridge binds the same original request id revision and complete values" {
  let catalog = @kintone_catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\"}}}",
    "12",
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
  let original = @kintone_host.declare_records(
    catalog,
    None,
    ["Subject"],
    "kintone",
    "kintone/0.1",
    "inquiries",
    {
      max_columns: 8,
      max_name_bytes: 128,
      max_nodes: 1000,
      max_depth: 16,
      max_text_bytes: 8192,
    },
    kintone_update_bridge_limits(),
  ).unwrap()
  let mapping = client_program_kintone_prepare_update_mapping(
    original,
    "inquiries",
    [{ target: "Subject", field: "subject", null_behavior: "reject", }],
    "required",
    kintone_update_bridge_limits(),
  ).unwrap()
  let page = @kintone_catalog.project_record_page(
    b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9007199254740994\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"before\"}}],\"totalCount\":null}",
    catalog,
    ["Subject"],
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_rows: 1,
      max_columns: 8,
      max_cells: 8,
      max_table_rows: 16,
    },
  ).unwrap()
  let target = @kintone_catalog.prepare_original_record_target(page, 0, 1000).unwrap()
  let text = @parameter_contract.primitive(
    @parameter_contract.StringType,
    nullable=false,
  )
  let values = @kintone_catalog.prepare_record_write_values(
    catalog,
    [("Subject", @admitted.checked_text_value("after", text).unwrap())],
    {
      max_fields: 16,
      max_name_bytes: 512,
      max_nodes: 1000,
      max_depth: 16,
      max_text_bytes: 8192,
      max_output_bytes: 8192,
    },
  ).unwrap()
  let request = @kintone_catalog.prepare_record_update_request(
    [(target, values)],
    {
      max_records: 1,
      max_identity_bytes: 1000,
      max_comparison_work: 10000,
      max_output_bytes: 8192,
      max_output_nodes: 1000,
      max_output_depth: 16,
    },
  ).unwrap()
  assert_true(
    client_program_kintone_update_mapping_matches_request(mapping, request),
  )
  assert_false(
    client_program_kintone_update_mapping_matches_request(
      mapping,
      kintone_update_copy_request(request),
    ),
  )
  assert_eq(
    client_program_kintone_update_body(request),
    "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"Subject\":{\"value\":\"after\"}},\"revision\":\"9007199254740994\"}],\"upsert\":false}",
  )
}
