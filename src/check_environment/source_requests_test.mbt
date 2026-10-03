///|
fn request_limits() -> SourceRequestLimits {
  { max_work: 100000, max_roles: 1000, }
}

///|
fn request_carriers(
  request : Json,
  response : Json,
  correlation : Json?,
  kind? : String = "relation",
  acquisition? : String = "fetch",
  view_count? : Int = 1,
  native_batch? : String? = None,
) -> CarrierSchemas raise {
  let bodies = value_bodies("{\"type\":\"number\",\"nullable\":false}")
  bodies["request_schema"] = request
  bodies["carrier_schema"] = response
  let contents = reference_fixture(
    complete_view=true,
    native_batch~,
    carrier=kind,
    acquisition_kind=acquisition,
    view_count~,
    bodies~,
    path=["view", "acquisition", "correlation"],
    replacement=correlation,
    policy_body=Some(policy_body_fixture("unknown")),
  )
  let refs = check_catalog_references(contents, reference_caps()).unwrap()
  let values = check_protocol_value_contracts(
    check_source_data_policies(refs, policy_limits()).unwrap(),
    protocol_value_limits(),
  ).unwrap()
  let shapes = check_source_view_shapes(values, {
    max_work: 100000,
    max_views: 10,
  }).unwrap()
  check_carrier_schemas(
    check_source_read_modes(shapes, 100000).unwrap(),
    carrier_limits(),
  ).unwrap()
}

///|
fn correlation_fixture(cardinality? : String = "zero_or_one") -> Json raise {
  @json.parse(
    "{\"request_fields\":[\"other\",\"id\"],\"response_fields\":[\"other\",\"id\"],\"identity\":[\"id\",\"other\"],\"cardinality\":\"" +
    cardinality +
    "\"}",
  )
}

///|
test "SourceView request proofs retain ordered typed pairs identity and exact owners" {
  for
    (word, expected) in [
      ("zero_or_one", SourceCardinality::ZeroOrOne),
      ("zero_or_many", SourceCardinality::ZeroOrMany),
      ("one", SourceCardinality::One),
      ("one_or_many", SourceCardinality::OneOrMany),
    ] {
    for kind in ["relation", "events", "vectors"] {
      let carriers = request_carriers(
        record_body(),
        role_body(kind),
        Some(correlation_fixture(cardinality=word)),
        kind~,
      )
      let requests = check_source_request_contracts(carriers, request_limits()).unwrap()
      assert_true(physical_equal(source_request_carriers(requests), carriers))
      let view = source_request_at(requests, 0).unwrap()
      let item = source_request_member(view)
      assert_true(
        physical_equal(source_request_for(requests, item).unwrap(), view),
      )
      assert_true(
        physical_equal(reference_member(source_request_reference(view)), item),
      )
      assert_eq(@row.field_count(source_request_schema(view)), 4)
      let correlation = source_request_correlation(view).unwrap()
      assert_eq(source_correlation_cardinality(correlation), expected)
      assert_eq(source_correlation_pair_count(correlation), 2)
      assert_eq(source_correlation_identity_count(correlation), 2)
      for (i, name) in [(0, "other"), (1, "id")] {
        let pair = source_correlation_pair_at(correlation, i).unwrap()
        assert_eq(pair.request.name, name)
        assert_eq(pair.response.name, name)
        let path = @decode.cursor_path(pair.response.source)
        assert_eq(path[path.length() - 2], @source.Key("response_fields"))
        assert_eq(path[path.length() - 1], @source.Index(i))
      }
      assert_eq(
        source_correlation_identity_at(correlation, 0).unwrap().name,
        "id",
      )
      let path = @decode.cursor_path(source_correlation_source(correlation))
      assert_eq(path[path.length() - 1], @source.Key("correlation"))
      assert_true(source_request_at(requests, 1) is None)
      assert_true(source_correlation_pair_at(correlation, -1) is None)
      assert_true(source_correlation_identity_at(correlation, 2) is None)
      let other = request_carriers(
        record_body(),
        role_body(kind),
        Some(correlation_fixture(cardinality=word)),
        kind~,
      )
      let other_item = read_mode_member(
        read_mode_view_at(carrier_schema_modes(other), 0).unwrap(),
      )
      assert_true(source_request_for(requests, other_item) is None)
      let (work, roles, count) = source_request_usage(requests)
      assert_eq((roles, count), (6, 1))
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
      assert_true(
        check_source_request_contracts(carriers, {
          max_work: work,
          max_roles: roles - 1,
        })
        is Err(e) &&
        e.kind == RoleLimit,
      )
    }
  }
}

