// Independent common protocol fixtures; these tests cover receiver admission only.

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
fn custody_configuration_fixture() -> NativeBundleCustodyConfiguration {
  {
    coordinator_authority: "coordinator-a",
    workspace_id: "workspace-a",
    authority_scope_cid: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    environment: "production",
    site_key: "site-a",
    site_generation: 7,
    runtime_bundle_cid: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    connector_registration: "connector-a",
    connector_revision: "revision-a",
    strategy_revision: "strategy-a",
  }
}

///|
test "Bundle receiver requires current exact trusted scope and authenticated Coordinator" {
  let request = @bundle_protocol.admit_bundle_custody_request_json(
    custody_vector_retain_request_body(),
    custody_vector_retain_request_cid(),
  ).unwrap()
  let configuration = custody_configuration_fixture()
  assert_true(
    native_bundle_custody_authorized(
      configuration, "coordinator-a", request, true,
    )
    is Ok(_),
  )
  assert_true(
    native_bundle_custody_authorized(configuration, "other", request, true)
    is Err(AuthorityRejected),
  )
  for
    changed in [
      { ..configuration, coordinator_authority: "other", },
      { ..configuration, workspace_id: "other", },
      { ..configuration, authority_scope_cid: "other", },
      { ..configuration, environment: "other", },
      { ..configuration, site_key: "other", },
      { ..configuration, site_generation: 8, },
      { ..configuration, runtime_bundle_cid: "other", },
      { ..configuration, connector_registration: "", },
      { ..configuration, connector_revision: "", },
      { ..configuration, strategy_revision: "", },
    ] {
    assert_true(
      native_bundle_custody_authorized(changed, "coordinator-a", request, true)
      is Err(AuthorityRejected),
    )
  }
}

///|
test "waiting Bundle retain rechecks admission while context query has no retain permission" {
  let configuration = custody_configuration_fixture()
  let retain = @bundle_protocol.admit_bundle_custody_request_json(
    custody_vector_retain_request_body(),
    custody_vector_retain_request_cid(),
  ).unwrap()
  assert_true(
    native_bundle_custody_authorized(
      configuration, "coordinator-a", retain, true,
    )
    is Ok(_),
  )
  assert_true(
    native_bundle_custody_authorized(
      configuration, "coordinator-a", retain, false,
    )
    is Err(AdmissionClosed),
  )
  let query = @bundle_protocol.admit_bundle_custody_request_json(
    custody_vector_context_request_body(),
    custody_vector_context_request_cid(),
  ).unwrap()
  assert_true(
    native_bundle_custody_authorized(
      configuration, "coordinator-a", query, false,
    )
    is Ok(_),
  )
}

///|
test "original context retirement and superseded retain retire only their transport slot" {
  // This callback fixture checks transport progression, not Store success.
  // The separate Native test obtains actual signed-catalog observations.
  let retain = @bundle_protocol.admit_bundle_custody_request_json(
    custody_vector_retain_request_body(),
    custody_vector_retain_request_cid(),
  ).unwrap()
  let context = @bundle_protocol.admit_bundle_custody_request_json(
    custody_vector_context_request_body(),
    custody_vector_context_request_cid(),
  ).unwrap()
  let binding = @bundle_protocol.bundle_custody_request_binding(retain).unwrap()
  let retained_fixture = @bundle_protocol.prepare_bundle_custody_response_fields(
    retain,
    "retained",
    Some("123e4567-e89b-42d3-a456-426614174000"),
    Some(12),
  ).unwrap()
  let context_fixture = @bundle_protocol.prepare_bundle_custody_context_response(
    context, binding,
  ).unwrap()
  for
    (request, response) in [
      (context, context_fixture),
      (retain, retained_fixture),
    ] {
    let delivery = @remote.admit_remote_poll_bundle_custody_json(
      @remote.remote_poll_bundle_custody_json(request, 37L).unwrap(),
    ).unwrap()
    let original = prepare_native_bundle_custody_pending_report(
      delivery, response,
    ).unwrap()
    let expected = @remote.remote_bundle_custody_observation_json(
      request, response, 37L,
    ).unwrap()
    let sends = [0]
    let post = fn(
      actual_delivery : @remote.RemotePollBundleCustody,
      actual_response : @bundle_protocol.RemoteBundleCustodyResponse,
    ) -> Result[
      @remote.RemoteBundleCustodyObservationReply,
      @client.NativeRemoteClientIssue,
    ] {
      let actual_request = @remote.remote_poll_bundle_custody_request(
        actual_delivery,
      )
      let revision = @remote.remote_poll_bundle_custody_delivery_revision(
        actual_delivery,
      )
      if @remote.remote_bundle_custody_observation_json(
          actual_request, actual_response, revision,
        ) !=
        Ok(expected) {
        return Err(@client.Protocol(@remote.InvalidDispatch))
      }
      sends[0] += 1
      if sends[0] == 1 {
        return Err(@client.HttpStatus(503))
      }
      let wire = @remote.remote_bundle_custody_observation_obsolete_json(
        actual_request, actual_response, revision,
      ).unwrap()
      match
        @remote.admit_remote_bundle_custody_observation_reply_json(
          wire, request, response, 37L,
        ) {
        Ok(reply) => Ok(reply)
        Err(issue) => Err(@client.Protocol(issue))
      }
    }
    let (pending, reply) = advance_native_bundle_custody_report(
      Some(original),
      post,
    )
    assert_true(pending is Some(_))
    assert_true(reply is None)
    let (pending, reply) = advance_native_bundle_custody_report(pending, post)
    assert_true(pending is None)
    assert_true(reply is Some(Obsolete))
    let (pending, reply) = advance_native_bundle_custody_report(pending, post)
    assert_true(pending is None)
    assert_true(reply is None)
    assert_eq(sends[0], 2)
  }
}
