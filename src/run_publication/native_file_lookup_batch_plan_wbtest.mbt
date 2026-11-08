///|
fn native_batch_fixture_keys(tuples : String) -> PublicationContract {
  let body = "{\"key_roles\":[{\"request_role\":\"n\",\"value_contract\":{\"nullable\":false,\"type\":\"number\"}}],\"request_schema_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"source_view_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"tuples\":[[2],[10]],\"version\":\"actql-lookup-key-set/0.1\"}"
  seal_publication_contract(
    "request_key_set",
    body.replace(old="[[2],[10]]", new=tuples),
    16384,
    1024,
    20,
  ).unwrap()
}

///|
fn native_batch_fixture_transport() -> PublicationContract raise {
  let writer = @encode.writer(100, 10, 4)
  @encode.begin_object(writer)
  @encode.end_object(writer)
  issue_native_file_lookup_transport(
    native_transport_fixture(),
    @encode.finish_document(writer),
    16384,
    1024,
    20,
  ).unwrap()
}

///|
test "Native singleton batch Plan binds exact original key set transport and canonical partition" {
  let keys = native_batch_fixture_keys("[[2],[10]]")
  let transport = native_batch_fixture_transport()
  let plan = issue_native_file_lookup_batch_plan(
    "sha256:" + "e".repeat(64),
    keys,
    transport,
    16384,
    1024,
    20,
  ).unwrap()
  // Independent Python hashlib over the authored canonical preimages.
  assert_eq(
    plan.identity,
    "sha256:54c1c0073c963e7ffea60b2b3da5e7cc357ca760dce30ba53149e120dcd4f5dd",
  )
  assert_true(
    plan.wire.contains(
      "\"batches\":[{\"batch_index\":0,\"key_indices\":[0]},{\"batch_index\":1,\"key_indices\":[1]}]",
    ),
  )
  assert_eq(
    admit_publication_contract(
      "native_file_lookup_batch_plan",
      plan.wire,
      16384,
      1024,
      20,
    ).unwrap().identity,
    plan.identity,
  )
}

///|
test "Native singleton batch Plan refuses reordered missing repeated and noncanonical incoming batches" {
  let plan = issue_native_file_lookup_batch_plan(
    "sha256:" + "e".repeat(64),
    native_batch_fixture_keys("[[2],[10]]"),
    native_batch_fixture_transport(),
    16384,
    1024,
    20,
  ).unwrap()
  let body = @json.stringify_value(
    @json.object_without_field(plan.value, "self_cid").unwrap(),
    16384,
    1024,
    20,
  )
  for
    (old, replacement) in [
      ("\"key_indices\":[0]", "\"key_indices\":[1]"),
      ("\"key_indices\":[1]", "\"key_indices\":[0]"),
      ("\"key_indices\":[0]", "\"key_indices\":[]"),
      ("\"key_indices\":[0]", "\"key_indices\":[0,1]"),
      ("\"batch_index\":1", "\"batch_index\":2"),
    ] {
    assert_true(
      seal_publication_contract(
        "native_file_lookup_batch_plan",
        body.replace(old~, new=replacement),
        16384,
        1024,
        20,
      )
      is Err(_),
    )
  }
  assert_true(
    admit_publication_contract(
      "native_file_lookup_batch_plan",
      " " + plan.wire,
      16384,
      1024,
      20,
    )
    is Err(InvalidWire),
  )
}

///|
test "Native zero-key batch Plan retains originals with no physical call and refuses a foreign purpose" {
  let keys = native_batch_fixture_keys("[]")
  let transport = native_batch_fixture_transport()
  let plan = issue_native_file_lookup_batch_plan(
    "sha256:" + "e".repeat(64),
    keys,
    transport,
    16384,
    1024,
    20,
  ).unwrap()
  assert_true(plan.wire.contains("\"batches\":[]"))
  assert_true(
    issue_native_file_lookup_batch_plan(
      "sha256:" + "e".repeat(64),
      keys,
      plan,
      16384,
      1024,
      20,
    )
    is Err(_),
  )
  assert_true(
    issue_native_file_lookup_batch_plan(
      "foreign", keys, transport, 16384, 1024, 20,
    )
    is Err(_),
  )
  assert_true(
    issue_native_file_lookup_batch_plan(
      "sha256:" + "e".repeat(64),
      keys,
      transport,
      1,
      1024,
      20,
    )
    is Err(_),
  )
}
