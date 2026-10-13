// Independent common vectors are retained from remote_bundle/retention_wire_wbtest.
// Wrapper literals are encoded independently with Python json, not product output.

///|
fn custody_vector_context_request_body() -> String {
  "{\"distribution\":\"{\\\"runtime_bundle_cids\\\":[\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"],\\\"version\\\":\\\"actql-remote-runtime-bundle-distribution/0.1\\\"}\",\"distribution_cid\":\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\",\"operation\":\"query\",\"scope\":\"{\\\"attempt_id\\\":\\\"hold-a\\\",\\\"authority_scope_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"distribution_cid\\\":\\\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\\\",\\\"environment\\\":\\\"production\\\",\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"set_revision_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"site_generation\\\":7,\\\"site_key\\\":\\\"site-a\\\",\\\"version\\\":\\\"actql-remote-runtime-bundle-hold-scope/0.1\\\",\\\"workspace_id\\\":\\\"workspace-a\\\"}\",\"scope_cid\":\"sha256:a47fd39adfd002964881687963b875b86549365ebea8c4d89a82f2948e02f3c3\",\"version\":\"actql-remote-runtime-bundle-custody-request/0.1\"}"
}

///|
fn custody_vector_context_request_cid() -> String {
  "sha256:a712ca85e73d44f13bf30d46a3cb43da0f020438b005f5cf445bd9be8d2ee3f6"
}

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
fn custody_poll_vector() -> String {
  "{\"delivery_revision\":37,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"request_json\":\"{\\\"binding\\\":\\\"{\\\\\\\"attempt_id\\\\\\\":\\\\\\\"hold-a\\\\\\\",\\\\\\\"authority_scope_cid\\\\\\\":\\\\\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\\\\\",\\\\\\\"catalog_incarnation\\\\\\\":\\\\\\\"123e4567-e89b-42d3-a456-426614174000\\\\\\\",\\\\\\\"coordinator_authority\\\\\\\":\\\\\\\"coordinator-a\\\\\\\",\\\\\\\"distribution_cid\\\\\\\":\\\\\\\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\\\\\\\",\\\\\\\"environment\\\\\\\":\\\\\\\"production\\\\\\\",\\\\\\\"initial_revision\\\\\\\":11,\\\\\\\"runtime_bundle_cid\\\\\\\":\\\\\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\\\\\",\\\\\\\"set_revision_cid\\\\\\\":\\\\\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\\\\\",\\\\\\\"site_generation\\\\\\\":7,\\\\\\\"site_key\\\\\\\":\\\\\\\"site-a\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-remote-runtime-bundle-hold-binding/0.1\\\\\\\",\\\\\\\"workspace_id\\\\\\\":\\\\\\\"workspace-a\\\\\\\"}\\\",\\\"binding_cid\\\":\\\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\\\",\\\"distribution\\\":\\\"{\\\\\\\"runtime_bundle_cids\\\\\\\":[\\\\\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\\\\\",\\\\\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\\\\\"],\\\\\\\"version\\\\\\\":\\\\\\\"actql-remote-runtime-bundle-distribution/0.1\\\\\\\"}\\\",\\\"distribution_cid\\\":\\\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\\\",\\\"operation\\\":\\\"retain\\\",\\\"version\\\":\\\"actql-remote-runtime-bundle-custody-request/0.1\\\"}\",\"version\":\"actql-remote-poll-bundle-custody/0.1\"}"
}

///|
fn custody_observation_vector() -> String {
  "{\"delivery_revision\":37,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"response_cid\":\"sha256:d50f438c17a0696073915837428e680a60807904d37a0d4719d4bda388df2cf3\",\"response_json\":\"{\\\"binding_cid\\\":\\\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\\\",\\\"catalog_incarnation\\\":\\\"123e4567-e89b-42d3-a456-426614174000\\\",\\\"kind\\\":\\\"observation\\\",\\\"observation\\\":\\\"retained\\\",\\\"record_revision\\\":12,\\\"request_cid\\\":\\\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\\\",\\\"version\\\":\\\"actql-remote-runtime-bundle-custody-response/0.1\\\"}\",\"version\":\"actql-remote-bundle-custody-observation/0.1\"}"
}

