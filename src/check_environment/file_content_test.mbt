///|
fn content_fixture_profile() -> Json raise {
  @json.parse(
    (
      #|{"version":"actql-file-content/0.1","kind":"file_content","admitted_scope_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","content_schema_contract_cid":"@schema","version_capability":{"contract_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","required_nonnull":true},"representation":"exact_stored_bytes"}
    ),
  )
}

///|
fn content_fixture_request() -> Json raise {
  @json.parse(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"record","nullable":false},"version":{"type":"string","nullable":false}}}
    ),
  )
}

///|
fn content_fixture_response() -> Json raise {
  @json.parse(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"record","nullable":false},"version":{"type":"string","nullable":false},"content":{"type":"content_ref","media_type":"application/pdf","nullable":false}}}
    ),
  )
}

///|
fn content_fixture_correlation() -> Json raise {
  @json.parse(
    (
      #|{"request_fields":["resource","version"],"response_fields":["resource","version"],"identity":["resource","version"],"cardinality":"one"}
    ),
  )
}

///|
fn content_fixture_capacity() -> Json raise {
  @json.parse(
    (
      #|{"version":"actql-lookup-capacity/0.1","completeness":"complete_per_requested_key","max_rows_per_key":1,"max_pages_per_request":2,"max_response_bytes_per_page":4096}
    ),
  )
}

///|
fn content_fixture_carriers(
  profile? : Json,
  request? : Json,
  response? : Json,
  correlation? : Json?,
  capacity? : Json?,
  acquisition? : String = "fetch",
  authority? : String = "read_content",
  extension? : Bool = false,
) -> CarrierSchemas raise {
  // Keep fallible fixture construction in the ordinary function body. The
  // selected Native C backend mis-types early returns from default arguments.
  let profile = match profile {
    Some(value) => value
    None => content_fixture_profile()
  }
  let request = match request {
    Some(value) => value
    None => content_fixture_request()
  }
  let response = match response {
    Some(value) => value
    None => content_fixture_response()
  }
  let correlation = match correlation {
    Some(value) => value
    None => Some(content_fixture_correlation())
  }
  let capacity = match capacity {
    Some(value) => value
    None => Some(content_fixture_capacity())
  }
  let bodies = value_bodies("{\"type\":\"number\",\"nullable\":false}")
  bodies["request_schema"] = request
  bodies["carrier_schema"] = response
  // Seal only the authored schema declaration. This is not an expected runtime
  // output identity generated from the implementation under test.
  let envelope = @json.parse(
    (
      #|{"schema":"actql.contract/0.1","id":"carrier_schema","kind":"carrier_schema","version":"external"}
    ),
  )
  guard envelope is Object(fields) else { abort("fixture") }
  fields["body"] = response
  let sealed_schema = @json.parse(sealed_fixture(envelope, "cid"))
  guard sealed_schema is Object(fields) else { abort("fixture") }
  if profile is Object(fields2) &&
    fields2.get("content_schema_contract_cid") == Some(Json::string("@schema")) {
    fields2["content_schema_contract_cid"] = fields["cid"]
  }
  let facts : Map[String, Json] = Map([("file_content", profile)])
  if capacity is Some(value) {
    facts["lookup_capacity"] = value
  }
  if extension {
    facts["uninterpreted"] = Json::object(Map([]))
  }
  bodies["carrier_facts"] = Json::object(facts)
  let contents = reference_fixture(
    complete_view=true,
    acquisition_kind=acquisition,
    acquisition_authority=authority,
    bodies~,
    policy_body=Some(policy_body_fixture("unknown")),
    path=["view", "acquisition", "correlation"],
    replacement=correlation,
  )
  let references = check_catalog_references(contents, reference_caps()).unwrap()
  let values = check_protocol_value_contracts(
    check_source_data_policies(references, policy_limits()).unwrap(),
    protocol_value_limits(),
  ).unwrap()
  let shapes = check_source_view_shapes(values, {
    max_views: 10,
    max_work: 100000,
  }).unwrap()
  check_carrier_schemas(
    check_source_read_modes(shapes, 100000).unwrap(),
    carrier_limits(),
  ).unwrap()
}

