///|
fn native_batch_fixture(cap : String) -> String {
  "{\"kind\":\"native_key_batch\",\"request_key_schema\":\"@lookup_request_key\",\"batch_request_schema\":\"@lookup_batch_request\",\"response_key_schema\":\"@lookup_response_key\",\"max_keys_per_request\":" +
  cap +
  ",\"preserves_per_key_semantics\":true}"
}

///|
fn batch_contents(batch : String) -> CatalogContents raise {
  let bodies = value_bodies("{\"type\":\"number\",\"nullable\":false}")
  bodies["request_schema"] = record_body()
  bodies["carrier_schema"] = role_body("relation")
  reference_fixture(
    complete_view=true,
    native_batch=Some(batch),
    acquisition_kind="fetch",
    bodies~,
    policy_body=Some(policy_body_fixture("unknown")),
  )
}

///|
test "invalid native batch declarations fail before typed request admission" {
  let valid = native_batch_fixture("64")
  for
    body in [
      native_batch_fixture("0"),
      native_batch_fixture("-1"),
      native_batch_fixture("1.5"),
      native_batch_fixture("\"64\""),
      valid.replace(old=":true", new=":false"),
      valid.replace(old="{", new="{\"unknown\":1,"),
    ] {
    let references = check_catalog_references(
      batch_contents(body),
      reference_caps(),
    ).unwrap()
    let values = check_protocol_value_contracts(
      check_source_data_policies(references, policy_limits()).unwrap(),
      protocol_value_limits(),
    ).unwrap()
    assert_true(
      check_source_view_shapes(values, { max_work: 100000, max_views: 10, })
      is Err(_),
    )
  }
  for
    role in [
      "lookup_request_key", "lookup_batch_request", "lookup_response_key",
    ] {
    // Another admitted value contract cannot substitute for the declared role.
    let wrong = valid.replace(old="@" + role, new="@checkpoint")
    assert_true(
      check_catalog_references(batch_contents(wrong), reference_caps())
      is Err(_),
    )
  }
}

///|
test "native batch contracts retain distinct role envelopes and original view occurrences" {
  for
    (cap, expected) in [
      ("1", 1.0),
      ("64", 64.0),
      ("9007199254740992", 9007199254740992.0),
      ("1e100", 1.0e100),
    ] {
    let carriers = request_carriers(
      record_body(),
      role_body("relation"),
      Some(correlation_fixture()),
      native_batch=Some(native_batch_fixture(cap)),
      view_count=2,
    )
    let requests = check_source_request_contracts(carriers, request_limits()).unwrap()
    let (work, roles, count) = source_request_usage(requests)
    assert_eq(count, 2)
    assert_true(
      check_source_request_contracts(carriers, {
        max_work: work,
        max_roles: roles,
      })
      is Ok(_),
    )
    assert_true(
      check_source_request_contracts(carriers, {
        max_work: work - 1,
        max_roles: roles,
      })
      is Err(e) &&
      e.kind == WorkLimit,
    )
    let identities = []
    for i in 0..<2 {
      let view = source_request_at(requests, i).unwrap()
      let batching = source_request_batching(view).unwrap()
      assert_eq(source_batching_max_keys(batching), expected)
      let path = @decode.cursor_path(source_batching_source(batching))
      assert_eq(path[path.length() - 1], @source.Key("batching"))
      for
        (role, kind, name) in [
          (
            SourceBatchRole::RequestKey,
            "lookup_request_key",
            "request_key_schema",
          ),
          (
            SourceBatchRole::BatchRequest,
            "lookup_batch_request",
            "batch_request_schema",
          ),
          (
            SourceBatchRole::ResponseKey,
            "lookup_response_key",
            "response_key_schema",
          ),
        ] {
        let reference = source_batching_reference(batching, role)
        let typed = source_batching_contract(batching, role)
        assert_true(
          physical_equal(
            reference_member(reference),
            source_request_member(view),
          ),
        )
        assert_true(
          physical_equal(
            reference_contract(reference),
            protocol_value_envelope(typed),
          ),
        )
        assert_eq(contract_role(reference_contract(reference)), kind)
        let slot = @decode.cursor_path(reference_source(reference))
        assert_eq(slot[slot.length() - 1], @source.Key(name))
        identities.push(contract_identity(reference_contract(reference)).2)
      }
    }
    assert_true(
      identities[0] != identities[1] &&
      identities[1] != identities[2] &&
      identities[0] != identities[2],
    )
    // Equal type bodies may share typed values, not the per-view reference owner.
    assert_eq(identities[0], identities[3])
    let a = source_request_batching(source_request_at(requests, 0).unwrap()).unwrap()
    let b = source_request_batching(source_request_at(requests, 1).unwrap()).unwrap()
    assert_false(
      physical_equal(
        source_batching_reference(a, RequestKey),
        source_batching_reference(b, RequestKey),
      ),
    )
  }
  let requests = check_source_request_contracts(
    request_carriers(
      record_body(),
      role_body("relation"),
      Some(correlation_fixture()),
    ),
    request_limits(),
  ).unwrap()
  assert_true(
    source_request_batching(source_request_at(requests, 0).unwrap()) is None,
  )
}