///|
fn outbound_custody_fixture_request() -> @bundle.RemoteBundleCustodyRequest {
  @bundle.admit_bundle_custody_request_json(
    custody_vector_retain_request_body(),
    custody_vector_retain_request_cid(),
  ).unwrap()
}

///|
fn outbound_custody_fixture_response(
  request : @bundle.RemoteBundleCustodyRequest,
) -> @bundle.RemoteBundleCustodyResponse {
  @bundle.admit_bundle_custody_response_json(
    request,
    custody_vector_retained_response_body(),
    custody_vector_retained_response_cid(),
  ).unwrap()
}

///|
test "pre-Run Bundle poll preserves original common bytes and is never a dispatch" {
  let request = outbound_custody_fixture_request()
  let wire = remote_poll_bundle_custody_json(request, 37L).unwrap()
  assert_eq(wire, custody_poll_vector())
  let delivery = admit_remote_poll_bundle_custody_json(wire).unwrap()
  assert_eq(remote_poll_bundle_custody_delivery_revision(delivery), 37L)
  assert_eq(
    @bundle.bundle_custody_request_json(
      remote_poll_bundle_custody_request(delivery),
    ).unwrap(),
    custody_vector_retain_request_body(),
  )
  assert_true(
    admit_remote_site_poll_operation_json(wire) is Ok(BundleCustody(_)),
  )
  assert_true(admit_remote_poll_operation_json(wire) is Err(_))
  let context = @bundle.admit_bundle_custody_request_json(
    custody_vector_context_request_body(),
    custody_vector_context_request_cid(),
  ).unwrap()
  let wire = remote_poll_bundle_custody_json(context, 38L).unwrap()
  assert_true(
    admit_remote_site_poll_operation_json(wire) is Ok(BundleCustody(_)),
  )
}

///|
test "pre-Run Bundle poll rejects changed identity shape noncanonical and unbounded delivery" {
  let request = outbound_custody_fixture_request()
  for revision in [0L, -1L, 9007199254740992L] {
    assert_true(remote_poll_bundle_custody_json(request, revision) is Err(_))
  }
  let wire = custody_poll_vector()
  for
    invalid in [
      " " + wire,
      wire.replace(old="{", new="{\"unexpected\":true,"),
      wire.replace(
        old="\"delivery_revision\":37",
        new="\"delivery_revision\":37.0",
      ),
      wire.replace(
        old="\"delivery_revision\":37",
        new="\"delivery_revision\":0",
      ),
      wire.replace(
        old="\"delivery_revision\":37",
        new="\"delivery_revision\":9007199254740992",
      ),
      wire.replace(
        old="\"delivery_revision\":37",
        new="\"delivery_revision\":37,\"delivery_revision\":37",
      ),
      wire.replace(
        old=custody_vector_retain_request_cid(),
        new=custody_vector_context_request_cid(),
      ),
      wire.replace(old="poll-bundle-custody/0.1", new="poll-dispatch/0.1"),
    ] {
    assert_true(admit_remote_site_poll_operation_json(invalid) is Err(_))
  }
  let oversized = StringBuilder()
  for _ in 0..<100 {
    oversized.write_string(wire)
  }
  assert_true(
    admit_remote_site_poll_operation_json(oversized.to_string()) is Err(_),
  )
}