///|
test "strict content profile is admitted by its exact SourceView and Catalog owners" {
  let carriers = content_fixture_carriers()
  let requests = check_source_request_contracts(carriers, request_limits()).unwrap()
  let view = source_request_at(requests, 0).unwrap()
  let profile = source_request_file_content(view).unwrap()
  assert_eq(
    file_content_scope_cid(profile),
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  assert_eq(
    file_content_version_capability_cid(profile),
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  let path = @decode.cursor_path(file_content_source(profile))
  assert_eq(path[path.length() - 1], @source.Key("file_content"))
  assert_true(source_request_file_listing(view) is None)
  let values = source_view_shape_values(
    read_mode_shapes(carrier_schema_modes(carriers)),
  )
  let facts = check_lookup_capacities(
    data_policy_references(value_contract_policies(values)),
    { max_work: 100000, max_facts: 10, },
  ).unwrap()
  let envelope = lookup_facts_envelope(lookup_facts_at(facts, 0).unwrap())
  assert_eq(file_content_facts_cid(profile), contract_identity(envelope).2)
  let dependencies = check_content_body_dependencies(
    requests, view, facts, envelope,
  ).unwrap()
  assert_true(catalog_body_admission(dependencies) is ContentFactsBody(_, _))
  assert_eq(catalog_body_dependency_count(dependencies), 1)
  assert_true(
    check_lookup_body_dependencies(facts, envelope)
    is Err(UnsupportedBodyGrammar("carrier_facts")),
  )
  let other = check_source_request_contracts(
    content_fixture_carriers(),
    request_limits(),
  ).unwrap()
  assert_true(
    check_content_body_dependencies(other, view, facts, envelope)
    is Err(ForeignEnvironment),
  )
  let (work, roles, _) = source_request_usage(requests)
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
    is Err(issue) &&
    issue.kind == WorkLimit,
  )
}

///|
test "strict content profile rejects missing version ability and altered representation" {
  for
    (path, replacement) in [
      (["version"], Some(Json::string("actql-file-content/" + "9.9"))),
      (["kind"], Some(Json::string("file_listing"))),
      (["admitted_scope_contract_cid"], Some(Json::string("bucket-path"))),
      (
        ["content_schema_contract_cid"],
        Some(
          Json::string(
            "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          ),
        ),
      ),
      (["version_capability"], None),
      (["version_capability", "required_nonnull"], Some(Json::boolean(false))),
      (["version_capability", "contract_cid"], Some(Json::string("latest"))),
      (["representation"], Some(Json::string("decompressed"))),
      (["extra"], Some(Json::boolean(true))),
    ] {
    let profile = content_fixture_profile()
    mutate_reference_fixture(profile, path, 0, replacement)
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(profile~),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileContentProfile,
    )
  }
}

///|
test "strict content profile requires nonnull resource/version and issued content roles" {
  for name in ["resource", "version", "content"] {
    let original = content_fixture_response()
    guard original is Object(object) && object["fields"] is Object(fields) else {
      abort("fixture")
    }
    fields[name] = Json::object(
      Map([
        ("contract", fields[name]),
        ("presence", Json::string("conditional")),
      ]),
    )
    let response = Json::object(
      Map([
        ("version", Json::string("actql-relation-schema/0.1")),
        ("fields", Json::object(fields)),
      ]),
    )
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(response~),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileContentProfile,
    )
  }
  for
    (path, replacement) in [
      (["fields", "version", "nullable"], Json::boolean(true)),
      (["fields", "resource", "resource_kind"], Json::string("foreign")),
    ] {
    let request = content_fixture_request()
    mutate_reference_fixture(request, path, 0, Some(replacement))
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(request~),
        request_limits(),
      )
      is Err(_),
    )
    let response = content_fixture_response()
    mutate_reference_fixture(response, path, 0, Some(replacement))
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(response~),
        request_limits(),
      )
      is Err(_),
    )
  }
  for replacement in [Json::boolean(true)] {
    let response = content_fixture_response()
    mutate_reference_fixture(
      response,
      ["fields", "content", "nullable"],
      0,
      Some(replacement),
    )
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(response~),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileContentProfile,
    )
  }
  let response = content_fixture_response()
  mutate_reference_fixture(
    response,
    ["fields", "content"],
    0,
    Some(@json.parse("{\"type\":\"string\",\"nullable\":false}")),
  )
  assert_true(
    check_source_request_contracts(
      content_fixture_carriers(response~),
      request_limits(),
    )
    is Err(issue) &&
    issue.kind == InvalidFileContentProfile,
  )
}

