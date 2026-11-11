///|
fn file_listing_fixture_profile() -> Json raise {
  @json.parse(
    (
      #|{"version":"actql-file-list/0.1","kind":"file_listing","selectable":["paths","glob"],"allow_unfiltered_listing":false,"admitted_scope_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","listing_schema_contract_cid":"@schema","max_listing_items":5,"max_listing_pages":3,"max_examined_items":9,"version_capability":{"contract_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","required_nonnull":true}}
    ),
  )
}

///|
fn file_listing_fixture_schema() -> Json raise {
  @json.parse(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"record","nullable":false},"version":{"type":"string","nullable":false},"name":{"type":"string","nullable":false},"path":{"type":"string","nullable":true},"media_type":{"type":"string","nullable":true},"size_bytes":{"type":"number","nullable":true},"modified_at":{"type":"timestamp","nullable":true}}}
    ),
  )
}

///|
fn file_listing_fixture_carriers(
  profile : Json?,
  schema? : Json,
  request? : Json? = None,
  extension? : Bool = false,
) -> CarrierSchemas raise {
  let schema = match schema {
    Some(value) => value
    None => file_listing_fixture_schema()
  }
  let bodies = value_bodies("{\"type\":\"number\",\"nullable\":false}")
  bodies["request_schema"] = @json.parse(
    "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"paths\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"string\",\"nullable\":false}},\"glob\":{\"type\":\"string\",\"nullable\":true}}}",
  )
  if request is Some(value) {
    bodies["request_schema"] = value
  }
  bodies["carrier_schema"] = schema
  let envelope = @json.parse(
    (
      #|{"schema":"actql.contract/0.1","id":"carrier_schema","kind":"carrier_schema","version":"external"}
    ),
  )
  guard envelope is Object(envelope_fields) else { abort("fixture") }
  envelope_fields["body"] = schema
  let sealed_envelope = @json.parse(sealed_fixture(envelope, "cid"))
  guard sealed_envelope is Object(sealed_fields) else { abort("fixture") }
  let facts = Json::object(Map([]))
  if extension {
    guard facts is Object(fields) else { abort("fixture") }
    fields["uninterpreted"] = Json::object(Map([]))
  }
  if profile is Some(profile) {
    guard profile is Object(fields) else {
      guard facts is Object(facts_fields) else { abort("fixture") }
      facts_fields["file_listing"] = profile
      return file_listing_fixture_admit(bodies, facts)
    }
    if fields.get("listing_schema_contract_cid") ==
      Some(Json::string("@schema")) {
      fields["listing_schema_contract_cid"] = sealed_fields["cid"]
    }
    guard facts is Object(facts_fields) else { abort("fixture") }
    facts_fields["file_listing"] = profile
  }
  file_listing_fixture_admit(bodies, facts)
}

///|
test "File-list Request declares two nullable alternatives with nonnull path members" {
  for
    text in [
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"glob\":{\"type\":\"string\",\"nullable\":true}}}",
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"paths\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}},\"glob\":{\"type\":\"string\",\"nullable\":true}}}",
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"paths\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"string\",\"nullable\":true}},\"glob\":{\"type\":\"string\",\"nullable\":true}}}",
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"paths\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":false}},\"glob\":{\"type\":\"string\",\"nullable\":true}}}",
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"paths\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"string\",\"nullable\":false}},\"glob\":{\"type\":\"number\",\"nullable\":true}}}",
    ] {
    let carriers = file_listing_fixture_carriers(
      Some(file_listing_fixture_profile()),
      request=Some(@json.parse(text)),
    )
    assert_true(
      check_source_request_contracts(carriers, request_limits()) is Err(issue) &&
      issue.kind == InvalidFileListProfile,
    )
  }
}

