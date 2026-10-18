///|
test "DELETE original request and acknowledgement reject shallow copies without changing exact wire" {
  let catalog = record_test_catalog()
  let page = mutation_page(catalog, [
    mutation_row("9007199254740993", revision="9007199254740994"),
  ])
  let target = prepare_original_record_target(page, 0, 1000).unwrap()
  let request = prepare_record_delete_request([target], mutation_limits()).unwrap()
  let response = project_record_delete_acknowledgement(
    request, 200, b"{}", 8192, 1000, 16,
  ).unwrap()
  let copied_request : RecordDeleteRequest = { ..request, }
  let copied_response : RecordDeleteAcknowledgement = { ..response, }
  assert_true(record_delete_request_is_original(request))
  assert_false(record_delete_request_is_original(copied_request))
  assert_true(record_delete_acknowledgement_is_original(response))
  assert_false(record_delete_acknowledgement_is_original(copied_response))
  assert_eq(
    record_delete_request_body(request),
    "{\"app\":\"12\",\"ids\":[\"9007199254740993\"],\"revisions\":[\"9007199254740994\"]}",
  )
}
