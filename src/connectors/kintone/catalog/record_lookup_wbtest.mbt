///|
fn lookup_test_limits() -> RecordLookupLimits {
  {
    max_key_bytes: 1000,
    max_columns: 10,
    max_comparison_work: 10000,
    max_request_bytes: 20000,
    max_request_nodes: 100,
    max_request_depth: 10,
  }
}

///|
fn lookup_test_request(value? : String = "original-key") -> RecordLookupRequest {
  prepare_record_text_key_lookup(
    form_test_catalog(),
    "customer_code",
    value,
    ["memo"],
    lookup_test_limits(),
  ).unwrap()
}

///|
fn lookup_test_row(
  value? : String = "original-key",
  id? : String = "9007199254740993",
  revision? : String = "9007199254740994",
) -> String {
  "{\"$id\":{\"type\":\"__ID__\",\"value\":\"" +
  id +
  "\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"" +
  revision +
  "\"},\"customer_code\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"" +
  value +
  "\"},\"memo\":{\"type\":\"MULTI_LINE_TEXT\",\"value\":\"unchanged\"}}"
}

///|
fn lookup_test_response(
  request : RecordLookupRequest,
  rows : Array[String],
  total? : String = "1",
) -> Result[RecordLookupObservation, RecordLookupIssue] {
  project_record_key_lookup(
    request,
    200,
    @utf8.encode(
      "{\"records\":[" + rows.join(",") + "],\"totalCount\":\"" + total + "\"}",
    ),
    record_test_limits(),
  )
}

///|
test "unique Text lookup pins exact original value with separate query and JSON escaping" {
  let catalog = form_test_catalog()
  let names = ["memo"]
  let request = prepare_record_text_key_lookup(
    catalog,
    "customer_code",
    "東京\"\\ or customer_code != \"\"",
    names,
    lookup_test_limits(),
  ).unwrap()
  names[0] = "foreign"
  assert_eq(
    record_lookup_request_body(request),
    (
      #|{"app":"12","fields":["$id","$revision","memo","customer_code"],"query":"customer_code = \"東京\\\"\\\\ or customer_code != \\\"\\\"\" limit 2","totalCount":true}
    ),
  )
  assert_true(physical_equal(request.catalog, catalog))
  assert_true(record_lookup_request_uses_catalog(request, catalog))
  assert_true(!record_lookup_request_uses_catalog(request, form_test_catalog()))
  assert_eq(request.names, ["memo", "customer_code"])
  let unicode = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"顧客_Ａ·コード":{"type":"SINGLE_LINE_TEXT","code":"顧客_Ａ·コード","unique":true}}}
    ),
  )
  let request = prepare_record_text_key_lookup(
    unicode,
    "顧客_Ａ·コード",
    "é",
    [],
    lookup_test_limits(),
  ).unwrap()
  assert_true(
    record_lookup_request_body(request).contains("顧客_Ａ·コード"),
  )
  assert_eq(request.value, "é")
  let request = lookup_test_request(value="\\\\\"\"")
  assert_eq(
    record_lookup_request_body(request),
    (
      #|{"app":"12","fields":["$id","$revision","memo","customer_code"],"query":"customer_code = \"\\\\\\\\\\\"\\\"\" limit 2","totalCount":true}
    ),
  )
}

///|
test "lookup requires positive original Text uniqueness without reclassifying Number or Record Number" {
  for
    metadata in [
      "\"type\":\"SINGLE_LINE_TEXT\",\"unique\":false", "\"type\":\"SINGLE_LINE_TEXT\"",
      "\"type\":\"RECORD_NUMBER\",\"unique\":true",
    ] {
    let catalog = form_test_catalog(
      body="{\"revision\":\"7\",\"properties\":{\"key\":{\"code\":\"key\"," +
        metadata +
        "}}}",
    )
    assert_true(
      prepare_record_text_key_lookup(
        catalog,
        "key",
        "a",
        [],
        lookup_test_limits(),
      )
      is Err(Form(UniqueKeyUnconfirmed)),
    )
  }
  let numeric = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"key":{"code":"key","type":"NUMBER","unique":true}}}
    ),
  )
  assert_true(
    prepare_record_text_key_lookup(
      numeric,
      "key",
      "1.007",
      [],
      lookup_test_limits(),
    )
    is Err(InvalidKey),
  )
  for value in ["", "line\nnext", "bad\u0000"] {
    assert_true(
      prepare_record_text_key_lookup(
        form_test_catalog(),
        "customer_code",
        value,
        [],
        lookup_test_limits(),
      )
      is Err(InvalidKey),
    )
  }
}