///|
test "strict content profile cannot weaken exact cardinality completeness or key correspondence" {
  for cardinality in ["zero_or_one", "zero_or_many", "one_or_many"] {
    let correlation = content_fixture_correlation()
    mutate_reference_fixture(
      correlation,
      ["cardinality"],
      0,
      Some(Json::string(cardinality)),
    )
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(correlation=Some(correlation)),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileContentProfile,
    )
  }
  for
    (path, replacement) in [
      (["completeness"], Json::string("hard_limit_only")),
      (["max_rows_per_key"], Json::number(2)),
    ] {
    let capacity = content_fixture_capacity()
    mutate_reference_fixture(capacity, path, 0, Some(replacement))
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(capacity=Some(capacity)),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileContentProfile,
    )
  }
  for
    correlation in [
      None,
      Some(
        @json.parse(
          "{\"request_fields\":[\"resource\"],\"response_fields\":[\"resource\"],\"identity\":[\"resource\"],\"cardinality\":\"one\"}",
        ),
      ),
    ] {
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(correlation~),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileContentProfile,
    )
  }
  assert_true(
    check_source_request_contracts(
      content_fixture_carriers(capacity=None),
      request_limits(),
    )
    is Err(issue) &&
    issue.kind == InvalidFileContentProfile,
  )
}

///|
test "unknown facts are not silently admitted with a valid content component" {
  let carriers = content_fixture_carriers(extension=true)
  let requests = check_source_request_contracts(carriers, request_limits()).unwrap()
  let values = source_view_shape_values(
    read_mode_shapes(carrier_schema_modes(carriers)),
  )
  let facts = check_lookup_capacities(
    data_policy_references(value_contract_policies(values)),
    { max_work: 100000, max_facts: 10, },
  ).unwrap()
  let envelope = lookup_facts_envelope(lookup_facts_at(facts, 0).unwrap())
  assert_true(
    check_content_body_dependencies(
      requests,
      source_request_at(requests, 0).unwrap(),
      facts,
      envelope,
    )
    is Err(UnsupportedBodyGrammar("carrier_facts")),
  )
}

///|
test "strict content keys preserve authored correspondence order without weakening the role set" {
  let reversed = @json.parse(
    (
      #|{"request_fields":["version","resource"],"response_fields":["version","resource"],"identity":["version","resource"],"cardinality":"one"}
    ),
  )
  let requests = check_source_request_contracts(
    content_fixture_carriers(correlation=Some(reversed)),
    request_limits(),
  ).unwrap()
  let view = source_request_at(requests, 0).unwrap()
  assert_true(source_request_file_content(view) is Some(_))
  let correlation = source_request_correlation(view).unwrap()
  assert_eq(
    source_correlation_pair_at(correlation, 0).unwrap().request.name,
    "version",
  )
  assert_eq(
    source_correlation_identity_at(correlation, 0).unwrap().name,
    "version",
  )
  let request = content_fixture_request()
  mutate_reference_fixture(
    request,
    ["fields", "other_version"],
    0,
    Some(@json.parse("{\"type\":\"string\",\"nullable\":false}")),
  )
  let wrong = content_fixture_correlation()
  mutate_reference_fixture(
    wrong,
    ["request_fields"],
    0,
    Some(@json.parse("[\"resource\",\"other_version\"]")),
  )
  assert_true(
    check_source_request_contracts(
      content_fixture_carriers(request~, correlation=Some(wrong)),
      request_limits(),
    )
    is Err(issue) &&
    issue.kind == InvalidFileContentProfile,
  )
}

///|
test "malformed content profiles and non-fetch views cannot claim strict capture" {
  for profile in [Json::null(), Json::array([]), Json::string("file_content")] {
    assert_true(
      check_source_request_contracts(
        content_fixture_carriers(profile~),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileContentProfile,
    )
  }
  // A search is permitted to declare generic correlation, but that does not
  // turn it into a strict file-content fetch capability.
  assert_true(
    check_source_request_contracts(
      content_fixture_carriers(acquisition="search"),
      request_limits(),
    )
    is Err(issue) &&
    issue.kind == InvalidFileContentProfile,
  )
  assert_true(
    check_source_request_contracts(
      content_fixture_carriers(authority="read_metadata"),
      request_limits(),
    )
    is Err(issue) &&
    issue.kind == InvalidFileContentProfile,
  )
  assert_true(
    check_source_request_contracts(
      content_fixture_carriers(authority="read_binary"),
      request_limits(),
    )
    is Ok(_),
  )
}
