///|
/// Test-only checked owner for the physical Site HTTP conformance test.
/// Product callers must supply their own checked output owner.
#export_name("salesforceSiteTestOutputValues")
pub fn salesforce_site_test_output_values() -> @execution.ManagedOutputValues {
  let parsed = @source.parse_json(
    "[{\"values\":{\"schema\":{\"Id\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"Id\"]}]",
    { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  let pipeline = @pipeline.check(cursor, [], None, None, {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 20,
  }).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  @execution.prepare_managed_output_values(
    owner,
    Step(1),
    3,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    { max_work: 100, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
}

///|
#export_name("salesforceSiteTestReceiptRows")
pub fn salesforce_site_test_receipt_rows(
  receipt : @execution.ManagedOutputValueReceipt,
) -> Int {
  @execution.managed_output_value_row_count(receipt)
}