///|
test "complete zero and one response keep same original request page and exact native locator" {
  let request = lookup_test_request()
  let empty = lookup_test_response(request, [], total="0").unwrap()
  assert_true(record_key_lookup_uses_request(empty, request))
  let page = record_key_lookup_page(empty)
  assert_eq(record_page_records(page).length(), 0)
  assert_eq(page.total_count, Some("0"))
  let original_bytes = "{\"records\":[],\"totalCount\":\"0\"}"
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(original_bytes)))
  let present = lookup_test_response(request, [lookup_test_row()]).unwrap()
  let original_page = record_key_lookup_page(present)
  let target = prepare_original_record_target(original_page, 0, 100).unwrap()
  assert_eq(original_record_target_id(target), "9007199254740993")
  assert_eq(original_record_target_revision(target), "9007199254740994")
  assert_true(
    physical_equal(original_record_target_page(target), original_page),
  )
  assert_true(record_page_uses_catalog(original_page, request.catalog))
  record_page_records(original_page).clear()
  assert_eq(record_page_records(record_key_lookup_page(present)).length(), 1)
}

///|
test "404 partial missing count contradictory counts and duplicate records never produce absence" {
  let request = lookup_test_request()
  for status in [0, 202, 204, 207, 400, 404, 500] {
    assert_true(
      project_record_key_lookup(
        request,
        status,
        b"{\"records\":[],\"totalCount\":\"0\"}",
        record_test_limits(),
      )
      is Err(UnexpectedStatus),
    )
  }
  for body in ["{}", "[]", "null", "{\"records\":[]}"] {
    assert_true(
      project_record_key_lookup(
        request,
        200,
        @utf8.encode(body),
        record_test_limits(),
      )
      is Err(Page(InvalidResponse)),
    )
  }
  assert_true(
    project_record_key_lookup(
      request,
      200,
      b"{\"records\":[],\"totalCount\":null}",
      record_test_limits(),
    )
    is Err(IncompleteResponse),
  )
  for total in ["1", "2", "1000000000000000000000000"] {
    assert_true(
      lookup_test_response(request, [], total~) is Err(IncompleteResponse),
    )
  }
  assert_true(
    lookup_test_response(request, [lookup_test_row()], total="0")
    is Err(IncompleteResponse),
  )
  assert_true(
    lookup_test_response(
      request,
      [lookup_test_row(), lookup_test_row(id="7")],
      total="2",
    )
    is Err(IncompleteResponse),
  )
  assert_true(lookup_test_response(request, [], total="000") is Ok(_))
  assert_true(
    lookup_test_response(request, [lookup_test_row()], total="001") is Ok(_),
  )
}

///|
test "lookup response must contain the exact selected key and every requested field" {
  let request = lookup_test_request(value="é")
  assert_true(
    lookup_test_response(request, [lookup_test_row(value="é")])
    is Err(ForeignRecord),
  )
  assert_true(
    lookup_test_response(request, [lookup_test_row(value="é ")])
    is Err(ForeignRecord),
  )
  let missing = lookup_test_row(value="é").replace(
    old="\"memo\":",
    new="\"other\":",
  )
  assert_true(
    lookup_test_response(request, [missing]) is Err(Page(MissingField("memo"))),
  )
  let wrong = lookup_test_row(value="é").replace(
    old="SINGLE_LINE_TEXT",
    new="NUMBER",
  )
  assert_true(
    lookup_test_response(request, [wrong])
    is Err(Page(InvalidField("customer_code"))),
  )
}