///|
test "correlation failures retain the exact authored role position" {
  for
    (field, replacement, expected, tail) in [
      (
        "request_fields",
        "[\"other\",\"missing\"]",
        SourceRequestIssueKind::UnknownRequestField("missing"),
        Some(1),
      ),
      (
        "response_fields",
        "[\"other\",\"missing\"]",
        SourceRequestIssueKind::UnknownResponseField("missing"),
        Some(1),
      ),
      (
        "response_fields",
        "[\"other\",\"at\"]",
        SourceRequestIssueKind::IncomparableKeys,
        Some(1),
      ),
      (
        "identity",
        "[\"id\",\"v\"]",
        SourceRequestIssueKind::InvalidIdentity("v"),
        Some(1),
      ),
      (
        "identity",
        "[\"missing\"]",
        SourceRequestIssueKind::UnknownResponseField("missing"),
        Some(0),
      ),
      (
        "response_fields",
        "[\"id\"]",
        SourceRequestIssueKind::MismatchedArity,
        None,
      ),
    ] {
    let fixture = correlation_fixture()
    guard fixture is Object(fields) else { abort("fixture") }
    fields[field] = @json.parse(replacement)
    let carriers = request_carriers(record_body(), record_body(), Some(fixture))
    match check_source_request_contracts(carriers, request_limits()) {
      Err(e) => {
        assert_eq(e.kind, expected)
        let path = @decode.cursor_path(e.source.unwrap())
        match tail {
          Some(i) => {
            assert_eq(path[path.length() - 2], @source.Key(field))
            assert_eq(path[path.length() - 1], @source.Index(i))
          }
          None => assert_eq(path[path.length() - 1], @source.Key(field))
        }
      }
      Ok(_) => abort("invalid role admitted")
    }
  }
}

///|
test "request objects are required without correlation and scan does not acquire keyed semantics" {
  let without = request_carriers(
    record_body(),
    record_body(),
    None,
    acquisition="scan",
  )
  let checked = check_source_request_contracts(without, request_limits()).unwrap()
  assert_true(
    source_request_correlation(source_request_at(checked, 0).unwrap()) is None,
  )
  assert_eq(source_request_usage(checked).1, 0)
  for
    text in [
      "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{}}",
    ] {
    let carriers = request_carriers(@json.parse(text), record_body(), None)
    assert_true(
      check_source_request_contracts(carriers, request_limits()) is Err(e) &&
      e.kind == InvalidRequestContract,
    )
  }
  let scan = request_carriers(
    record_body(),
    record_body(),
    Some(correlation_fixture()),
    acquisition="scan",
  )
  assert_true(
    check_source_request_contracts(scan, request_limits()) is Err(e) &&
    e.kind == InvalidAcquisition,
  )
  for kind in ["search", "fetch", "follow"] {
    let carriers = request_carriers(
      record_body(),
      record_body(),
      Some(correlation_fixture()),
      acquisition=kind,
    )
    assert_true(
      check_source_request_contracts(carriers, request_limits()) is Ok(_),
    )
  }
  assert_true(
    check_source_request_contracts(without, { max_work: -1, max_roles: 0, })
    is Err(e) &&
    e.kind == InvalidLimits,
  )
}

