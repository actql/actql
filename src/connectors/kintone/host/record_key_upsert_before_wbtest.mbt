///|
fn key_before_catalog(
  memo_required? : Bool = false,
) -> @catalog.FormFieldCatalog {
  let body = "{\"revision\":\"7\",\"properties\":{\"customer_code\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"customer_code\",\"expression\":\"\",\"unique\":true,\"required\":true},\"memo\":{\"type\":\"MULTI_LINE_TEXT\",\"code\":\"memo\",\"required\":false},\"Tags\":{\"type\":\"MULTI_SELECT\",\"code\":\"Tags\",\"required\":false},\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"Computed\",\"expression\":\"\\\"server\\\"\"},\"Extra\":{\"type\":\"SINGLE_LINE_TEXT\",\"code\":\"Extra\",\"expression\":\"\",\"required\":false}}}"
  let body = if memo_required {
    body.replace(
      old="\"code\":\"memo\",\"required\":false",
      new="\"code\":\"memo\",\"required\":true",
    )
  } else {
    body
  }
  @catalog.project_form_fields(@utf8.encode(body), "12", {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 16,
    max_fields: 10,
    max_name_units: 1000,
  }).unwrap()
}

///|
fn key_before_declaration(
  catalog : @catalog.FormFieldCatalog,
  names? : Array[String] = ["customer_code", "Computed", "Tags", "memo"],
) -> RecordDeclaration {
  declare_records(
    catalog,
    None,
    names,
    "crm",
    "kintone/0.1",
    "customers",
    delete_preview_values(),
    delete_declaration_limits(),
  ).unwrap()
}

///|
fn key_before_lookup_limits() -> @catalog.RecordLookupLimits {
  {
    max_key_bytes: 1000,
    max_columns: 10,
    max_comparison_work: 10000,
    max_request_bytes: 20000,
    max_request_nodes: 1000,
    max_request_depth: 16,
  }
}

///|
fn key_before_lookup(
  catalog : @catalog.FormFieldCatalog,
  present : Bool,
  names? : Array[String] = ["memo", "Tags", "Computed"],
) -> @catalog.RecordLookupObservation {
  let request = @catalog.prepare_record_text_key_lookup(
    catalog,
    "customer_code",
    "original-key",
    names,
    key_before_lookup_limits(),
  ).unwrap()
  key_before_reply(request, present)
}

///|
fn key_before_reply(
  request : @catalog.RecordLookupRequest,
  present : Bool,
) -> @catalog.RecordLookupObservation {
  @catalog.project_record_key_lookup(
    request,
    200,
    if present {
      b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9007199254740994\"},\"customer_code\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original-key\"},\"memo\":{\"type\":\"MULTI_LINE_TEXT\",\"value\":\"東京 é\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[\"red\",\"東京\",\"red\"]},\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"server\"},\"Extra\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"extra\"}}],\"totalCount\":\"1\"}"
    } else {
      b"{\"records\":[],\"totalCount\":\"0\"}"
    },
    {
      max_bytes: 20000,
      max_nodes: 1000,
      max_depth: 16,
      max_rows: 2,
      max_columns: 10,
      max_cells: 20,
      max_table_rows: 10,
    },
  ).unwrap()
}

///|
fn key_before_write_limits() -> @catalog.RecordWriteLimits {
  {
    max_fields: 10,
    max_name_bytes: 1000,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 20000,
    max_output_bytes: 20000,
  }
}

