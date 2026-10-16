///|
// Static synthetic Catalog originals only. These fixtures do not install a
// mailbox/channel, resolve an identifier or issue an execution target/grant.
fn published_command_fixture(binding : Json?) -> CatalogContents raise {
  let target : Json = { "cardinality": "single", "resource_kind": "mailbox" }
  if binding is Some(value) {
    guard target is Object(fields) else { abort("target fixture") }
    fields["binding"] = value
  }
  let command = command_target_fixture(
    "example",
    "command:mailbox.send.v1",
    canonical_fixture(target),
  )
  let catalog = catalog_fixture("example", [], commands=[command])
  check_catalog_contents(
    catalog_environment([catalog], [], commands=[command]),
    caps(),
  ).unwrap()
}

///|
fn published_command_limits() -> @value_contract.Limits {
  { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, }
}

///|
fn published_identifier_fixture() -> Json {
  {
    "kind": "identifier",
    "identity_contract": {
      "type": "string",
      "nullable": false,
      "max_utf8_bytes": 64,
    },
  }
}

///|
test "published Command installation mode retains exact original Catalog and environment" {
  let contents = published_command_fixture(Some({ "kind": "installation" }))
  let bound = select_published_command_binding(
    contents,
    "command:mailbox.send.v1",
    published_command_limits(),
    1000,
  ).unwrap()
  assert_eq(published_command_binding_mode(bound), Installation)
  assert_true(published_command_binding_identifier_type(bound) is None)
  assert_eq(published_command_binding_usage(bound), (2, 12))
  assert_eq(published_command_binding_work(bound), 16)
  let target = published_command_binding_target(bound)
  assert_eq(command_target_id(target), "command:mailbox.send.v1")
  assert_eq(command_target_resource_kind(target), "mailbox")
  assert_true(
    physical_equal(
      command_target_catalog(target),
      catalog_at(contents, 0).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      member_environment(command_target_member(target)),
      contract_registry_environment(catalog_registry(contents)),
    ),
  )
}

///|
test "published Command identifier mode keeps the complete checked original key domain" {
  let contents = published_command_fixture(Some(published_identifier_fixture()))
  let bound = select_published_command_binding(
    contents,
    "command:mailbox.send.v1",
    published_command_limits(),
    1000,
  ).unwrap()
  assert_eq(published_command_binding_mode(bound), Identifier)
  let identifier = published_command_binding_identifier_type(bound).unwrap()
  assert_true(!identifier.nullable)
  guard identifier.shape is @value_contract.Text(parameters) else {
    abort("original checked string domain")
  }
  assert_eq(parameters.max_utf8_bytes, Some(64L))
  assert_eq(published_command_binding_usage(bound), (3, 16))
  assert_eq(published_command_binding_work(bound), 21)
}

///|
test "absent Command binding keeps legacy field meaning and cannot become an installation default" {
  let old = published_command_fixture(None)
  assert_true(select_command_target(old, "command:mailbox.send.v1", 2) is Ok(_))
  assert_true(
    select_published_command_binding(
      old,
      "command:mailbox.send.v1",
      published_command_limits(),
      1000,
    )
    is Err(MissingBinding),
  )
  let bindings : Array[Json] = [
    { "kind": "installation" },
    published_identifier_fixture(),
  ]
  for binding in bindings {
    let contents = published_command_fixture(Some(binding))
    assert_true(
      select_command_target(contents, "command:mailbox.send.v1", 1000)
      is Err(InvalidCommand("command:mailbox.send.v1")),
    )
  }
}

///|
test "published Command binding is closed and malformed presence never becomes absence" {
  let bindings : Array[Json] = [
    Json::null(),
    Json::boolean(false),
    {},
    { "kind": "other" },
    { "kind": 1 },
    { "kind": "installation", "extra": true },
    { "kind": "installation", "identity_contract": Json::null() },
    { "kind": "identifier" },
    {
      "kind": "identifier",
      "identity_contract": { "type": "string", "nullable": false },
      "extra": false,
    },
  ]
  for binding in bindings {
    let contents = published_command_fixture(Some(binding))
    assert_true(
      select_published_command_binding(
        contents,
        "command:mailbox.send.v1",
        published_command_limits(),
        1000,
      )
      is Err(InvalidBinding),
    )
  }
}

