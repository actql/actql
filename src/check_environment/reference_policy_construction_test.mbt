///|
test "reference constructor and returned ownership use generated routes and independent fixed counts" {
  assert_eq(
    catalog_reference_construction_extent({
      catalogs: 1,
      members: 0,
      member_nodes: 0,
      max_member_nodes: 0,
    }),
    Some({
      record_headers: 149L,
      reference_slots: 603L,
      scalar_words: 170L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  let small = CatalogReferenceGeometry::{
    catalogs: 1,
    members: 2,
    member_nodes: 8,
    max_member_nodes: 4,
  }
  assert_eq(
    catalog_reference_construction_extent(small),
    Some({
      record_headers: 284L,
      reference_slots: 980L,
      scalar_words: 391L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  assert_eq(
    catalog_reference_retained_extent(small),
    Some({
      record_headers: 40L,
      reference_slots: 115L,
      scalar_words: 103L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  assert_true(
    catalog_reference_construction_extent({ ..small, member_nodes: -1, })
    is None,
  )
  assert_true(
    catalog_reference_construction_extent({ ..small, max_member_nodes: 9, })
    is None,
  )
  assert_true(
    catalog_reference_construction_extent({ ..small, members: 0, }) is None,
  )
  assert_true(
    catalog_reference_construction_extent({
      catalogs: 2147483647,
      members: 2147483647,
      member_nodes: 2147483647,
      max_member_nodes: 2147483647,
    })
    is Some(_),
  )
}

///|
test "actual reference observer retains repeated roles and original one-short partial charges" {
  let contents = reference_fixture(view_count=3, modes=10)
  let geometry = observe_reference_construction_geometry(contents)
  assert_eq(geometry.catalogs, 1)
  assert_eq(geometry.members, 4)
  let (result, work) = observe_catalog_references(contents, reference_caps())
  let references = result.unwrap()
  assert_eq(reference_usage(references), (work, 126))
  assert_true(126 <= geometry.member_nodes / 4)
  assert_eq(reference_construction_observation_work(contents), 8L)
  let (short, charged) = observe_catalog_references(contents, {
    max_work: work - 1,
    max_references: 126,
  })
  assert_true(short is Err(issue) && issue.kind == WorkLimit)
  assert_eq(charged, work - 1)
  assert_true(
    check_catalog_references(contents, {
      max_work: work - 1,
      max_references: 126,
    })
    is Err(issue) &&
    issue.kind == WorkLimit,
  )
  let (limited, charged) = observe_catalog_references(contents, {
    max_work: work,
    max_references: 125,
  })
  assert_true(limited is Err(issue) && issue.kind == ReferenceLimit)
  assert_true(charged > 0 && charged < work)
  let (invalid, charged) = observe_catalog_references(contents, {
    max_work: -1,
    max_references: 126,
  })
  assert_true(invalid is Err(issue) && issue.kind == InvalidLimits)
  assert_eq(charged, 0)
}

///|
test "data-policy inventory retains unused bodies and exact output ownership without text copies" {
  assert_eq(
    data_policy_construction_extent({
      envelopes: 1,
      policies: 1,
      references: 1,
      policy_references: 1,
    }),
    Some({
      record_headers: 93L,
      reference_slots: 204L,
      scalar_words: 164L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  assert_eq(
    data_policy_retained_extent({
      envelopes: 1,
      policies: 1,
      references: 1,
      policy_references: 1,
    }),
    Some({
      record_headers: 28L,
      reference_slots: 82L,
      scalar_words: 72L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  let body = policy_body_fixture("unknown")
  let contents = reference_fixture(
    policy_body=Some(body),
    unused_policy=Some(body),
    view_count=3,
  )
  let references = observe_catalog_references(contents, reference_caps()).0.unwrap()
  let geometry = observe_data_policy_construction_geometry(references)
  assert_eq(geometry.policies, 2)
  assert_eq(geometry.references, 45)
  assert_eq(geometry.policy_references, 3)
  let (result, work) = observe_source_data_policies(references, policy_limits())
  let policies = result.unwrap()
  assert_eq(data_policy_usage(policies), (work, 2))
  assert_true(physical_equal(data_policy_references(policies), references))
  let catalog = catalog_at(contents, 0).unwrap()
  for i in 0..<3 {
    let original = catalog_view_at(catalog, i).unwrap()
    let retained = source_view_policy(policies, original).unwrap()
    assert_true(
      physical_equal(
        reference_member(source_view_policy_reference(retained)),
        original,
      ),
    )
  }
  let (short, charged) = observe_source_data_policies(references, {
    max_work: work - 1,
    max_policies: 2,
  })
  assert_eq(short is Err(WorkLimit), true)
  assert_eq(charged, work - 1)
  let (limited, charged) = observe_source_data_policies(references, {
    max_work: work,
    max_policies: 1,
  })
  assert_true(limited is Err(PolicyLimit))
  assert_true(charged > 0 && charged < work)
  let invalid = reference_fixture(
    policy_body=Some(body),
    unused_policy=Some(Json::null()),
  )
  let refs = check_catalog_references(invalid, reference_caps()).unwrap()
  let (bad, used) = observe_source_data_policies(refs, policy_limits())
  assert_true(bad is Err(InvalidPolicy(_)))
  assert_true(used > 0)
  assert_true(
    check_source_data_policies(refs, policy_limits()) is Err(InvalidPolicy(_)),
  )
  assert_true(
    data_policy_construction_extent({ ..geometry, policies: -1, }) is None,
  )
}