///|
fn file_listing_fixture_admit(
  bodies : Map[String, Json],
  facts : Json,
) -> CarrierSchemas raise {
  bodies["carrier_facts"] = facts
  let contents = reference_fixture(
    complete_view=true,
    bodies~,
    policy_body=Some(policy_body_fixture("unknown")),
  )
  let refs = check_catalog_references(contents, reference_caps()).unwrap()
  let values = check_protocol_value_contracts(
    check_source_data_policies(refs, policy_limits()).unwrap(),
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
test "common listing ceiling retains the admitted profile and Host policy" {
  let carriers = file_listing_fixture_carriers(
    Some(file_listing_fixture_profile()),
  )
  let requests = check_source_request_contracts(carriers, request_limits()).unwrap()
  let profile = source_request_file_listing(
    source_request_at(requests, 0).unwrap(),
  ).unwrap()
  let rows = resolve_file_listing_rows(profile, None, "file-listing:owned").unwrap()
  assert_true(physical_equal(file_listing_rows_profile(rows), profile))
  assert_true(file_listing_rows_policy(rows) is None)
  assert_eq(file_listing_rows_maximum(rows), 5L)
  let maximums = file_listing_limit_candidates(file_listing_rows_profile(rows))
  maximums.clear()
  assert_eq(file_listing_rows_maximum(rows), 5L)
  assert_eq(file_listing_limit_candidates(profile).length(), 3)
  let policy_wire = capacity_body().replace(
    old="\"max_effect_items\":1,",
    new="\"max_effect_items\":1,\"max_file_listing_items\":2,",
  )
  let policy = capacity_policy(
    read_capacity(capacity_wire("{\"capacity\":" + policy_wire + "}"), {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 4,
    }).unwrap(),
  )
  let limited = resolve_file_listing_rows(
    profile,
    Some(policy),
    "file-listing:owned",
  ).unwrap()
  assert_true(
    physical_equal(file_listing_rows_policy(limited).unwrap(), policy),
  )
  assert_true(physical_equal(file_listing_rows_profile(limited), profile))
  assert_eq(file_listing_rows_maximum(limited), 2L)
  // Generic Relation output ceiling one is not this acquisition's row scope.
  let generic_only = capacity_policy(
    read_capacity(capacity_wire("{\"capacity\":" + capacity_body() + "}"), {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 4,
    }).unwrap(),
  )
  assert_eq(
    file_listing_rows_maximum(
      resolve_file_listing_rows(
        profile,
        Some(generic_only),
        "file-listing:owned",
      ).unwrap(),
    ),
    5L,
  )
  assert_true(resolve_file_listing_rows(profile, None, "") is Err(Unresolved))
  let different = resolve_file_listing_rows(profile, None, "file-listing:other").unwrap()
  assert_true(
    @bound_wire.limit_cid(file_listing_rows_claim(rows)) !=
    @bound_wire.limit_cid(file_listing_rows_claim(different)),
  )
}

///|
test "File listing body dependency admission refuses unknown facts without dropping them" {
  let carriers = file_listing_fixture_carriers(
    Some(file_listing_fixture_profile()),
    extension=true,
  )
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
    check_listing_body_dependencies(
      requests,
      source_request_at(requests, 0).unwrap(),
      facts,
      envelope,
    )
    is Err(UnsupportedBodyGrammar("carrier_facts")),
  )
}

///|
test "File listing declaration retains exact Catalog facts and candidates without count proof" {
  let carriers = file_listing_fixture_carriers(
    Some(file_listing_fixture_profile()),
  )
  let checked = check_source_request_contracts(carriers, request_limits()).unwrap()
  let values = source_view_shape_values(
    read_mode_shapes(carrier_schema_modes(carriers)),
  )
  let references = data_policy_references(value_contract_policies(values))
  let facts = check_lookup_capacities(references, {
    max_work: 100000,
    max_facts: 10,
  }).unwrap()
  let envelope = lookup_facts_envelope(lookup_facts_at(facts, 0).unwrap())
  let view = source_request_at(checked, 0).unwrap()
  let dependencies = check_listing_body_dependencies(
    checked, view, facts, envelope,
  ).unwrap()
  assert_true(catalog_body_admission(dependencies) is ListingFactsBody(_, _))
  assert_eq(catalog_body_dependency_count(dependencies), 1)
  assert_true(
    check_lookup_body_dependencies(facts, envelope)
    is Err(UnsupportedBodyGrammar("carrier_facts")),
  )
  let foreign_carriers = file_listing_fixture_carriers(
    Some(file_listing_fixture_profile()),
  )
  let foreign = check_source_request_contracts(
    foreign_carriers,
    request_limits(),
  ).unwrap()
  assert_true(
    check_listing_body_dependencies(foreign, view, facts, envelope)
    is Err(ForeignEnvironment),
  )
  let profile = source_request_file_listing(
    source_request_at(checked, 0).unwrap(),
  ).unwrap()
  assert_true(file_listing_accepts(profile, "paths"))
  assert_true(file_listing_accepts(profile, "glob"))
  assert_false(file_listing_accepts(profile, "all"))
  assert_false(file_listing_accepts(profile, "unknown"))
  let limits = file_listing_limit_candidates(profile)
  assert_eq(limits, [
    ("max_examined_items", 9L),
    ("max_listing_items", 5L),
    ("max_listing_pages", 3L),
  ])
  limits.clear()
  assert_eq(file_listing_limit_candidates(profile).length(), 3)
  assert_true(file_listing_facts_cid(profile).has_prefix("sha256:"))
  let path = @decode.cursor_path(file_listing_source(profile))
  assert_eq(path[path.length() - 1], @source.Key("file_listing"))
  let (work, roles, _) = source_request_usage(checked)
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
  let plain = check_source_request_contracts(
    file_listing_fixture_carriers(None),
    request_limits(),
  ).unwrap()
  assert_true(
    source_request_file_listing(source_request_at(plain, 0).unwrap()) is None,
  )
}

///|
test "File listing declaration rejects malformed profiles instead of inferring roles" {
  let changes : Array[(Array[String], Json?)] = [
    (["kind"], Some(Json::string("file_content"))),
    (["version"], Some(Json::string("actql-file-list/" + "9.9"))),
    (["selectable"], Some(@json.parse("[\"paths\",\"paths\"]"))),
    (["selectable"], Some(@json.parse("[\"unknown\"]"))),
    (["allow_unfiltered_listing"], None),
    (["allow_unfiltered_listing"], Some(Json::string("true"))),
    (["max_listing_items"], Some(Json::number(-1))),
    (["max_listing_items"], Some(Json::number(0))),
    (["max_listing_pages"], Some(Json::number(0))),
    (["maximum_path_length"], Some(Json::number(1.5))),
    (
      ["listing_schema_contract_cid"],
      Some(
        Json::string(
          "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        ),
      ),
    ),
    (["extra"], Some(Json::boolean(true))),
    (["version_capability", "required_nonnull"], Some(Json::null())),
  ]
  for (path, replacement) in changes {
    let profile = file_listing_fixture_profile()
    mutate_reference_fixture(profile, path, 0, replacement)
    let carriers = file_listing_fixture_carriers(Some(profile))
    assert_true(
      check_source_request_contracts(carriers, request_limits()) is Err(e) &&
      e.kind == InvalidFileListProfile,
    )
  }
  for malformed in [Json::null(), Json::array([]), Json::string("listing")] {
    let carriers = file_listing_fixture_carriers(Some(malformed))
    assert_true(
      check_source_request_contracts(carriers, request_limits()) is Err(e) &&
      e.kind == InvalidFileListProfile,
    )
  }
}

///|
test "File listing declaration enforces fixed required roles independently from nullable" {
  for
    (path, replacement) in [
      (["fields", "version", "nullable"], Json::boolean(true)),
      (["fields", "resource", "resource_kind"], Json::string("foreign")),
      (["fields", "size_bytes", "type"], Json::string("string")),
      (["fields", "name", "nullable"], Json::boolean(true)),
    ] {
    let schema = file_listing_fixture_schema()
    mutate_reference_fixture(schema, path, 0, Some(replacement))
    let carriers = file_listing_fixture_carriers(
      Some(file_listing_fixture_profile()),
      schema~,
    )
    assert_true(
      check_source_request_contracts(carriers, request_limits()) is Err(e) &&
      e.kind == InvalidFileListProfile,
    )
  }
  let schema = file_listing_fixture_schema()
  mutate_reference_fixture(
    schema,
    ["fields", "version", "nullable"],
    0,
    Some(Json::boolean(true)),
  )
  let profile = file_listing_fixture_profile()
  mutate_reference_fixture(
    profile,
    ["version_capability", "required_nonnull"],
    0,
    Some(Json::boolean(false)),
  )
  assert_true(
    check_source_request_contracts(
      file_listing_fixture_carriers(Some(profile), schema~),
      request_limits(),
    )
    is Ok(_),
  )
}

///|
fn native_file_listing_fixture_schema() -> Json raise {
  let schema = file_listing_fixture_schema()
  for
    (name, contract) in [
      ("size", ({ "type": "int64", "nullable": false } : Json)),
      ("modified_time", ({ "type": "timestamp", "nullable": false } : Json)),
    ] {
    mutate_reference_fixture(schema, ["fields", name], 0, Some(contract))
  }
  mutate_reference_fixture(
    schema,
    ["fields", "path", "nullable"],
    0,
    Some(Json::boolean(false)),
  )
  schema
}

///|
test "File listing admits the complete native metadata schema and stronger nonnull roles" {
  let schema = native_file_listing_fixture_schema()
  let carriers = file_listing_fixture_carriers(
    Some(file_listing_fixture_profile()),
    schema~,
  )
  let checked = check_source_request_contracts(carriers, request_limits()).unwrap()
  let profile = source_request_file_listing(
    source_request_at(checked, 0).unwrap(),
  ).unwrap()
  assert_true(file_listing_accepts(profile, "paths"))
  assert_true(file_listing_accepts(profile, "glob"))
  // Each full output contract was admitted by the existing Carrier Owner;
  // this profile retains its complete output-schema CID, not a seven-field CID.
  let seven = check_source_request_contracts(
    file_listing_fixture_carriers(Some(file_listing_fixture_profile())),
    request_limits(),
  ).unwrap()
  let old_profile = source_request_file_listing(
    source_request_at(seven, 0).unwrap(),
  ).unwrap()
  assert_true(
    file_listing_facts_cid(profile) != file_listing_facts_cid(old_profile),
  )
  let (work, roles, _) = source_request_usage(checked)
  let (old_work, _, _) = source_request_usage(seven)
  assert_true(work > old_work)
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
  for name in ["path", "media_type", "size_bytes", "modified_at"] {
    let refined = file_listing_fixture_schema()
    mutate_reference_fixture(
      refined,
      ["fields", name, "nullable"],
      0,
      Some(Json::boolean(false)),
    )
    assert_true(
      check_source_request_contracts(
        file_listing_fixture_carriers(
          Some(file_listing_fixture_profile()),
          schema=refined,
        ),
        request_limits(),
      )
      is Ok(_),
    )
  }
}

///|
test "Native listing metadata cannot replace canonical roles or their exact schema identity" {
  for
    name in [
      "resource", "version", "name", "path", "media_type", "size_bytes", "modified_at",
    ] {
    let schema = native_file_listing_fixture_schema()
    mutate_reference_fixture(schema, ["fields", name], 0, None)
    assert_true(
      check_source_request_contracts(
        file_listing_fixture_carriers(
          Some(file_listing_fixture_profile()),
          schema~,
        ),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileListProfile,
    )
  }
  for
    (name, wrong) in [
      ("size_bytes", "int64"),
      ("modified_at", "string"),
      ("path", "number"),
      ("media_type", "number"),
    ] {
    let schema = native_file_listing_fixture_schema()
    mutate_reference_fixture(
      schema,
      ["fields", name, "type"],
      0,
      Some(Json::string(wrong)),
    )
    assert_true(
      check_source_request_contracts(
        file_listing_fixture_carriers(
          Some(file_listing_fixture_profile()),
          schema~,
        ),
        request_limits(),
      )
      is Err(issue) &&
      issue.kind == InvalidFileListProfile,
    )
  }
  let schema = native_file_listing_fixture_schema()
  let wrong_profile = file_listing_fixture_profile()
  mutate_reference_fixture(
    wrong_profile,
    ["listing_schema_contract_cid"],
    0,
    Some(Json::string("sha256:" + "c".repeat(64))),
  )
  assert_true(
    check_source_request_contracts(
      file_listing_fixture_carriers(Some(wrong_profile), schema~),
      request_limits(),
    )
    is Err(issue) &&
    issue.kind == InvalidFileListProfile,
  )
}
