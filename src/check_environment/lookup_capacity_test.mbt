///|
fn assert_lookup_capacity_fixture(
  text : String,
  accepted : Bool,
  complete : Bool,
) -> Unit raise {
  for unused in [false, true] {
    let body = @json.parse(text)
    let contents = if unused {
      reference_fixture(
        bodies=Map([("carrier_facts", @json.parse("{}"))]),
        unused_facts=Some(body),
      )
    } else {
      reference_fixture(bodies=Map([("carrier_facts", body)]))
    }
    let refs = check_catalog_references(contents, reference_caps()).unwrap()
    let result = check_lookup_capacities(refs, {
      max_work: 100000,
      max_facts: 10,
    })
    if !accepted {
      guard result is Err(issue) else { fail("malformed facts accepted") }
      assert_eq(issue.kind, InvalidBody)
      assert_true(issue.source is Some(_))
      continue
    }
    let checked = result.unwrap()
    assert_true(physical_equal(lookup_capacity_references(checked), refs))
    let (work, count) = lookup_capacity_usage(checked)
    assert_eq(count, if unused { 2 } else { 1 })
    let mut components = 0
    for i in 0..<count {
      let facts = lookup_facts_at(checked, i).unwrap()
      assert_eq(contract_role(lookup_facts_envelope(facts)), "carrier_facts")
      if lookup_facts_capacity(facts) is Some(capacity) {
        components += 1
        assert_eq(
          lookup_capacity_completeness(capacity) == CompletePerRequestedKey,
          complete,
        )
        let source = lookup_capacity_source(capacity)
        let obj = @decode.open_object(source).unwrap()
        assert_eq(
          lookup_capacity_rows_per_key(capacity),
          @decode.safe_integer(@decode.lookup(obj, "max_rows_per_key").unwrap()).unwrap(),
        )
        assert_eq(
          lookup_capacity_pages_per_request(capacity),
          @decode.safe_integer(
            @decode.lookup(obj, "max_pages_per_request").unwrap(),
          ).unwrap(),
        )
        assert_eq(
          lookup_capacity_response_bytes_per_page(capacity),
          @decode.safe_integer(
            @decode.lookup(obj, "max_response_bytes_per_page").unwrap(),
          ).unwrap(),
        )
      }
    }
    assert_eq(components, if text.contains("lookup_capacity") { 1 } else { 0 })
    let item = catalog_view_at(catalog_at(contents, 0).unwrap(), 0).unwrap()
    let linked = source_lookup_facts(checked, item).unwrap()
    assert_true(
      physical_equal(reference_member(source_lookup_reference(linked)), item),
    )
    assert_true(
      physical_equal(
        reference_contract(source_lookup_reference(linked)),
        lookup_facts_envelope(source_lookup_body(linked)),
      ),
    )
    if unused {
      assert_true(lookup_facts_capacity(source_lookup_body(linked)) is None)
    }
    let other = reference_fixture(
      bodies=Map([("carrier_facts", @json.parse(text))]),
    )
    assert_true(
      source_lookup_facts(
        checked,
        catalog_view_at(catalog_at(other, 0).unwrap(), 0).unwrap(),
      )
      is None,
    )
    assert_true(
      source_lookup_facts(
        checked,
        catalog_command_at(catalog_at(contents, 0).unwrap(), 0).unwrap(),
      )
      is None,
    )
    assert_true(lookup_facts_at(checked, -1) is None)
    assert_true(lookup_facts_at(checked, count) is None)
    assert_true(
      check_lookup_capacities(refs, { max_work: work, max_facts: count, })
      is Ok(_),
    )
    assert_true(
      check_lookup_capacities(refs, { max_work: work - 1, max_facts: count, })
      is Err({ kind: WorkLimit, .. }),
    )
    assert_true(
      check_lookup_capacities(refs, { max_work: work, max_facts: count - 1, })
      is Err({ kind: FactsLimit, .. }),
    )
  }
}

///|
test "lookup capacity empty registry and invalid limits" {
  let contents = check_catalog_contents(catalog_environment([], []), caps()).unwrap()
  let refs = check_catalog_references(contents, reference_caps()).unwrap()
  let checked = check_lookup_capacities(refs, { max_work: 0, max_facts: 0, }).unwrap()
  assert_eq(lookup_capacity_usage(checked), (0, 0))
  let invalid : Array[LookupCapacityLimits] = [
    { max_work: -1, max_facts: 0, },
    { max_work: 0, max_facts: -1, },
  ]
  for limits in invalid {
    assert_true(
      check_lookup_capacities(refs, limits)
      is Err({ kind: InvalidLimits, source: None, }),
    )
  }
}

///|
test "lookup facts shared body retains distinct SourceView references" {
  let contents = reference_fixture(
    bodies=Map([("carrier_facts", @json.parse("{}"))]),
    view_count=2,
  )
  let refs = check_catalog_references(contents, reference_caps()).unwrap()
  let checked = check_lookup_capacities(refs, {
    max_work: 100000,
    max_facts: 1,
  }).unwrap()
  let catalog = catalog_at(contents, 0).unwrap()
  let first = source_lookup_facts(checked, catalog_view_at(catalog, 0).unwrap()).unwrap()
  let second = source_lookup_facts(
    checked,
    catalog_view_at(catalog, 1).unwrap(),
  ).unwrap()
  assert_true(
    physical_equal(source_lookup_body(first), source_lookup_body(second)),
  )
  assert_false(
    physical_equal(
      source_lookup_reference(first),
      source_lookup_reference(second),
    ),
  )
  assert_true(lookup_facts_capacity(source_lookup_body(first)) is None)
}