///|
test "Bundle observation binds original request response and exact pending member delivery" {
  let request = outbound_custody_fixture_request()
  let response = outbound_custody_fixture_response(request)
  let wire = remote_bundle_custody_observation_json(request, response, 37L).unwrap()
  assert_eq(wire, custody_observation_vector())
  let admitted = admit_remote_bundle_custody_observation_json(
    wire, request, 37L,
  ).unwrap()
  assert_eq(
    @bundle.bundle_custody_response_json(admitted).unwrap(),
    custody_vector_retained_response_body(),
  )
  assert_true(
    admit_remote_bundle_custody_observation_json(wire, request, 38L) is Err(_),
  )
  let context = @bundle.admit_bundle_custody_request_json(
    custody_vector_context_request_body(),
    custody_vector_context_request_cid(),
  ).unwrap()
  assert_true(
    admit_remote_bundle_custody_observation_json(wire, context, 37L) is Err(_),
  )
  assert_true(
    remote_bundle_custody_observation_json(context, response, 37L) is Err(_),
  )
  for
    invalid in [
      " " + wire,
      wire.replace(old="observation/0.1", new="observation/0.2"),
      wire.replace(
        old=custody_vector_retained_response_cid(),
        new=custody_vector_retain_request_cid(),
      ),
    ] {
    assert_true(
      admit_remote_bundle_custody_observation_json(invalid, request, 37L)
      is Err(_),
    )
  }
}

///|
test "Bundle observation ACK rejects bare success other delivery and other response" {
  let request = outbound_custody_fixture_request()
  let response = outbound_custody_fixture_response(request)
  let expected = "{\"delivery_revision\":37,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"response_cid\":\"sha256:d50f438c17a0696073915837428e680a60807904d37a0d4719d4bda388df2cf3\",\"version\":\"actql-remote-bundle-custody-observation-ack/0.1\"}"
  assert_eq(
    remote_bundle_custody_observation_ack_json(request, response, 37L).unwrap(),
    expected,
  )
  assert_true(
    admit_remote_bundle_custody_observation_ack_json(
      expected, request, response, 37L,
    )
    is Ok(_),
  )
  for
    invalid in [
      "",
      "{}",
      "200",
      " " + expected,
      expected.replace(
        old="\"delivery_revision\":37",
        new="\"delivery_revision\":38",
      ),
      expected.replace(
        old=custody_vector_retained_response_cid(),
        new=custody_vector_retain_request_cid(),
      ),
    ] {
    assert_true(
      admit_remote_bundle_custody_observation_ack_json(
        invalid, request, response, 37L,
      )
      is Err(_),
    )
  }
}

///|
test "obsolete Bundle transport disposition is exact bound and never a custody ACK" {
  let request = outbound_custody_fixture_request()
  let response = outbound_custody_fixture_response(request)
  let expected = "{\"delivery_revision\":37,\"disposition\":\"obsolete\",\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"response_cid\":\"sha256:d50f438c17a0696073915837428e680a60807904d37a0d4719d4bda388df2cf3\",\"version\":\"actql-remote-bundle-custody-observation-disposition/0.1\"}"
  assert_eq(
    remote_bundle_custody_observation_obsolete_json(request, response, 37L).unwrap(),
    expected,
  )
  assert_true(
    admit_remote_bundle_custody_observation_reply_json(
      expected, request, response, 37L,
    )
    is Ok(Obsolete),
  )
  assert_true(
    admit_remote_bundle_custody_observation_ack_json(
      expected, request, response, 37L,
    )
    is Err(_),
  )
  for
    invalid in [
      "{}",
      "409",
      " " + expected,
      expected.replace(
        old="\"delivery_revision\":37",
        new="\"delivery_revision\":38",
      ),
      expected.replace(
        old="\"disposition\":\"obsolete\"",
        new="\"disposition\":\"accepted\"",
      ),
      expected.replace(
        old=custody_vector_retain_request_cid(),
        new=custody_vector_context_request_cid(),
      ),
      expected.replace(
        old=custody_vector_retained_response_cid(),
        new=custody_vector_retain_request_cid(),
      ),
      expected.replace(old="{", new="{\"forged\":true,"),
    ] {
    assert_true(
      admit_remote_bundle_custody_observation_reply_json(
        invalid, request, response, 37L,
      )
      is Err(_),
    )
  }
}
