///|
fn policy_body_fixture(classification : String) -> Json raise {
  @json.parse(
    "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":\"source:connector/record#view\",\"classification\":\"" +
    classification +
    "\"}",
  )
}

///|
fn policy_limits() -> DataPolicyLimits {
  { max_work: 100000, max_policies: 10, }
}

///|
test "source data policy keeps all classifications including unknown and exact output ownership" {
  for
    (name, expected) in [
      ("public", DataClassification::Public),
      ("internal", DataClassification::Internal),
      ("confidential", DataClassification::Confidential),
      ("restricted", DataClassification::Restricted),
      ("unknown", DataClassification::Unknown),
    ] {
    let contents = reference_fixture(
      policy_body=Some(policy_body_fixture(name)),
    )
    let references = check_catalog_references(contents, reference_caps()).unwrap()
    let policies = check_source_data_policies(references, policy_limits()).unwrap()
    assert_true(physical_equal(data_policy_references(policies), references))
    let policy = data_policy_at(policies, 0).unwrap()
    assert_eq(data_classification(policy), expected)
    assert_eq(data_policy_source(policy), "source:connector/record#view")
    assert_eq(contract_role(data_policy_envelope(policy)), "data_policy")
    if name == "unknown" {
      // Independently computed with Python hashlib, full envelope core rather
      // than the policy body alone.
      assert_eq(
        contract_identity(data_policy_envelope(policy)).2,
        "sha256:8f74df0a38b16dda8bef7375593b16f1cfc86b6d1fb5474150b59889d7c9e5c9",
      )
    }
    let catalog = catalog_at(contents, 0).unwrap()
    let item = catalog_view_at(catalog, 0).unwrap()
    let linked = source_view_policy(policies, item).unwrap()
    assert_true(physical_equal(source_view_data_policy(linked), policy))
    let reference = source_view_policy_reference(linked)
    assert_true(physical_equal(reference_member(reference), item))
    assert_true(
      physical_equal(
        reference_contract(reference),
        data_policy_envelope(policy),
      ),
    )
    assert_true(
      source_view_policy(policies, catalog_command_at(catalog, 0).unwrap())
      is None,
    )
    let other = reference_fixture(policy_body=Some(policy_body_fixture(name)))
    let other_item = catalog_view_at(catalog_at(other, 0).unwrap(), 0).unwrap()
    assert_true(source_view_policy(policies, other_item) is None)
    assert_true(data_policy_at(policies, -1) is None)
    assert_true(data_policy_at(policies, 1) is None)
    let (work, count) = data_policy_usage(policies)
    assert_eq(count, 1)
    assert_true(
      check_source_data_policies(references, {
        max_work: work,
        max_policies: 1,
      })
      is Ok(_),
    )
    assert_true(
      check_source_data_policies(references, {
        max_work: work - 1,
        max_policies: 1,
      })
      is Err(WorkLimit),
    )
    assert_true(
      check_source_data_policies(references, {
        max_work: work,
        max_policies: 0,
      })
      is Err(PolicyLimit),
    )
    assert_true(
      check_source_data_policies(references, { max_work: -1, max_policies: 1, })
      is Err(InvalidLimits),
    )
  }
}

///|
test "malformed data policies fail even when unused and enclosing identities are valid" {
  let valid = policy_body_fixture("internal")
  let malformed = [
    @json.parse(
      "{\"version\":\"actql-source-data-policy/0.1\",\"source\":\"s\",\"classification\":\"public\"}",
    ),
    Json::null(),
    Json::array([]),
    Json::object(Map([])),
    @json.parse(
      "{\"version\":\"actql-source-data-policy/0.1\",\"classification\":\"public\"}",
    ),
    @json.parse(
      "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":\"\",\"classification\":\"public\"}",
    ),
    @json.parse(
      "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":null,\"classification\":\"public\"}",
    ),
    @json.parse(
      "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":\"s\",\"classification\":[]}",
    ),
    @json.parse(
      "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":\"s\",\"classification\":\"public\",\"extra\":0}",
    ),
    @json.parse(
      "{\"version\":\"wrong\",\"source_ref\":\"s\",\"classification\":\"public\"}",
    ),
    policy_body_fixture("PUBLIC"),
    policy_body_fixture(""),
    policy_body_fixture("secret"),
  ]
  for body in malformed {
    for unused in [false, true] {
      let contents = if unused {
        reference_fixture(policy_body=Some(valid), unused_policy=Some(body))
      } else {
        reference_fixture(policy_body=Some(body))
      }
      let references = check_catalog_references(contents, reference_caps()).unwrap()
      assert_true(
        check_source_data_policies(references, policy_limits())
        is Err(InvalidPolicy(_)),
      )
    }
  }
}

///|
test "all data policy bodies share one budget and unused policies remain inspectable" {
  let body = policy_body_fixture("unknown")
  let references = check_catalog_references(
    reference_fixture(policy_body=Some(body), unused_policy=Some(body)),
    reference_caps(),
  ).unwrap()
  let policies = check_source_data_policies(references, policy_limits()).unwrap()
  let (work, count) = data_policy_usage(policies)
  assert_eq(count, 2)
  for i in 0..<2 {
    assert_eq(
      data_classification(data_policy_at(policies, i).unwrap()),
      Unknown,
    )
  }
  assert_true(
    check_source_data_policies(references, {
      max_work: work,
      max_policies: count,
    })
    is Ok(_),
  )
  assert_true(
    check_source_data_policies(references, {
      max_work: work - 1,
      max_policies: count,
    })
    is Err(WorkLimit),
  )
  assert_true(
    check_source_data_policies(references, {
      max_work: work,
      max_policies: count - 1,
    })
    is Err(PolicyLimit),
  )
  let empty = check_catalog_contents(catalog_environment([], []), caps()).unwrap()
  let empty_refs = check_catalog_references(empty, reference_caps()).unwrap()
  assert_true(
    check_source_data_policies(empty_refs, { max_work: 0, max_policies: 0, })
    is Ok(v) &&
    data_policy_usage(v) == (0, 0),
  )
}
