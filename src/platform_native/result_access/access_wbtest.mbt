///|
fn access_test_cid(character : String) -> String {
  "sha256:" + character.repeat(64)
}

///|
test "native Result access validates the complete request before effects" {
  let request : NativeResultAccessRequest = {
    namespace_id: "namespace_id",
    authority_scope_cid: access_test_cid("a"),
    run_definition_cid: access_test_cid("b"),
    principal_id: "principal",
    purpose: "download",
    result_name: "answer",
    format: "jsonl",
    attempt_id: "attempt",
  }
  assert_true(valid_request(request))
  assert_false(valid_request({ ..request, format: "other", }))
  assert_false(valid_request({ ..request, authority_scope_cid: "not-a-cid", }))
  assert_false(valid_request({ ..request, attempt_id: "", }))
}