///|
test "published Command identifiers require the existing checked nonnull KeyComparable domain" {
  let contracts : Array[Json] = [
    { "type": "string", "nullable": true },
    { "type": "json", "nullable": false },
    {
      "type": "vector",
      "nullable": false,
      "dimensions": 2,
      "element_type": "f32",
    },
    {
      "type": "object",
      "nullable": false,
      "additional_properties": false,
      "fields": {},
    },
    {
      "type": "array",
      "nullable": false,
      "items": { "type": "string", "nullable": false },
    },
  ]
  for contract in contracts {
    let contents = published_command_fixture(
      Some({ "kind": "identifier", "identity_contract": contract }),
    )
    assert_true(
      select_published_command_binding(
        contents,
        "command:mailbox.send.v1",
        published_command_limits(),
        1000,
      )
      is Err(UnsupportedIdentifierDomain),
    )
  }
  let malformed : Array[Json] = [Json::null(), {}, { "type": "string" }]
  for contract in malformed {
    let contents = published_command_fixture(
      Some({ "kind": "identifier", "identity_contract": contract }),
    )
    assert_true(
      select_published_command_binding(
        contents,
        "command:mailbox.send.v1",
        published_command_limits(),
        1000,
      )
      is Err(InvalidIdentifierType(_)),
    )
  }
}

///|
test "published Command selection budgets original walk, declaration and every checked type" {
  // The original Catalog walk exhausts two units before this declaration.
  // A malformed child cannot trigger type interpretation with no work left.
  let exhausted = published_command_fixture(
    Some({ "kind": "identifier", "identity_contract": Json::null() }),
  )
  assert_true(
    select_published_command_binding(
      exhausted,
      "command:mailbox.send.v1",
      published_command_limits(),
      2,
    )
    is Err(WorkLimit),
  )
  let cases : Array[(Json, Int, Int, Int)] = [
    ({ "kind": "installation" }, 2, 12, 16),
    (published_identifier_fixture(), 3, 16, 21),
  ]
  for (binding, nodes, text, work) in cases {
    let contents = published_command_fixture(Some(binding))
    let exact : @value_contract.Limits = {
      max_nodes: nodes,
      max_depth: 1,
      max_text_bytes: text,
    }
    assert_true(
      select_published_command_binding(
        contents, "command:mailbox.send.v1", exact, work,
      )
      is Ok(_),
    )
    for
      (limits, remaining_work) in [
        (exact, work - 1),
        ({ ..exact, max_nodes: nodes - 1, }, work),
        ({ ..exact, max_text_bytes: text - 1, }, work),
        ({ ..exact, max_depth: 0, }, work),
      ] {
      assert_true(
        select_published_command_binding(
          contents, "command:mailbox.send.v1", limits, remaining_work,
        )
        is Err(WorkLimit),
      )
    }
    for
      limits in [
        { ..exact, max_nodes: -1, },
        { ..exact, max_depth: -1, },
        { ..exact, max_text_bytes: -1, },
      ] {
      assert_true(
        select_published_command_binding(
          contents, "command:mailbox.send.v1", limits, work,
        )
        is Err(InvalidLimit),
      )
    }
    assert_true(
      select_published_command_binding(
        contents, "command:mailbox.send.v1", exact, -1,
      )
      is Err(InvalidLimit),
    )
  }
}

///|
test "equal Command self CIDs preserve distinct original environments and exact reference lookup" {
  let original = published_command_fixture(Some({ "kind": "installation" }))
  let copy = published_command_fixture(Some({ "kind": "installation" }))
  let first = select_published_command_binding(
    original,
    "command:mailbox.send.v1",
    published_command_limits(),
    1000,
  ).unwrap()
  let second = select_published_command_binding(
    copy,
    "command:mailbox.send.v1",
    published_command_limits(),
    1000,
  ).unwrap()
  let a = published_command_binding_target(first)
  let b = published_command_binding_target(second)
  assert_eq(command_target_cid(a), command_target_cid(b))
  assert_true(
    !physical_equal(
      member_environment(command_target_member(a)),
      member_environment(command_target_member(b)),
    ),
  )
  assert_true(
    select_published_command_binding(
      original,
      "command:mailbox.other.v1",
      published_command_limits(),
      1000,
    )
    is Err(Command(MissingCommand("command:mailbox.other.v1"))),
  )
}
