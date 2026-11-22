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
    key_before_response_body(present),
    key_before_page_limits(),
  ).unwrap()
}

///|
fn key_before_response_body(present : Bool) -> Bytes {
  if present {
    b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9007199254740994\"},\"customer_code\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original-key\"},\"memo\":{\"type\":\"MULTI_LINE_TEXT\",\"value\":\"東京 é\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[\"red\",\"東京\",\"red\"]},\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"server\"},\"Extra\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"extra\"}}],\"totalCount\":\"1\"}"
  } else {
    b"{\"records\":[],\"totalCount\":\"0\"}"
  }
}

///|
fn key_before_page_limits() -> @catalog.RecordPageLimits {
  {
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 16,
    max_rows: 2,
    max_columns: 10,
    max_cells: 20,
    max_table_rows: 10,
  }
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
  let capacity = record_key_upsert_mapping_construction_capacity(
    original,
    "customer_code",
    sources.length(),
    30L,
    limits,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  assert_true(retained > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) > retained,
  )
  assert_true(
    record_key_upsert_mapping_construction_capacity(
      original,
      "customer_code",
      sources.length(),
      30L,
      { ..limits, max_bytes: "customer_code".length() - 1, },
    )
    is None,
  )
  assert_true(
    record_key_upsert_mapping_construction_capacity(
      original,
      "customer_code",
      sources.length(),
      9223372036854775807L,
      limits,
    )
    is None,
  )
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
  let mutation = { ..delete_preview_limits(), max_records: 1, }
  for present in [true, false] {
    let proposal = prepare_record_key_upsert_proposal(
      selected, "original-key", bytes, 10000, write_limits, limits,
    ).unwrap()
    let lookup = record_key_upsert_proposal_lookup(proposal)
    assert_true(
      @catalog.record_lookup_request_body(lookup).contains("customer_code = "),
    )
    let observed = key_before_reply(lookup, present)
    let before = prepare_record_key_upsert_proposal_before(
      proposal,
      observed,
      delete_preview_values(),
      mutation,
    ).unwrap()
    assert_true(record_key_upsert_before_matches(before, original, observed))
    if present {
      assert_true(record_key_upsert_before_version_cid(before) is Some(_))
      assert_true(
        record_key_upsert_create_construction_capacity(
          proposal, before, write_limits, mutation,
        )
        is None,
      )
      let expected = "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"memo\":{\"value\":\"next\"}},\"revision\":\"9007199254740994\"}],\"upsert\":false}"
      let exact = { ..mutation, max_output_bytes: expected.length(), }
      let short = { ..exact, max_output_bytes: expected.length() - 1, }
      let quote = record_key_upsert_update_construction_capacity(
        proposal, before, exact,
      ).unwrap()
      let smaller = record_key_upsert_update_construction_capacity(
        proposal, before, short,
      ).unwrap()
      assert_true(
        @execution.execution_capacity_retained_bytes(quote) >
        @execution.execution_capacity_retained_bytes(smaller),
      )
      assert_true(
        @execution.execution_capacity_execution_bytes(quote) >
        @execution.execution_capacity_retained_bytes(quote),
      )
      let bounded = prepare_record_key_upsert_request_from_before(
        proposal, before, write_limits, exact,
      ).unwrap()
      assert_eq(
        @catalog.record_update_request_body(
          @catalog.record_key_upsert_update_request(bounded).unwrap(),
        ),
        expected,
      )
      assert_true(
        prepare_record_key_upsert_request_from_before(
          proposal, before, write_limits, short,
        )
        is Err(Request(Request(BudgetExceeded))),
      )
    } else {
      assert_true(record_key_upsert_before_version_cid(before) is None)
      assert_true(
        record_key_upsert_update_construction_capacity(
          proposal, before, mutation,
        )
        is None,
      )
      let expected = "{\"app\":\"12\",\"records\":[{\"memo\":{\"value\":\"next\"},\"customer_code\":{\"value\":\"original-key\"}}]}"
      let value_body = "{\"memo\":{\"value\":\"next\"},\"customer_code\":{\"value\":\"original-key\"}}"
      let write = { ..write_limits, max_output_bytes: value_body.length(), }
      let exact = { ..mutation, max_output_bytes: expected.length(), }
      let short = { ..exact, max_output_bytes: expected.length() - 1, }
      let quote = record_key_upsert_create_construction_capacity(
        proposal, before, write, exact,
      ).unwrap()
      let smaller = record_key_upsert_create_construction_capacity(
        proposal, before, write, short,
      ).unwrap()
      assert_true(
        @execution.execution_capacity_retained_bytes(quote) >
        @execution.execution_capacity_retained_bytes(smaller),
      )
      assert_true(
        @execution.execution_capacity_execution_bytes(quote) >
        @execution.execution_capacity_retained_bytes(quote),
      )
      let request = prepare_record_key_upsert_request_from_before(
        proposal, before, write, exact,
      ).unwrap()
      assert_eq(
        @catalog.record_create_request_body(
          @catalog.record_key_upsert_create_request(request).unwrap(),
        ),
        expected,
      )
      assert_true(
        prepare_record_key_upsert_request_from_before(
          proposal, before, write, short,
        )
        is Err(Request(Request(BudgetExceeded))),
      )
      assert_true(
        prepare_record_key_upsert_request_from_before(
          proposal,
          before,
          { ..write, max_output_bytes: value_body.length() - 1, },
          exact,
        )
        is Err(Request(Write(BudgetExceeded))),
      )
    }
    let different = prepare_record_key_upsert_proposal(
      selected, "original-key", bytes, 10000, write_limits, limits,
    ).unwrap()
    assert_true(
      prepare_record_key_upsert_proposal_before(
        different,
        observed,
        delete_preview_values(),
        mutation,
      )
      is Err(Lookup(ForeignRequest)),
    )
    assert_true(
      record_key_upsert_update_construction_capacity(
        different, before, mutation,
      )
      is None,
    )
    assert_true(
      record_key_upsert_create_construction_capacity(
        different, before, write_limits, mutation,
      )
      is None,
    )
    assert_true(
      prepare_record_key_upsert_request_from_before(
        different, before, write_limits, mutation,
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

///|
test "saved keyed UPSERT restores only the original presence branch and exact native body" {
  let original = key_before_declaration(key_before_catalog(memo_required=true))
  let mapping = prepare_record_key_upsert_mapping(
    original,
    "customers",
    "customer_code",
    [{ target: "memo", field: "next_memo", null_behavior: "reject", }],
    delete_declaration_limits(),
  ).unwrap()
  let lookup = key_before_lookup_limits()
  let write = key_before_write_limits()
  let request_limits = create_construction_request()
  let restore = (present, operation, body, target_bytes, limits) => {
    let result = restore_record_key_upsert_execution(
      mapping,
      "original-key",
      b"{\"memo\":\"next\"}",
      target_bytes,
      operation,
      body,
      1000,
      lookup,
      key_before_page_limits(),
      delete_preview_values(),
      write,
      limits,
      delete_preview_limits(),
    )
    if result is Ok((proposal, before, request)) {
      assert_eq(record_key_upsert_before_target(before) is Some(_), present)
      assert_eq(
        record_key_upsert_proposal_value_wire(proposal),
        "{\"memo\":\"next\"}",
      )
      assert_true(
        record_key_upsert_execution_matches(proposal, before, request),
      )
    }
    result
  }
  for
    (present, operation, other, body) in [
      (
        false,
        @catalog.Insert,
        @catalog.Update,
        "{\"app\":\"12\",\"records\":[{\"memo\":{\"value\":\"next\"},\"customer_code\":{\"value\":\"original-key\"}}]}",
      ),
      (
        true,
        @catalog.Update,
        @catalog.Insert,
        "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"memo\":{\"value\":\"next\"}},\"revision\":\"9007199254740994\"}],\"upsert\":false}",
      ),
    ] {
    let original_bytes = key_before_response_body(present)
    let exact = { ..request_limits, max_output_bytes: body.length(), }
    let (proposal, before, request) = restore(
      present, operation, body, original_bytes, exact,
    ).unwrap()
    let (renewed, renewed_before, _) = restore(
      present, operation, body, original_bytes, exact,
    ).unwrap()
    assert_false(
      record_key_upsert_execution_matches(renewed, renewed_before, request),
    )
    assert_false(
      record_key_upsert_execution_matches(proposal, renewed_before, request),
    )
    assert_true(
      restore(present, other, body, original_bytes, exact)
      is Err(SavedRequestMismatch),
    )
    assert_true(
      restore(
        present,
        operation,
        body,
        key_before_response_body(!present),
        exact,
      )
      is Err(SavedRequestMismatch),
    )
    assert_true(
      restore(
        present,
        operation,
        body.replace(old="next", new="else"),
        original_bytes,
        exact,
      )
      is Err(SavedRequestMismatch),
    )
    assert_true(
      restore(present, operation, body, original_bytes, {
        ..exact,
        max_output_bytes: body.length() - 1,
      })
      is Err(Request(Request(BudgetExceeded))),
    )
    if before.target is Some(_) {
      let other_target = @catalog.prepare_original_record_target(
        @catalog.record_key_lookup_page(before.lookup),
        0,
        exact.max_identity_bytes,
      ).unwrap()
      let copied = @catalog.prepare_record_key_upsert_request(
        before.lookup,
        proposal.values,
        write,
        exact,
        target=Some(other_target),
      ).unwrap()
      assert_false(
        record_key_upsert_execution_matches(proposal, before, copied),
      )
    }
  }
  assert_true(
    restore(
      false,
      Insert,
      "{}",
      b"{\"records\":[],\"totalCount\":null}",
      request_limits,
    )
    is Err(Lookup(IncompleteResponse)),
  )
}

///|
test "UPSERT lookup proposal quote adds retained body and bounded writer work on the same values" {
  let original = key_before_declaration(key_before_catalog(memo_required=true))
  let mapping = prepare_record_key_upsert_mapping(
    original,
    "customers",
    "customer_code",
    [{ target: "memo", field: "next", null_behavior: "reject", }],
    delete_declaration_limits(),
  ).unwrap()
  let input = b"{\"memo\":\"next\"}"
  let key = "ord\\\"東京"
  let lookup = key_before_lookup_limits()
  let write = key_before_write_limits()
  let mutation = create_construction_request()
  let proposal = prepare_record_key_upsert_proposal(
    mapping,
    key,
    input,
    input.length(),
    write,
    lookup,
  ).unwrap()
  let body = @catalog.record_lookup_request_body(
    record_key_upsert_proposal_lookup(proposal),
  )
  let bound = @utf8.encode(body).length()
  assert_true(bound > 1)
  let exact = { ..lookup, max_request_bytes: bound, }
  assert_true(
    prepare_record_key_upsert_proposal(
      mapping,
      key,
      input,
      input.length(),
      write,
      exact,
    )
    is Ok(_),
  )
  let short = { ..exact, max_request_bytes: bound - 1, }
  assert_true(
    prepare_record_key_upsert_proposal(
      mapping,
      key,
      input,
      input.length(),
      write,
      short,
    )
    is Err(Lookup(BudgetExceeded)),
  )
  let quote = record_key_upsert_proposal_construction_capacity(
    mapping,
    input.length(),
    write,
    mutation,
    exact,
  ).unwrap()
  let tiny = record_key_upsert_proposal_construction_capacity(
    mapping,
    input.length(),
    write,
    mutation,
    short,
  ).unwrap()
  let base = update_construction_capacity(
    record_mutation_proposal_values_inventory(
      original,
      1,
      input.length(),
      write,
      mutation,
    ).unwrap(),
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let work = @execution.execution_capacity_execution_bytes(quote)
  assert_true(retained > @execution.execution_capacity_retained_bytes(base))
  assert_true(work > @execution.execution_capacity_execution_bytes(base))
  assert_true(work > retained)
  assert_true(@execution.execution_capacity_retained_bytes(tiny) < retained)
  assert_true(@execution.execution_capacity_execution_bytes(tiny) < work)
  assert_true(
    record_key_upsert_proposal_construction_capacity(
      mapping,
      input.length(),
      write,
      mutation,
      { ..exact, max_columns: 1, },
    )
    is None,
  )
}

///|
test "UPSERT before reuses the charged page reader and refuses incomplete absence" {
  let original = key_before_declaration(key_before_catalog(memo_required=true))
  let mapping = prepare_record_key_upsert_mapping(
    original,
    "customers",
    "customer_code",
    [{ target: "memo", field: "next", null_behavior: "reject", }],
    delete_declaration_limits(),
  ).unwrap()
  let values = delete_preview_values()
  let mutation = create_construction_request()
  let proposal = prepare_record_key_upsert_proposal(
    mapping,
    "original-key",
    b"{\"memo\":\"next\"}",
    1024,
    key_before_write_limits(),
    key_before_lookup_limits(),
  ).unwrap()
  let request = record_key_upsert_proposal_lookup(proposal)
  for present in [false, true] {
    let body = key_before_response_body(present)
    let pages = { ..key_before_page_limits(), max_bytes: body.length(), }
    let quote = record_key_upsert_before_construction_capacity(
      mapping,
      body.length(),
      pages,
      values,
      mutation,
    ).unwrap()
    assert_true(@execution.execution_capacity_retained_bytes(quote) > 0L)
    assert_true(
      @execution.execution_capacity_execution_bytes(quote) >
      @execution.execution_capacity_retained_bytes(quote),
    )
    let observed = @catalog.project_record_key_lookup(request, 200, body, pages).unwrap()
    let before = prepare_record_key_upsert_proposal_before(
      proposal, observed, values, mutation,
    ).unwrap()
    assert_true(record_key_upsert_before_matches(before, original, observed))
    assert_eq(record_key_upsert_before_target(before) is Some(_), present)
    let short = { ..pages, max_bytes: body.length() - 1, }
    assert_true(
      record_key_upsert_before_construction_capacity(
        mapping,
        body.length(),
        short,
        values,
        mutation,
      )
      is None,
    )
    assert_true(
      @catalog.project_record_key_lookup(request, 200, body, short) is Err(_),
    )
  }
  assert_true(
    @catalog.project_record_key_lookup(
      request,
      200,
      b"{\"records\":[],\"totalCount\":null}",
      key_before_page_limits(),
    )
    is Err(IncompleteResponse),
  )
}

///|
test "UPSERT plan budgets either final write and all co-held cold native outputs" {
  let original = key_before_declaration(key_before_catalog(memo_required=true))
  let mapping = prepare_record_key_upsert_mapping(
    original,
    "customers",
    "customer_code",
    [{ target: "memo", field: "next", null_behavior: "reject", }],
    delete_declaration_limits(),
  ).unwrap()
  let write = key_before_write_limits()
  let lookup = key_before_lookup_limits()
  let request = create_construction_request()
  let values = delete_preview_values()
  let bytes = b"{\"memo\":\"next\"}"
  let proposal = prepare_record_key_upsert_proposal(
    mapping,
    "original-key",
    bytes,
    bytes.length(),
    write,
    lookup,
  ).unwrap()
  let original_lookup = record_key_upsert_proposal_lookup(proposal)
  let (none, some) = (
    prepare_record_key_upsert_proposal_before(
      proposal,
      key_before_reply(original_lookup, false),
      values,
      request,
    ).unwrap(),
    prepare_record_key_upsert_proposal_before(
      proposal,
      key_before_reply(original_lookup, true),
      values,
      request,
    ).unwrap(),
  )
  let insert = record_key_upsert_create_construction_capacity(
    proposal, none, write, request,
  ).unwrap()
  let update = record_key_upsert_update_construction_capacity(
    proposal, some, request,
  ).unwrap()
  let finalization = record_key_upsert_finalization_construction_capacity(
    mapping, write, request,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes
  let execution = @execution.execution_capacity_execution_bytes
  assert_eq(
    retained(finalization),
    Int64::max(retained(insert), retained(update)),
  )
  assert_eq(
    execution(finalization),
    Int64::max(execution(insert), execution(update)),
  )

  let target_bytes = key_before_response_body(true).length()
  let pages = { ..key_before_page_limits(), max_bytes: target_bytes, }
  let proposed = record_key_upsert_proposal_construction_capacity(
    mapping,
    bytes.length(),
    write,
    request,
    lookup,
  ).unwrap()
  let observed = record_key_upsert_before_construction_capacity(
    mapping, target_bytes, pages, values, request,
  ).unwrap()
  let recovery = record_key_upsert_recovery_construction_capacity(
    mapping,
    target_bytes,
    bytes.length(),
    lookup,
    pages,
    values,
    write,
    request,
    request,
  ).unwrap()
  assert_true(
    retained(recovery) >
    retained(proposed) + retained(observed) + retained(finalization),
  )
  assert_true(execution(recovery) >= execution(proposed))
  assert_true(execution(recovery) >= retained(proposed) + execution(observed))
  assert_true(
    execution(recovery) >=
    retained(proposed) + retained(observed) + execution(finalization),
  )
  assert_true(
    execution(recovery) <
    execution(proposed) + execution(observed) + execution(finalization),
  )
  assert_true(
    record_key_upsert_recovery_construction_capacity(
      mapping,
      target_bytes + 1,
      bytes.length(),
      lookup,
      pages,
      values,
      write,
      request,
      request,
    )
    is None,
  )
}
