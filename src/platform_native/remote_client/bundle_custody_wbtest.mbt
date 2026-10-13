// Independent wire fixtures; status/response admission only, no HTTP execution.

///|
fn custody_vector_retain_request_body() -> String {
  "{\"binding\":\"{\\\"attempt_id\\\":\\\"hold-a\\\",\\\"authority_scope_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"catalog_incarnation\\\":\\\"123e4567-e89b-42d3-a456-426614174000\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"distribution_cid\\\":\\\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\\\",\\\"environment\\\":\\\"production\\\",\\\"initial_revision\\\":11,\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"set_revision_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"site_generation\\\":7,\\\"site_key\\\":\\\"site-a\\\",\\\"version\\\":\\\"actql-remote-runtime-bundle-hold-binding/0.1\\\",\\\"workspace_id\\\":\\\"workspace-a\\\"}\",\"binding_cid\":\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\",\"distribution\":\"{\\\"runtime_bundle_cids\\\":[\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"],\\\"version\\\":\\\"actql-remote-runtime-bundle-distribution/0.1\\\"}\",\"distribution_cid\":\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\",\"operation\":\"retain\",\"version\":\"actql-remote-runtime-bundle-custody-request/0.1\"}"
}

///|
fn custody_vector_retain_request_cid() -> String {
  "sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d"
}

///|
fn custody_vector_retained_response_body() -> String {
  "{\"binding_cid\":\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\",\"catalog_incarnation\":\"123e4567-e89b-42d3-a456-426614174000\",\"kind\":\"observation\",\"observation\":\"retained\",\"record_revision\":12,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"version\":\"actql-remote-runtime-bundle-custody-response/0.1\"}"
}

///|
fn custody_vector_retained_response_cid() -> String {
  "sha256:d50f438c17a0696073915837428e680a60807904d37a0d4719d4bda388df2cf3"
}

///|
test "Bundle transport distinguishes checked ACK obsolete and generic HTTP outcomes" {
  let request = @bundle.admit_bundle_custody_request_json(
    custody_vector_retain_request_body(),
    custody_vector_retain_request_cid(),
  ).unwrap()
  let response = @bundle.admit_bundle_custody_response_json(
    request,
    custody_vector_retained_response_body(),
    custody_vector_retained_response_cid(),
  ).unwrap()
  let delivery = @remote.admit_remote_poll_bundle_custody_json(
    @remote.remote_poll_bundle_custody_json(request, 37L).unwrap(),
  ).unwrap()
  let ack = @remote.remote_bundle_custody_observation_ack_json(
    request, response, 37L,
  ).unwrap()
  let obsolete = @remote.remote_bundle_custody_observation_obsolete_json(
    request, response, 37L,
  ).unwrap()
  assert_true(
    admit_bundle_custody_report_reply(200, ack, delivery, response)
    is Ok(Accepted),
  )
  assert_true(
    admit_bundle_custody_report_reply(409, obsolete, delivery, response)
    is Ok(Obsolete),
  )
  assert_true(
    admit_bundle_custody_report_reply(200, obsolete, delivery, response)
    is Err(_),
  )
  assert_true(
    admit_bundle_custody_report_reply(409, ack, delivery, response) is Err(_),
  )
  assert_true(
    admit_bundle_custody_report_reply(200, "{}", delivery, response) is Err(_),
  )
  assert_true(
    admit_bundle_custody_report_reply(409, "{}", delivery, response) is Err(_),
  )
  assert_true(
    admit_bundle_custody_report_reply(503, ack, delivery, response) is Err(_),
  )
  let old = @remote.remote_bundle_custody_observation_obsolete_json(
    request, response, 36L,
  ).unwrap()
  assert_true(
    admit_bundle_custody_report_reply(409, old, delivery, response) is Err(_),
  )
}
