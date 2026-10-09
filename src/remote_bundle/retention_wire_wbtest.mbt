// Independent canonical vectors: literal values, Python json and hashlib.
// These fixtures are not obtained from the product serializer.

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
fn custody_vector_context_response_body() -> String {
  "{\"binding\":\"{\\\"attempt_id\\\":\\\"hold-a\\\",\\\"authority_scope_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"catalog_incarnation\\\":\\\"123e4567-e89b-42d3-a456-426614174000\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"distribution_cid\\\":\\\"sha256:db2c1d1c2bcac2bac713db8b6065ef525014133c60b672540d20f9be0bdb4f06\\\",\\\"environment\\\":\\\"production\\\",\\\"initial_revision\\\":11,\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"set_revision_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"site_generation\\\":7,\\\"site_key\\\":\\\"site-a\\\",\\\"version\\\":\\\"actql-remote-runtime-bundle-hold-binding/0.1\\\",\\\"workspace_id\\\":\\\"workspace-a\\\"}\",\"binding_cid\":\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\",\"kind\":\"context\",\"request_cid\":\"sha256:a712ca85e73d44f13bf30d46a3cb43da0f020438b005f5cf445bd9be8d2ee3f6\",\"version\":\"actql-remote-runtime-bundle-custody-response/0.1\"}"
}

