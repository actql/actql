///|
test "every Catalog reference role retains its exact source member and target" {
  let contents = reference_fixture()
  let checked = check_catalog_references(contents, reference_caps()).unwrap()
  assert_true(physical_equal(reference_contents(checked), contents))
  let (work, count) = reference_usage(checked)
  assert_eq(count, 19)
  for i in 0..<count {
    let reference = catalog_reference_at(checked, i).unwrap()
    assert_true(
      physical_equal(
        catalog_reference_for_cursor(checked, reference_source(reference)).unwrap(),
        reference,
      ),
    )
    assert_true(
      catalog_reference_for_cursor(
        checked,
        member_body(reference_member(reference)),
      )
      is None,
    )
    assert_true(
      physical_equal(
        reference_catalog(reference),
        catalog_at(contents, 0).unwrap(),
      ),
    )
    let item = reference_member(reference)
    assert_true(
      @decode.tree_index(member_body(item), reference_source(reference))
      is Some(_),
    )
    let target = reference_contract(reference)
    assert_eq(contract_identity(target).0, contract_role(target))
    assert_true(
      physical_equal(
        member_environment(contract_member(target)),
        member_environment(item),
      ),
    )
  }
  assert_true(catalog_reference_at(checked, -1) is None)
  assert_true(catalog_reference_at(checked, count) is None)
  assert_true(
    check_catalog_references(contents, {
      max_work: work,
      max_references: count,
    })
    is Ok(_),
  )
  assert_true(
    check_catalog_references(contents, {
      max_work: work - 1,
      max_references: count,
    })
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    check_catalog_references(contents, {
      max_work: work,
      max_references: count - 1,
    })
    is Err({ kind: ReferenceLimit, .. }),
  )
  assert_true(
    check_catalog_references(contents, { max_work: -1, max_references: count, })
    is Err({ kind: InvalidLimits, .. }),
  )
  assert_true(
    check_catalog_references(reference_fixture(modes=10), reference_caps())
    is Ok(v) &&
    reference_usage(v).1 == 46,
  )
}

///|
test "every optional Catalog reference container rejects null rather than disappearing" {
  for
    path in [
      ["view", "acquisition", "batching"],
      ["view", "acquisition", "modes", "0", "checkpoint"],
      ["view", "acquisition", "modes", "0", "delivery"],
      ["view", "acquisition", "modes", "0", "delivery", "lease"],
      ["view", "request_processing", "data_handling"],
      ["view", "request_processing", "provider_execution_capability"],
      ["command", "idempotency", "key_schema"],
      ["command", "reconciliation"],
      ["command", "poll"],
      ["command", "cancel"],
    ] {
    assert_true(
      check_catalog_references(reference_fixture(path~), reference_caps())
      is Ok(_),
    )
    assert_true(
      check_catalog_references(
        reference_fixture(path~, replacement=Some(Json::null())),
        reference_caps(),
      )
      is Err({ kind: InvalidSlot, .. }),
    )
  }
}

///|
test "all nineteen reference slots reject wrong kind and preserve diagnostic cursor" {
  let baseline = check_catalog_references(reference_fixture(), reference_caps()).unwrap()
  let first = reference_contract(catalog_reference_at(baseline, 0).unwrap())
  let (id, version, cid) = contract_identity(first)
  let wrong = @json.parse(
    "{\"id\":\"" +
    id +
    "\",\"version\":\"" +
    version +
    "\",\"cid\":\"" +
    cid +
    "\"}",
  )
  // Independently enumerated locations, not generated from the product routes.
  for
    path in [
      ["view", "acquisition", "batching", "request_key_schema"],
      ["view", "acquisition", "batching", "batch_request_schema"],
      ["view", "acquisition", "batching", "response_key_schema"],
      ["view", "acquisition", "modes", "0", "checkpoint", "value_schema"],
      ["view", "acquisition", "modes", "0", "checkpoint", "expiration_schema"],
      [
        "view", "acquisition", "modes", "0", "delivery", "lease", "expiration_schema",
      ],
      ["view", "request_processing", "data_handling", "contract"],
      ["view", "request_processing", "provider_execution_capability"],
      ["view", "output", "schema"],
      ["view", "output", "facts"],
      ["view", "output", "data_policy"],
      ["view", "pushdown", "contract"],
      ["command", "input_schema"],
      ["command", "output_schema"],
      ["command", "idempotency", "key_schema"],
      ["command", "reconciliation"],
      ["command", "poll"],
      ["command", "cancel"],
    ] {
    let error = check_catalog_references(
      reference_fixture(path~, replacement=Some(wrong)),
      reference_caps(),
    ).unwrap_err()
    assert_true(error.kind is Resolution(Contract(WrongKind(_, _))))
    let actual = @decode.cursor_path(error.source.unwrap())
    assert_true(
      actual[actual.length() - 1] is Key(v) && v == path[path.length() - 1],
    )
  }
  let other = reference_contract(catalog_reference_at(baseline, 1).unwrap())
  let (id, version, cid) = contract_identity(other)
  let wrong = @json.parse(
    "{\"id\":\"" +
    id +
    "\",\"version\":\"" +
    version +
    "\",\"cid\":\"" +
    cid +
    "\"}",
  )
  assert_true(
    check_catalog_references(
      reference_fixture(
        path=["view", "acquisition", "request_schema"],
        replacement=Some(wrong),
      ),
      reference_caps(),
    )
    is Err({ kind: Resolution(Contract(WrongKind(_, _))), .. }),
  )
}

///|
test "missing malformed and foreign Catalog references cannot be masked by aggregate hashing" {
  for
    path in [
      ["view", "acquisition"],
      ["view", "output", "data_policy"],
      ["view", "acquisition", "batching", "request_key_schema"],
      ["command", "idempotency"],
      ["command", "input_schema"],
    ] {
    assert_true(
      check_catalog_references(reference_fixture(path~), reference_caps())
      is Err({ kind: InvalidSlot, .. }),
    )
  }
  for
    body in [
      "null", "[]", "{}", "{\"id\":\"request_schema\",\"version\":\"external\"}",
      "{\"id\":null,\"version\":\"external\",\"cid\":\"x\"}", "{\"id\":\"request_schema\",\"version\":\"external\",\"cid\":\"x\",\"extra\":0}",
    ] {
    assert_true(
      check_catalog_references(
        reference_fixture(
          path=["view", "acquisition", "request_schema"],
          replacement=Some(@json.parse(body)),
        ),
        reference_caps(),
      )
      is Err({ kind: InvalidSlot, .. }),
    )
  }
  assert_true(
    check_catalog_references(
      reference_fixture(misplaced=true),
      reference_caps(),
    )
    is Err({ kind: Resolution(OutsideCatalog(_, _)), .. }),
  )
  let missing = @json.parse(
    "{\"id\":\"missing\",\"version\":\"external\",\"cid\":\"sha256:" +
    "0".repeat(64) +
    "\"}",
  )
  assert_true(
    check_catalog_references(
      reference_fixture(path=["command", "cancel"], replacement=Some(missing)),
      reference_caps(),
    )
    is Err({ kind: Resolution(Contract(UnknownReference(_, _))), .. }),
  )
}