///|
test "reobservation compares the same original request and refuses changed presence locator or revision" {
  let request = lookup_test_request()
  let empty = lookup_test_response(request, [], total="0").unwrap()
  let present = lookup_test_response(request, [lookup_test_row()]).unwrap()
  assert_true(
    match_record_key_lookup(
      empty,
      lookup_test_response(request, [], total="0").unwrap(),
    )
    is Ok(_),
  )
  assert_true(
    match_record_key_lookup(
      present,
      lookup_test_response(request, [lookup_test_row()]).unwrap(),
    )
    is Ok(_),
  )
  assert_true(
    match_record_key_lookup(empty, present) is Err(ChangedObservation),
  )
  assert_true(
    match_record_key_lookup(present, empty) is Err(ChangedObservation),
  )
  for
    row in [
      lookup_test_row(id="7"),
      lookup_test_row(revision="9007199254740995"),
    ] {
    assert_true(
      match_record_key_lookup(
        present,
        lookup_test_response(request, [row]).unwrap(),
      )
      is Err(ChangedObservation),
    )
  }
  let foreign = lookup_test_request()
  assert_eq(
    record_lookup_request_body(request),
    record_lookup_request_body(foreign),
  )
  assert_true(!record_key_lookup_uses_request(empty, foreign))
  assert_true(
    match_record_key_lookup(
      empty,
      lookup_test_response(foreign, [], total="0").unwrap(),
    )
    is Err(ForeignRequest),
  )
}

///|
test "positive byte column comparison request and page bounds refuse without partial lookup material" {
  let catalog = form_test_catalog()
  let limits = lookup_test_limits()
  for
    bounded in [
      { ..limits, max_key_bytes: 0, },
      { ..limits, max_columns: 999, },
      { ..limits, max_comparison_work: 0, },
      { ..limits, max_request_bytes: 0, },
      { ..limits, max_request_nodes: 0, },
      { ..limits, max_request_depth: 0, },
    ] {
    assert_true(
      prepare_record_text_key_lookup(catalog, "customer_code", "a", [], bounded)
      is Err(InvalidLimits),
    )
  }
  for
    bounded in [
      { ..limits, max_key_bytes: 1, },
      { ..limits, max_comparison_work: 1, },
      { ..limits, max_request_bytes: 1, },
      { ..limits, max_request_nodes: 1, },
      { ..limits, max_request_depth: 1, },
    ] {
    assert_true(
      prepare_record_text_key_lookup(
        catalog,
        "customer_code",
        "é",
        [],
        bounded,
      )
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    prepare_record_text_key_lookup(catalog, "customer_code", "a", ["memo"], {
      ..limits,
      max_columns: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_text_key_lookup(
      catalog,
      "customer_code",
      "a",
      ["memo", "memo"],
      limits,
    )
    is Err(InvalidSelection),
  )
  assert_true(
    prepare_record_text_key_lookup(
      catalog,
      "customer_code",
      "a",
      ["foreign"],
      limits,
    )
    is Err(InvalidSelection),
  )
  let request = lookup_test_request()
  assert_true(
    project_record_key_lookup(
      request,
      200,
      b"{\"records\":[],\"totalCount\":\"0\"}",
      { ..record_test_limits(), max_bytes: 1, },
    )
    is Err(Page(BudgetExceeded)),
  )
  let minimal = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"customer_code":{"type":"SINGLE_LINE_TEXT","code":"customer_code","unique":true}}}
    ),
  )
  assert_true(
    prepare_record_text_key_lookup(catalog, "customer_code", "a", [], {
      ..limits,
      max_comparison_work: 32,
    })
    is Err(BudgetExceeded),
  )
  let request = prepare_record_text_key_lookup(
    minimal,
    "customer_code",
    "long-original-key",
    [],
    { ..limits, max_comparison_work: 32, },
  ).unwrap()
  assert_true(
    lookup_test_response(request, [lookup_test_row(value="long-original-key")])
    is Err(BudgetExceeded),
  )
}

///|
test "query field-code syntax is neither caller query text nor a normalized alias" {
  for
    code in [
      "key or other", "key=other", "key\"", "key\\", "key\n", "key\u3000other", "key\u2028other",
      "key\u00a0other", "1key",
    ] {
    let original = form_test_catalog()
    let field = original.fields[0]
    // Whitebox adversarial original metadata exercises the interpolation
    // fence without inventing a public Catalog constructor.
    let catalog : FormFieldCatalog = {
      ..original,
      fields: [{ ..field, code, path: [code], }],
    }
    assert_true(
      prepare_record_text_key_lookup(
        catalog,
        code,
        "a",
        [],
        lookup_test_limits(),
      )
      is Err(InvalidKey),
    )
  }
}