///|
fn custody_vector_context_response_cid() -> String {
  "sha256:f97a5757e928d9d1117c850a8fe11ebb2872a42032b3cefb247a557075f6c3cd"
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
fn custody_vector_fenced_response_body() -> String {
  "{\"binding_cid\":\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\",\"catalog_incarnation\":\"123e4567-e89b-42d3-a456-426614174000\",\"kind\":\"observation\",\"observation\":\"fenced\",\"record_revision\":12,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"version\":\"actql-remote-runtime-bundle-custody-response/0.1\"}"
}

///|
fn custody_vector_fenced_response_cid() -> String {
  "sha256:63ef577c6f6ce659ccc2c8b715626a7a2dd3a4a1b6329862cd5d4e78310a27bc"
}

///|
fn custody_vector_unresolved_response_body() -> String {
  "{\"binding_cid\":\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\",\"catalog_incarnation\":\"123e4567-e89b-42d3-a456-426614174000\",\"kind\":\"observation\",\"observation\":\"unresolved\",\"record_revision\":11,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"version\":\"actql-remote-runtime-bundle-custody-response/0.1\"}"
}

///|
fn custody_vector_unresolved_response_cid() -> String {
  "sha256:7e4ef1776af26ae5179abadc1e76eea4c2d5a3ebb2bfca0297c6d6bedac1e4b5"
}

///|
fn custody_vector_unavailable_response_body() -> String {
  "{\"binding_cid\":\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\",\"catalog_incarnation\":\"123e4567-e89b-42d3-a456-426614174000\",\"kind\":\"observation\",\"observation\":\"unavailable\",\"record_revision\":null,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"version\":\"actql-remote-runtime-bundle-custody-response/0.1\"}"
}

///|
fn custody_vector_unavailable_response_cid() -> String {
  "sha256:52a55cbd9281c83b62baf009464b6c88c4096e24ea5e3a3b63fd5e7695b5e0ab"
}

///|
fn custody_vector_request_cid(operation : String) -> String {
  match operation {
    "retain" =>
      "sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d"
    "query" =>
      "sha256:1e8e00fe38cbc657887ffe8e2e6dabc4953307335402086cad63724be0abd952"
    "release" =>
      "sha256:090e6569f0486cd33fb70365630c85f6e556096681d4beeac3cdb5dae3606010"
    _ => abort("invalid fixture operation")
  }
}

///|
fn custody_fixture_request(
  operation? : String = "retain",
) -> RemoteBundleCustodyRequest {
  prepare_bundle_custody_request(
    hold_fixture_distribution(),
    hold_fixture_binding(),
    operation,
  ).unwrap()
}

///|
fn custody_fixture_context_query() -> RemoteBundleCustodyRequest {
  prepare_bundle_custody_context_query(
    hold_fixture_distribution(),
    hold_fixture_scope(),
  ).unwrap()
}

///|
test "bundle custody requests match independent canonical vectors and bind every verb" {
  for operation in ["retain", "query", "release"] {
    let request = custody_fixture_request(operation~)
    let expected_body = custody_vector_retain_request_body().replace(
      old="\"operation\":\"retain\"",
      new="\"operation\":\"" + operation + "\"",
    )
    assert_eq(bundle_custody_request_json(request).unwrap(), expected_body)
    assert_eq(
      bundle_custody_request_identity(request),
      custody_vector_request_cid(operation),
    )
    let admitted = admit_bundle_custody_request_json(
      expected_body,
      custody_vector_request_cid(operation),
    ).unwrap()
    assert_eq(bundle_custody_request_operation(admitted), operation)
    assert_eq(
      bundle_distribution_identity(
        bundle_custody_request_distribution(admitted),
      ),
      hold_vector_distribution_cid(),
    )
    assert_eq(
      bundle_hold_scope_identity(bundle_custody_request_scope(admitted)),
      hold_vector_scope_cid(),
    )
    assert_eq(
      bundle_hold_binding_identity(
        bundle_custody_request_binding(admitted).unwrap(),
      ),
      hold_vector_binding_cid(),
    )
  }
  assert_eq(
    custody_vector_retain_request_cid(),
    custody_vector_request_cid("retain"),
  )
  let context = custody_fixture_context_query()
  assert_eq(
    bundle_custody_request_json(context).unwrap(),
    custody_vector_context_request_body(),
  )
  assert_eq(
    bundle_custody_request_identity(context),
    custody_vector_context_request_cid(),
  )
  let admitted = admit_bundle_custody_request_json(
    custody_vector_context_request_body(),
    custody_vector_context_request_cid(),
  ).unwrap()
  assert_true(bundle_custody_request_binding(admitted) is None)
  assert_eq(
    bundle_hold_scope_identity(bundle_custody_request_scope(admitted)),
    hold_vector_scope_cid(),
  )
  assert_true(
    bundle_custody_request_identity(context) !=
    custody_vector_request_cid("query"),
  )
}

///|
test "bundle custody request admission rejects unknown shapes operations and substitutions" {
  let body = custody_vector_retain_request_body()
  for
    invalid in [
      " " + body,
      body.replace(old="custody-request/0.1", new="custody-request/0.2"),
      body.replace(old="{", new="{\"unknown\":true,"),
      body.replace(old="{", new="{\"operation\":\"retain\","),
      body.replace(
        old="\"operation\":\"retain\"",
        new="\"operation\":\"install\"",
      ),
      body.replace(old="\"operation\":\"retain\",", new=""),
      body.replace(old="\"operation\":\"retain\"", new="\"operation\":null"),
      body.replace(
        old="\"version\":\"actql-remote-runtime-bundle-custody-request/0.1\"",
        new="\"scope_cid\":\"" +
          hold_vector_scope_cid() +
          "\",\"version\":\"actql-remote-runtime-bundle-custody-request/0.1\"",
      ),
      custody_vector_context_request_body().replace(
        old="\"operation\":\"query\"",
        new="\"operation\":\"retain\"",
      ),
    ] {
    assert_true(
      admit_bundle_custody_request_json(
        invalid,
        custody_vector_retain_request_cid(),
      )
      is Err(InvalidBundle),
    )
  }
  for operation in ["query", "release"] {
    let changed = body.replace(
      old="\"operation\":\"retain\"",
      new="\"operation\":\"" + operation + "\"",
    )
    assert_true(
      admit_bundle_custody_request_json(
        changed,
        custody_vector_retain_request_cid(),
      )
      is Err(BundleIdentityMismatch),
    )
  }
  assert_true(
    admit_bundle_custody_request_json(body, hold_fixture_cid_a())
    is Err(BundleIdentityMismatch),
  )
  for operation in ["", "install", "activate", "drain", "reclaim", "Retain"] {
    assert_true(
      prepare_bundle_custody_request(
        hold_fixture_distribution(),
        hold_fixture_binding(),
        operation,
      )
      is Err(InvalidBundle),
    )
  }
  let other_distribution = prepare_bundle_distribution([hold_fixture_cid_a()]).unwrap()
  assert_true(
    prepare_bundle_custody_context_query(
      other_distribution,
      hold_fixture_scope(),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    prepare_bundle_custody_request(
      other_distribution,
      hold_fixture_binding(),
      "retain",
    )
    is Err(InvalidBundle),
  )
  let request = custody_fixture_request()
  assert_true(
    bundle_custody_request_json({ ..request, operation: "release", })
    is Err(BundleIdentityMismatch),
  )
  assert_true(
    bundle_custody_request_json({
      ..request,
      scope: hold_fixture_scope(workspace="other"),
    })
    is Err(InvalidBundle),
  )
}

///|
test "bundle custody context reply has an independent vector and cannot assert retention" {
  let request = custody_fixture_context_query()
  let response = prepare_bundle_custody_context_response(
    request,
    hold_fixture_binding(),
  ).unwrap()
  assert_eq(
    bundle_custody_response_json(response).unwrap(),
    custody_vector_context_response_body(),
  )
  assert_eq(
    bundle_custody_response_identity(response),
    custody_vector_context_response_cid(),
  )
  let admitted = admit_bundle_custody_response_json(
    request,
    custody_vector_context_response_body(),
    custody_vector_context_response_cid(),
  ).unwrap()
  assert_eq(bundle_custody_response_kind(admitted), "context")
  assert_true(bundle_custody_response_observation(admitted) is None)
  assert_eq(bundle_custody_response_observation_text(admitted), "")
  assert_eq(
    bundle_custody_response_catalog_incarnation(admitted),
    Some(hold_fixture_catalog()),
  )
  assert_eq(
    bundle_custody_response_catalog_incarnation_text(admitted),
    hold_fixture_catalog(),
  )
  assert_eq(bundle_custody_response_record_revision(admitted), Some(11))
  assert_eq(bundle_custody_response_record_revision_text(admitted), "11")
  assert_eq(
    bundle_hold_binding_identity(bundle_custody_response_binding(admitted)),
    hold_vector_binding_cid(),
  )
  assert_true(
    prepare_bundle_custody_response(
      request,
      BundleHoldRetained,
      Some(hold_fixture_catalog()),
      Some(12),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    prepare_bundle_custody_response_fields(
      request,
      "retained",
      Some(hold_fixture_catalog()),
      Some(12),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    prepare_bundle_custody_context_response(
      custody_fixture_request(),
      hold_fixture_binding(),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    admit_bundle_custody_response_json(
      custody_fixture_request(),
      custody_vector_context_response_body(),
      custody_vector_context_response_cid(),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    admit_bundle_custody_response_json(
      request,
      custody_vector_retained_response_body(),
      custody_vector_retained_response_cid(),
    )
    is Err(InvalidBundle),
  )
}

///|
test "bundle custody observation responses match independent canonical vectors" {
  let request = custody_fixture_request()
  for
    (observation, revision, body, cid) in [
      (
        BundleHoldRetained,
        Some(12),
        custody_vector_retained_response_body(),
        custody_vector_retained_response_cid(),
      ),
      (
        BundleHoldFenced,
        Some(12),
        custody_vector_fenced_response_body(),
        custody_vector_fenced_response_cid(),
      ),
      (
        BundleHoldUnresolved,
        Some(11),
        custody_vector_unresolved_response_body(),
        custody_vector_unresolved_response_cid(),
      ),
      (
        BundleHoldUnavailable,
        None,
        custody_vector_unavailable_response_body(),
        custody_vector_unavailable_response_cid(),
      ),
    ] {
    let response = prepare_bundle_custody_response(
      request,
      observation,
      Some(hold_fixture_catalog()),
      revision,
    ).unwrap()
    assert_eq(bundle_custody_response_json(response).unwrap(), body)
    assert_eq(bundle_custody_response_identity(response), cid)
    let from_fields = prepare_bundle_custody_response_fields(
      request,
      bundle_hold_observation_projection(observation),
      Some(hold_fixture_catalog()),
      revision,
    ).unwrap()
    assert_eq(bundle_custody_response_identity(from_fields), cid)
    let admitted = admit_bundle_custody_response_json(request, body, cid).unwrap()
    assert_eq(bundle_custody_response_kind(admitted), "observation")
    assert_eq(bundle_custody_response_observation(admitted), Some(observation))
    assert_eq(
      bundle_custody_response_observation_text(admitted),
      bundle_hold_observation_projection(observation),
    )
    assert_eq(bundle_custody_response_record_revision(admitted), revision)
    assert_eq(
      bundle_custody_response_record_revision_text(admitted),
      match revision {
        Some(value) => value.to_string()
        None => ""
      },
    )
  }
  for invalid in ["", "ready", "absent", "Retained"] {
    assert_true(
      prepare_bundle_custody_response_fields(
        request,
        invalid,
        Some(hold_fixture_catalog()),
        Some(12),
      )
      is Err(InvalidBundle),
    )
  }
}

///|
test "bundle custody replies reject stale false fenced and malformed proof even with a matching hash" {
  let request = custody_fixture_request()
  let body = custody_vector_fenced_response_body()
  for
    invalid in [
      " " + body,
      body.replace(old="custody-response/0.1", new="custody-response/0.2"),
      body.replace(old="{", new="{\"unknown\":true,"),
      body.replace(old="{", new="{\"kind\":\"observation\","),
      body.replace(old="\"kind\":\"observation\"", new="\"kind\":\"context\""),
      body.replace(
        old="\"observation\":\"fenced\"",
        new="\"observation\":\"ready\"",
      ),
      body.replace(old="\"record_revision\":12", new="\"record_revision\":11"),
      body.replace(old="\"record_revision\":12", new="\"record_revision\":10"),
      body.replace(old="\"record_revision\":12", new="\"record_revision\":null"),
      body.replace(old="\"record_revision\":12", new="\"record_revision\":12.0"),
      body.replace(old="\"record_revision\":12", new="\"record_revision\":-1"),
      body.replace(
        old="\"record_revision\":12",
        new="\"record_revision\":2147483648",
      ),
      body.replace(old="\"record_revision\":12,", new=""),
      body.replace(
        old=hold_fixture_catalog(),
        new="123e4567-e89b-42d3-a456-426614174001",
      ),
      body.replace(
        old="\"catalog_incarnation\":\"" + hold_fixture_catalog() + "\"",
        new="\"catalog_incarnation\":null",
      ),
      body.replace(
        old="\"catalog_incarnation\":\"" + hold_fixture_catalog() + "\",",
        new="",
      ),
    ] {
    assert_true(
      admit_bundle_custody_response_json(
        request,
        invalid,
        bundle_value_identity(invalid).unwrap(),
      )
      is Err(InvalidBundle),
    )
  }
  for observation in [BundleHoldRetained, BundleHoldFenced] {
    for revision in [None, Some(10), Some(11)] {
      assert_true(
        prepare_bundle_custody_response(
          request,
          observation,
          Some(hold_fixture_catalog()),
          revision,
        )
        is Err(InvalidBundle),
      )
    }
    assert_true(
      prepare_bundle_custody_response(request, observation, None, Some(12))
      is Err(InvalidBundle),
    )
  }
  for revision in [None, Some(10), Some(12)] {
    assert_true(
      prepare_bundle_custody_response(
        request,
        BundleHoldUnresolved,
        Some(hold_fixture_catalog()),
        revision,
      )
      is Err(InvalidBundle),
    )
  }
  assert_true(
    prepare_bundle_custody_response(
      request,
      BundleHoldUnavailable,
      Some(""),
      None,
    )
    is Err(InvalidBundle),
  )
  assert_true(
    prepare_bundle_custody_response(
      request,
      BundleHoldUnavailable,
      Some(hold_fixture_catalog()),
      Some(-1),
    )
    is Err(InvalidBundle),
  )
  let unavailable = prepare_bundle_custody_response(
    request,
    BundleHoldUnavailable,
    Some("123e4567-e89b-42d3-a456-426614174001"),
    None,
  ).unwrap()
  assert_eq(
    bundle_custody_response_observation(unavailable),
    Some(BundleHoldUnavailable),
  )
  assert_eq(bundle_custody_response_record_revision_text(unavailable), "")
  let zero = prepare_bundle_custody_response(
    request,
    BundleHoldUnavailable,
    Some(hold_fixture_catalog()),
    Some(0),
  ).unwrap()
  assert_eq(bundle_custody_response_record_revision_text(zero), "0")
  let unknown = prepare_bundle_custody_response_fields(
    request,
    "unavailable",
    None,
    None,
  ).unwrap()
  assert_eq(bundle_custody_response_catalog_incarnation(unknown), None)
  assert_eq(bundle_custody_response_catalog_incarnation_text(unknown), "")
  let body = bundle_custody_response_json(unknown).unwrap()
  assert_eq(body, custody_vector_unknown_catalog_response_body())
  assert_eq(
    bundle_custody_response_identity(unknown),
    custody_vector_unknown_catalog_response_cid(),
  )
  let admitted = admit_bundle_custody_response_json(
    request,
    body,
    custody_vector_unknown_catalog_response_cid(),
  ).unwrap()
  assert_eq(
    bundle_custody_response_observation(admitted),
    Some(BundleHoldUnavailable),
  )
  assert_eq(bundle_custody_response_catalog_incarnation(admitted), None)
  assert_true(
    prepare_bundle_custody_response(
      request,
      BundleHoldUnresolved,
      None,
      Some(11),
    )
    is Err(InvalidBundle),
  )
}

///|
test "bundle custody replies bind request verb scope catalog revision and exact binding" {
  let request = custody_fixture_request()
  for operation in ["query", "release"] {
    assert_true(
      admit_bundle_custody_response_json(
        custody_fixture_request(operation~),
        custody_vector_retained_response_body(),
        custody_vector_retained_response_cid(),
      )
      is Err(BundleIdentityMismatch),
    )
  }
  assert_true(
    admit_bundle_custody_response_json(
      request,
      custody_vector_retained_response_body(),
      hold_fixture_cid_a(),
    )
    is Err(BundleIdentityMismatch),
  )
  let false_binding = custody_vector_retained_response_body().replace(
    old=hold_vector_binding_cid(),
    new=hold_fixture_cid_a(),
  )
  assert_true(
    admit_bundle_custody_response_json(
      request,
      false_binding,
      bundle_value_identity(false_binding).unwrap(),
    )
    is Err(BundleIdentityMismatch),
  )
  let context = custody_fixture_context_query()
  for
    scope in [
      hold_fixture_scope(coordinator="other"),
      hold_fixture_scope(workspace="other"),
      hold_fixture_scope(runtime_bundle_cid=hold_fixture_cid_b()),
      hold_fixture_scope(site="other"),
      hold_fixture_scope(generation=8),
      hold_fixture_scope(attempt="other"),
    ] {
    let binding = prepare_bundle_hold_binding_from_scope(
      scope,
      hold_fixture_catalog(),
      11,
    ).unwrap()
    assert_true(
      prepare_bundle_custody_context_response(context, binding)
      is Err(InvalidBundle),
    )
    let other_context = prepare_bundle_custody_context_query(
      hold_fixture_distribution(),
      scope,
    ).unwrap()
    let other_response = prepare_bundle_custody_context_response(
      other_context, binding,
    ).unwrap()
    let body = bundle_custody_response_json(other_response)
      .unwrap()
      .replace(
        old=bundle_custody_request_identity(other_context),
        new=bundle_custody_request_identity(context),
      )
    assert_true(
      admit_bundle_custody_response_json(
        context,
        body,
        bundle_value_identity(body).unwrap(),
      )
      is Err(InvalidBundle),
    )
    let other_request = prepare_bundle_custody_request(
      hold_fixture_distribution(),
      binding,
      "retain",
    ).unwrap()
    let other_response = prepare_bundle_custody_response(
      other_request,
      BundleHoldRetained,
      Some(hold_fixture_catalog()),
      Some(12),
    ).unwrap()
    let body = bundle_custody_response_json(other_response)
      .unwrap()
      .replace(
        old=bundle_custody_request_identity(other_request),
        new=bundle_custody_request_identity(request),
      )
    assert_true(
      admit_bundle_custody_response_json(
        request,
        body,
        bundle_value_identity(body).unwrap(),
      )
      is Err(BundleIdentityMismatch),
    )
  }
}

///|
test "bundle custody charges nested payloads to a single total UTF8 control budget" {
  let members = [hold_fixture_cid_a()]
  for index in 1000..<1883 {
    members.push(
      "sha256:000000000000000000000000000000000000000000000000000000000000" +
      index.to_string(),
    )
  }
  let distribution = prepare_bundle_distribution(members).unwrap()
  assert_eq(
    @utf8.encode(bundle_distribution_json(distribution).unwrap()).length(),
    65498,
  )
  let scope = hold_fixture_scope(distribution~)
  let binding = prepare_bundle_hold_binding_from_scope(
    scope,
    hold_fixture_catalog(),
    11,
  ).unwrap()
  assert_true(bundle_hold_scope_json(scope) is Ok(_))
  assert_true(bundle_hold_binding_json(binding) is Ok(_))
  assert_true(
    prepare_bundle_custody_context_query(distribution, scope)
    is Err(InvalidBundle),
  )
  assert_true(
    prepare_bundle_custody_request(distribution, binding, "retain")
    is Err(InvalidBundle),
  )
  let oversized = StringBuilder()
  for _ in 0..<100 {
    oversized.write_string(custody_vector_retain_request_body())
  }
  assert_true(
    admit_bundle_custody_request_json(
      oversized.to_string(),
      custody_vector_retain_request_cid(),
    )
    is Err(InvalidBundle),
  )
  assert_true(
    admit_bundle_custody_response_json(
      custody_fixture_request(),
      oversized.to_string(),
      custody_vector_retained_response_cid(),
    )
    is Err(InvalidBundle),
  )
}

///|
fn custody_vector_unknown_catalog_response_body() -> String {
  "{\"binding_cid\":\"sha256:43996a2fa47f5c49b74175ad6906ee2d9c03ac74f5f1163fe3b087c5f79ad594\",\"catalog_incarnation\":null,\"kind\":\"observation\",\"observation\":\"unavailable\",\"record_revision\":null,\"request_cid\":\"sha256:a823575b8877d19528e2e5e37c385ac42aa11dc6aa1049f80720a2c816a4a41d\",\"version\":\"actql-remote-runtime-bundle-custody-response/0.1\"}"
}

///|
fn custody_vector_unknown_catalog_response_cid() -> String {
  "sha256:51f1d6ac2bd851f8c4a5f717862ccc61224e0e9442334ae07ff071cbf2c28a8d"
}
