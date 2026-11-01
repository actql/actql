///|
fn key_upsert_catalog(extra_required? : Bool = false) -> FormFieldCatalog {
  form_test_catalog(
    body=(
        #|{"revision":"7","properties":{"customer_code":{"type":"SINGLE_LINE_TEXT","code":"customer_code","expression":"","unique":true,"required":true},"memo":{"type":"MULTI_LINE_TEXT","code":"memo","required":false}
      ) +
      (if extra_required {
        ",\"extra\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"extra\",\"expression\":\"\",\"required\":true}"
      } else {
        ""
      }) +
      "}}",
  )
}

///|
fn key_upsert_lookup(
  catalog : FormFieldCatalog,
  present : Bool,
  key? : String = "original-key",
) -> RecordLookupObservation {
  let request = prepare_record_text_key_lookup(
    catalog,
    "customer_code",
    key,
    ["memo"],
    lookup_test_limits(),
  ).unwrap()
  lookup_test_response(
    request,
    if present {
      [lookup_test_row(value=key)]
    } else {
      []
    },
    total=if present { "1" } else { "0" },
  ).unwrap()
}

///|
fn key_upsert_values(catalog : FormFieldCatalog) -> RecordWriteValues {
  prepare_record_write_values(
    catalog,
    [("memo", write_text("intended"))],
    write_test_limits(),
  ).unwrap()
}

///|
test "keyed UPSERT retains original present lookup and exact revision checked UPDATE branch" {
  let catalog = key_upsert_catalog()
  let lookup = key_upsert_lookup(catalog, true)
  let values = key_upsert_values(catalog)
  let request = prepare_record_key_upsert_request(
    lookup,
    values,
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  assert_eq(record_key_upsert_request_operation(request), Update)
  assert_true(record_key_upsert_request_matches_lookup(request, lookup))
  assert_true(physical_equal(record_key_upsert_request_values(request), values))
  assert_true(record_key_upsert_create_request(request) is None)
  let update = record_key_upsert_update_request(request).unwrap()
  assert_eq(
    record_update_request_body(update),
    (
      #|{"app":"12","records":[{"id":"9007199254740993","record":{"memo":{"value":"intended"}},"revision":"9007199254740994"}],"upsert":false}
    ),
  )
  assert_true(physical_equal(update.records[0].0.page, lookup.page))
  assert_true(physical_equal(update.records[0].1, values))
}

///|
test "keyed UPSERT original complete absence emits CREATE with same enforced key and no blind upsert" {
  let catalog = key_upsert_catalog()
  let lookup = key_upsert_lookup(catalog, false, key="東京\"\\é")
  let values = key_upsert_values(catalog)
  let request = prepare_record_key_upsert_request(
    lookup,
    values,
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  assert_eq(record_key_upsert_request_operation(request), Insert)
  assert_true(record_key_upsert_update_request(request) is None)
  let create = record_key_upsert_create_request(request).unwrap()
  assert_eq(
    record_create_request_body(create),
    (
      #|{"app":"12","records":[{"memo":{"value":"intended"},"customer_code":{"value":"東京\"\\é"}}]}
    ),
  )
  assert_true(physical_equal(create.catalog, catalog))
  assert_true(
    physical_equal(create.records[0].originals[0].1, values.originals[0].1),
  )
  assert_eq(record_write_values_fields(values), ["memo"])
  assert_true(record_key_upsert_request_matches_lookup(request, lookup))
}

///|
test "keyed UPSERT refuses changing the original key foreign values and missing insertion requirements" {
  let catalog = key_upsert_catalog()
  for present in [false, true] {
    let lookup = key_upsert_lookup(catalog, present)
    let changed = prepare_record_write_values(
      catalog,
      [("customer_code", write_text("other"))],
      write_test_limits(),
    ).unwrap()
    assert_true(
      prepare_record_key_upsert_request(
        lookup,
        changed,
        write_test_limits(),
        mutation_limits(),
      )
      is Err(ChangedKey),
    )
    assert_true(
      prepare_record_key_upsert_request(
        lookup,
        key_upsert_values(key_upsert_catalog()),
        write_test_limits(),
        mutation_limits(),
      )
      is Err(ForeignCatalog),
    )
    let same = prepare_record_write_values(
      catalog,
      [("customer_code", write_text("original-key"))],
      write_test_limits(),
    ).unwrap()
    let request = prepare_record_key_upsert_request(
      lookup,
      same,
      write_test_limits(),
      mutation_limits(),
    ).unwrap()
    if !present {
      assert_eq(
        record_create_request_body(
          record_key_upsert_create_request(request).unwrap(),
        ),
        (
          #|{"app":"12","records":[{"customer_code":{"value":"original-key"}}]}
        ),
      )
    }
  }
  let required = key_upsert_catalog(extra_required=true)
  let intended = key_upsert_values(required)
  assert_true(
    prepare_record_key_upsert_request(
      key_upsert_lookup(required, false),
      intended,
      write_test_limits(),
      mutation_limits(),
    )
    is Err(MissingRequiredField("extra")),
  )
  assert_true(
    prepare_record_key_upsert_request(
      key_upsert_lookup(required, true),
      intended,
      write_test_limits(),
      mutation_limits(),
    )
    is Ok(_),
  )
}

///|
test "keyed UPSERT nominal request and lookup correspondence cannot use equal copied originals" {
  let catalog = key_upsert_catalog()
  let lookup = key_upsert_lookup(catalog, false)
  let request = prepare_record_key_upsert_request(
    lookup,
    key_upsert_values(catalog),
    write_test_limits(),
    mutation_limits(),
  ).unwrap()
  assert_true(record_key_upsert_request_is_original(request))
  let copied : RecordKeyUpsertRequest = { ..request, }
  assert_false(record_key_upsert_request_is_original(copied))
  assert_true(record_key_upsert_create_request(copied) is None)
  assert_false(
    record_key_upsert_request_matches_lookup(
      request,
      key_upsert_lookup(catalog, false),
    ),
  )
}

///|
test "keyed UPSERT preserves explicit encoding field identity and comparison budgets" {
  let catalog = key_upsert_catalog()
  let lookup = key_upsert_lookup(catalog, false)
  let values = key_upsert_values(catalog)
  assert_true(
    prepare_record_key_upsert_request(
      lookup,
      values,
      { ..write_test_limits(), max_fields: 1, },
      mutation_limits(),
    )
    is Err(Write(BudgetExceeded)),
  )
  for
    limits in [
      { ..mutation_limits(), max_identity_bytes: 1, },
      { ..mutation_limits(), max_output_bytes: 1, },
      { ..mutation_limits(), max_comparison_work: 1, },
    ] {
    assert_true(
      prepare_record_key_upsert_request(
        lookup,
        values,
        write_test_limits(),
        limits,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_record_key_upsert_request(lookup, values, write_test_limits(), {
      ..mutation_limits(),
      max_records: 0,
    })
    is Err(InvalidLimits),
  )
}