///|
test "keyed UPSERT before retains full present original and reuses exact target in native UPDATE" {
  let catalog = key_before_catalog()
  let original = key_before_declaration(catalog)
  let lookup = key_before_lookup(catalog, true)
  let before = prepare_record_key_upsert_before(
    original,
    lookup,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(record_key_upsert_before_key(before), "customer_code")
  assert_eq(record_key_upsert_before_identity(before), "original-key")
  assert_eq(
    record_key_upsert_before_wire(before),
    Some(
      "{\"$id\":\"9007199254740993\",\"memo\":\"東京 é\",\"Tags\":[\"red\",\"東京\",\"red\"],\"Computed\":\"server\",\"customer_code\":\"original-key\"}",
    ),
  )
  assert_eq(
    record_key_upsert_before_version_cid(before),
    Some(
      "sha256:99944ac0d4a7f14be6fac31131cccd767d5149ae8e8c65daeb50bdeee0c087cd",
    ),
  )
  let target = record_key_upsert_before_target(before).unwrap()
  assert_eq(@catalog.original_record_target_id(target), "9007199254740993")
  assert_true(
    physical_equal(
      @catalog.original_record_target_page(target),
      @catalog.record_key_lookup_page(lookup),
    ),
  )
  let values = @catalog.prepare_record_write_values_json(
    catalog,
    b"{\"memo\":\"next\"}",
    10000,
    key_before_write_limits(),
  ).unwrap()
  let request = @catalog.prepare_record_key_upsert_request(
    lookup,
    values,
    key_before_write_limits(),
    delete_preview_limits(),
    target=Some(target),
  ).unwrap()
  let native = @catalog.record_key_upsert_update_request(request).unwrap()
  assert_true(
    physical_equal(@catalog.record_update_request_values(native)[0].0, target),
  )
  assert_eq(
    @catalog.record_update_request_body(native),
    "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"memo\":{\"value\":\"next\"}},\"revision\":\"9007199254740994\"}],\"upsert\":false}",
  )
  assert_true(record_key_upsert_before_matches(before, original, lookup))
}

///|
test "keyed UPSERT before complete absence never fabricates native target before or version" {
  let catalog = key_before_catalog()
  let original = key_before_declaration(catalog)
  let lookup = key_before_lookup(catalog, false)
  let before = prepare_record_key_upsert_before(
    original,
    lookup,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_eq(record_key_upsert_before_key(before), "customer_code")
  assert_eq(record_key_upsert_before_identity(before), "original-key")
  assert_true(record_key_upsert_before_target(before) is None)
  assert_true(record_key_upsert_before_wire(before) is None)
  assert_true(record_key_upsert_before_version_cid(before) is None)
  assert_true(record_key_upsert_before_matches(before, original, lookup))
  let values = @catalog.prepare_record_write_values_json(
    catalog,
    b"{\"memo\":\"next\"}",
    10000,
    key_before_write_limits(),
  ).unwrap()
  let request = @catalog.prepare_record_key_upsert_request(
    lookup,
    values,
    key_before_write_limits(),
    delete_preview_limits(),
    target=record_key_upsert_before_target(before),
  ).unwrap()
  assert_eq(
    @catalog.record_create_request_body(
      @catalog.record_key_upsert_create_request(request).unwrap(),
    ),
    "{\"app\":\"12\",\"records\":[{\"memo\":{\"value\":\"next\"},\"customer_code\":{\"value\":\"original-key\"}}]}",
  )
  let present = prepare_record_key_upsert_before(
    original,
    key_before_lookup(catalog, true),
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  assert_true(
    @catalog.prepare_record_key_upsert_request(
      lookup,
      values,
      key_before_write_limits(),
      delete_preview_limits(),
      target=record_key_upsert_before_target(present),
    )
    is Err(InvalidLookup),
  )
}

///|
test "keyed UPSERT before preserves declaration snapshot and refuses foreign incomplete copied and bounded material" {
  let catalog = key_before_catalog()
  let names = ["customer_code", "Computed", "Tags", "memo"]
  let original = key_before_declaration(catalog, names~)
  names.clear()
  record_declaration(original).views[0].fields.clear()
  let lookup = key_before_lookup(catalog, true)
  let before = prepare_record_key_upsert_before(
    original,
    lookup,
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  let copied : RecordKeyUpsertBefore = { ..before, }
  assert_false(record_key_upsert_before_matches(copied, original, lookup))
  assert_false(
    record_key_upsert_before_matches(
      before,
      key_before_declaration(catalog),
      lookup,
    ),
  )
  assert_false(
    record_key_upsert_before_matches(
      before,
      original,
      key_before_lookup(catalog, true),
    ),
  )
  for
    wrong in [
      key_before_lookup(key_before_catalog(), true),
      key_before_lookup(catalog, true, names=["memo"]),
      key_before_lookup(catalog, true, names=["memo", "Tags", "Extra"]),
    ] {
    assert_true(
      prepare_record_key_upsert_before(
        original,
        wrong,
        delete_preview_values(),
        delete_preview_limits(),
      )
      is Err(ForeignDeclaration),
    )
  }
  for
    limits in [
      { ..delete_preview_limits(), max_records: 0, },
      { ..delete_preview_limits(), max_comparison_work: 1, },
      { ..delete_preview_limits(), max_identity_bytes: 1, },
      { ..delete_preview_limits(), max_output_bytes: 1, },
    ] {
    assert_true(
      prepare_record_key_upsert_before(
        original,
        lookup,
        delete_preview_values(),
        limits,
      )
      is Err(_),
    )
  }
  let foreign = prepare_record_key_upsert_before(
    original,
    key_before_lookup(catalog, true),
    delete_preview_values(),
    delete_preview_limits(),
  ).unwrap()
  let values = @catalog.prepare_record_write_values_json(
    catalog,
    b"{\"memo\":\"next\"}",
    10000,
    key_before_write_limits(),
  ).unwrap()
  assert_true(
    @catalog.prepare_record_key_upsert_request(
      lookup,
      values,
      key_before_write_limits(),
      delete_preview_limits(),
      target=record_key_upsert_before_target(foreign),
    )
    is Err(InvalidLookup),
  )
}

///|
test "keyed UPSERT Mapping binds the original Form key and both permissions, preserving native identity" {
  let original = key_before_declaration(key_before_catalog(memo_required=true))
  let sources : Array[@rows.RowMappingSource] = [
    { target: "memo", field: "next_memo", null_behavior: "reject", },
  ]
  let limits = delete_declaration_limits()
  let selected = prepare_record_key_upsert_mapping(
    original, "customers", "customer_code", sources, limits,
  ).unwrap()
  let mapped = record_key_upsert_mapping(selected)
  let update = prepare_record_update_mapping(
    original, "customers", sources, "required", limits,
  ).unwrap()
  guard @json.parse(mapped.body) is Object(body) &&
    @json.parse(record_update_mapping(update).body) is Object(update_body) else {
    fail("Original Mapping body required")
  }
  assert_eq(body.get("primary_identity"), Some("customer_code".to_json()))
  assert_eq(
    body.get("resource_identity_cid"),
    update_body.get("resource_identity_cid"),
  )
  assert_eq(body.get("minimum_approval"), Some("required".to_json()))
  assert_eq(body.get("required_fields"), Some((["memo"] : Json)))
  assert_eq(body.get("writable_fields"), Some((["memo"] : Json)))
  assert_eq(
    body.get("permission_rules"),
    Some(
      (
        [
          {
            "effect_kind": "upsert",
            "selector_class": "key",
            "write_fields": ["memo"],
            "permissions": ["kintone:records:create", "kintone:records:update"],
          },
        ] : Json),
    ),
  )
  assert_eq(mapped.write_fields, ["memo"])
  assert_true(
    prepare_record_key_upsert_mapping(
      original, "customers", "memo", sources, limits,
    )
    is Err(InvalidSpecification),
  )
  assert_true(
    prepare_record_key_upsert_mapping(
      original,
      "customers",
      "customer_code",
      [],
      limits,
    )
    is Err(MissingRequiredField("memo")),
  )
  assert_true(
    prepare_record_key_upsert_mapping(
      original,
      "customers",
      "customer_code",
      [{ target: "Computed", field: "computed", null_behavior: "reject", }],
      limits,
    )
    is Err(FieldNotWritable("Computed")),
  )
}

///|
test "mapped UPSERT proposal binds both outcomes to its exact original lookup and cells" {
  let original = key_before_declaration(key_before_catalog(memo_required=true))
  let sources : Array[@rows.RowMappingSource] = [
    { target: "memo", field: "next_memo", null_behavior: "reject", },
    { target: "Tags", field: "next_tags", null_behavior: "omit", },
  ]
  let selected = prepare_record_key_upsert_mapping(
    original,
    "customers",
    "customer_code",
    sources,
    delete_declaration_limits(),
  ).unwrap()
  // An escaped array from the Mapping's construction is independent of its
  // held rules. The proposal still needs the selected required input cell.
  sources.clear()
  let bytes = b"{\"memo\":\"next\"}"
  let limits = key_before_lookup_limits()
  let write_limits = key_before_write_limits()
  for present in [true, false] {
    let proposal = prepare_record_key_upsert_proposal(
      selected, "original-key", bytes, 10000, write_limits, limits,
    ).unwrap()
    let lookup = record_key_upsert_proposal_lookup(proposal)
    assert_true(
      @catalog.record_lookup_request_body(lookup).contains("customer_code = "),
    )
    let observed = key_before_reply(lookup, present)
    let (before, request) = prepare_record_key_upsert_observed_request(
      proposal,
      observed,
      delete_preview_values(),
      write_limits,
      delete_preview_limits(),
    ).unwrap()
    assert_true(record_key_upsert_before_matches(before, original, observed))
    if present {
      assert_true(record_key_upsert_before_version_cid(before) is Some(_))
      assert_eq(
        @catalog.record_update_request_body(
          @catalog.record_key_upsert_update_request(request).unwrap(),
        ),
        "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"memo\":{\"value\":\"next\"}},\"revision\":\"9007199254740994\"}],\"upsert\":false}",
      )
    } else {
      assert_true(record_key_upsert_before_version_cid(before) is None)
      assert_eq(
        @catalog.record_create_request_body(
          @catalog.record_key_upsert_create_request(request).unwrap(),
        ),
        "{\"app\":\"12\",\"records\":[{\"memo\":{\"value\":\"next\"},\"customer_code\":{\"value\":\"original-key\"}}]}",
      )
    }
    let different = prepare_record_key_upsert_proposal(
      selected, "original-key", bytes, 10000, write_limits, limits,
    ).unwrap()
    assert_true(
      prepare_record_key_upsert_observed_request(
        different,
        observed,
        delete_preview_values(),
        write_limits,
        delete_preview_limits(),
      )
      is Err(Lookup(ForeignRequest)),
    )
  }
  for
    rejected in [
      b"{\"Tags\":[\"red\"]}", b"{\"memo\":\"next\",\"customer_code\":\"original-key\"}",
    ] {
    assert_true(
      prepare_record_key_upsert_proposal(
        selected, "original-key", rejected, 10000, write_limits, limits,
      )
      is Err(MappingMismatch),
    )
  }
}