///|
test "correlation KeyComparable does not collapse to identical checked contracts" {
  for
    (left, right, accepted) in [
      (
        "{\"type\":\"decimal\",\"precision\":8,\"scale\":2,\"nullable\":true}", "{\"type\":\"decimal\",\"precision\":38,\"scale\":19,\"nullable\":false}",
        true,
      ),
      (
        "{\"type\":\"string\",\"max_utf8_bytes\":5,\"nullable\":true}", "{\"type\":\"string\",\"nullable\":false}",
        true,
      ),
      (
        "{\"type\":\"artifact_ref\",\"media_type\":\"text/plain\",\"nullable\":false}",
        "{\"type\":\"artifact_ref\",\"media_type\":\"application/json\",\"nullable\":false}",
        true,
      ),
      (
        "{\"type\":\"resource_ref\",\"resource_kind\":\"a\",\"nullable\":false}",
        "{\"type\":\"resource_ref\",\"resource_kind\":\"b\",\"nullable\":false}",
        false,
      ),
      (
        "{\"type\":\"json\",\"nullable\":false}", "{\"type\":\"json\",\"nullable\":false}",
        false,
      ),
    ] {
    let req = @json.parse(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"key\":" +
      left +
      "}}",
    )
    let res = @json.parse(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"key\":" +
      right +
      ",\"id\":{\"type\":\"number\",\"nullable\":false}}}",
    )
    let correlation = @json.parse(
      "{\"request_fields\":[\"key\"],\"response_fields\":[\"key\"],\"identity\":[\"id\"],\"cardinality\":\"zero_or_many\"}",
    )
    let carriers = request_carriers(req, res, Some(correlation))
    assert_eq(
      check_source_request_contracts(carriers, request_limits()) is Ok(_),
      accepted,
    )
  }
}

///|
test "role budgets accumulate across views sharing the same schema envelopes" {
  let carriers = request_carriers(
    record_body(),
    record_body(),
    Some(correlation_fixture()),
    view_count=2,
  )
  let checked = check_source_request_contracts(carriers, request_limits()).unwrap()
  let (work, roles, count) = source_request_usage(checked)
  assert_eq((roles, count), (12, 2))
  assert_true(
    check_source_request_contracts(carriers, {
      max_work: work,
      max_roles: roles,
    })
    is Ok(_),
  )
  assert_true(
    check_source_request_contracts(carriers, { max_work: work, max_roles: 11, })
    is Err(e) &&
    e.kind == RoleLimit,
  )
  assert_true(
    check_source_request_contracts(carriers, {
      max_work: work - 1,
      max_roles: roles,
    })
    is Err(e) &&
    e.kind == WorkLimit,
  )
  assert_true(
    !physical_equal(
      source_request_member(source_request_at(checked, 0).unwrap()),
      source_request_member(source_request_at(checked, 1).unwrap()),
    ),
  )
}

///|
test "a Graph response cannot silently become one field-based correlation record" {
  let body = @json.parse(
    "{\"version\":\"actql-property-graph-contract/0.1\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"node_definitions\":[],\"edge_definitions\":[],\"identity_law_cid\":\"" +
    @graph.property_law_cid() +
    "\",\"value_law_cid\":\"" +
    @graph.property_law_cid() +
    "\"}",
  )
  let plain = request_carriers(record_body(), body, None, kind="graph")
  assert_true(check_source_request_contracts(plain, request_limits()) is Ok(_))
  let keyed = request_carriers(
    record_body(),
    body,
    Some(correlation_fixture()),
    kind="graph",
  )
  assert_true(
    check_source_request_contracts(keyed, request_limits()) is Err(e) &&
    e.kind == UnsupportedResponseCarrier,
  )
}

///|
test "nullable correlation keys do not become nonnull response identity evidence" {
  let body = @json.parse(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"key":{"type":"number","nullable":true},"id":{"type":"number","nullable":false}}}
    ),
  )
  for identity in ["key", "id"] {
    let correlation = @json.parse(
      "{\"request_fields\":[\"key\"],\"response_fields\":[\"key\"],\"identity\":[\"" +
      identity +
      "\"],\"cardinality\":\"one\"}",
    )
    let carriers = request_carriers(body, body, Some(correlation))
    let checked = check_source_request_contracts(carriers, request_limits())
    if identity == "key" {
      assert_true(checked is Err(e) && e.kind == InvalidIdentity("key"))
    } else {
      let pair = source_correlation_pair_at(
        source_request_correlation(
          source_request_at(checked.unwrap(), 0).unwrap(),
        ).unwrap(),
        0,
      ).unwrap()
      assert_true(pair.request.contract.nullable)
      assert_true(pair.response.contract.nullable)
    }
  }
}
