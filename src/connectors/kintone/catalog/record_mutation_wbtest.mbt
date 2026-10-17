///|
fn mutation_limits() -> RecordMutationLimits {
  {
    max_records: 100,
    max_identity_bytes: 10000,
    max_comparison_work: 100000,
    max_output_bytes: 20000,
    max_output_nodes: 2000,
    max_output_depth: 10,
  }
}

///|
fn mutation_row(id : String, revision? : String = "9007199254740993") -> String {
  "{\"$id\":{\"type\":\"__ID__\",\"value\":\"" +
  id +
  "\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"" +
  revision +
  "\"},\"number\":{\"type\":\"RECORD_NUMBER\",\"value\":\"APP-7\"},\"text\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"東京\\r\\nnext\"}}"
}

///|
fn mutation_page(
  catalog : FormFieldCatalog,
  rows : Array[String],
) -> OriginalRecordPage {
  project_record_page(
    @utf8.encode("{\"records\":[" + rows.join(",") + "],\"totalCount\":null}"),
    catalog,
    ["number", "text"],
    {
      ..record_test_limits(),
      max_bytes: 100000,
      max_nodes: 10000,
      max_rows: 200,
      max_cells: 1000,
    },
  ).unwrap()
}

///|
test "mutation targets retain the exact original API ID revision and page not Record Number" {
  let page = mutation_page(record_test_catalog(), [
    mutation_row("9007199254740992"),
  ])
  let target = prepare_original_record_target(page, 0, 100).unwrap()
  assert_true(physical_equal(original_record_target_page(target), page))
  assert_eq(original_record_target_id(target), "9007199254740992")
  assert_eq(original_record_target_revision(target), "9007199254740993")
  assert_true(
    prepare_original_record_target(page, -1, 100) is Err(InvalidIndex),
  )
  assert_true(prepare_original_record_target(page, 1, 100) is Err(InvalidIndex))
  assert_true(prepare_original_record_target(page, 0, 0) is Err(InvalidLimits))
  assert_true(prepare_original_record_target(page, 0, 1) is Err(BudgetExceeded))
  let records = record_page_records(page)
  records.clear()
  assert_eq(original_record_target_id(target), "9007199254740992")
}

///|
test "target revision check needs the original Catalog and existing matching record" {
  let catalog = record_test_catalog()
  let page = mutation_page(catalog, [mutation_row("9007199254740992")])
  let target = prepare_original_record_target(page, 0, 100).unwrap()
  let fresh = mutation_page(catalog, [mutation_row("9007199254740992")])
  assert_true(
    match_original_record_target_revision(target, fresh, 100) is Ok(_),
  )
  assert_true(
    match_original_record_target_revision(
      target,
      mutation_page(catalog, [
        mutation_row("9007199254740992", revision="9007199254740994"),
      ]),
      100,
    )
    is Err(ChangedRevision),
  )
  assert_true(
    match_original_record_target_revision(
      target,
      mutation_page(catalog, []),
      100,
    )
    is Err(MissingTarget),
  )
  let equal_foreign = mutation_page(record_test_catalog(), [
    mutation_row("9007199254740992"),
  ])
  assert_true(
    match_original_record_target_revision(target, equal_foreign, 100)
    is Err(ForeignCatalog),
  )
  assert_true(
    match_original_record_target_revision(target, fresh, 0)
    is Err(InvalidLimits),
  )
  assert_true(
    match_original_record_target_revision(target, fresh, 1)
    is Err(BudgetExceeded),
  )
}

///|
test "a missing or unchecked native revision cannot become an original mutation target" {
  let catalog = record_test_catalog()
  for revision in ["", "-1", "1.0", "1e0", "NaN"] {
    assert_true(
      project_record_page(
        @utf8.encode(
          "{\"records\":[" +
          mutation_row("7", revision~) +
          "],\"totalCount\":null}",
        ),
        catalog,
        ["number", "text"],
        record_test_limits(),
      )
      is Err(InvalidField("$revision")),
    )
  }
  let row = mutation_row("7").replace(old="\"$revision\":", new="\"other\":")
  assert_true(
    project_record_page(
      @utf8.encode("{\"records\":[" + row + "],\"totalCount\":null}"),
      catalog,
      ["number", "text"],
      record_test_limits(),
    )
    is Err(MissingField("$revision")),
  )
}

///|
test "delete requests preserve paired original wide IDs and mandatory revision order" {
  let page = mutation_page(record_test_catalog(), [
    mutation_row("9007199254740992", revision="7"),
    mutation_row("9007199254740993", revision="9007199254740994"),
  ])
  let second = prepare_original_record_target(page, 1, 100).unwrap()
  let first = prepare_original_record_target(page, 0, 100).unwrap()
  let targets = [second, first]
  let request = prepare_record_delete_request(targets, mutation_limits()).unwrap()
  let expected = "{\"app\":\"12\",\"ids\":[\"9007199254740993\",\"9007199254740992\"],\"revisions\":[\"9007199254740994\",\"7\"]}"
  assert_eq(record_delete_request_body(request), expected)
  assert_true(physical_equal(record_delete_request_targets(request)[0], second))
  targets.clear()
  record_delete_request_targets(request).clear()
  assert_eq(record_delete_request_body(request), expected)
  assert_eq(record_delete_request_targets(request).length(), 2)
}

///|
test "delete batches refuse equal foreign catalogs and exact or numeric duplicate IDs" {
  let catalog = record_test_catalog()
  let original = mutation_page(catalog, [mutation_row("9007199254740992")])
  let first = prepare_original_record_target(original, 0, 100).unwrap()
  let foreign = prepare_original_record_target(
    mutation_page(record_test_catalog(), [mutation_row("8")]),
    0,
    100,
  ).unwrap()
  assert_true(
    prepare_record_delete_request([first, foreign], mutation_limits())
    is Err(ForeignCatalog),
  )
  assert_true(
    prepare_record_delete_request([first, first], mutation_limits())
    is Err(DuplicateTarget),
  )
  let equal_id = prepare_original_record_target(
    mutation_page(catalog, [mutation_row("0009007199254740992")]),
    0,
    100,
  ).unwrap()
  assert_true(
    prepare_record_delete_request([first, equal_id], mutation_limits())
    is Err(DuplicateTarget),
  )
  assert_eq(original_record_target_id(equal_id), "0009007199254740992")
}

///|
test "delete request bounds refuse before encoding without dropping target revisions" {
  let page = mutation_page(record_test_catalog(), [
    mutation_row("7"),
    mutation_row("8"),
  ])
  let first = prepare_original_record_target(page, 0, 100).unwrap()
  let second = prepare_original_record_target(page, 1, 100).unwrap()
  let limits = mutation_limits()
  assert_true(prepare_record_delete_request([], limits) is Err(InvalidRequest))
  assert_true(
    prepare_record_delete_request([first], { ..limits, max_records: 101, })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_record_delete_request([first, second], { ..limits, max_records: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_delete_request([first], { ..limits, max_identity_bytes: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_delete_request([first, second], {
      ..limits,
      max_comparison_work: 1,
    })
    is Err(BudgetExceeded),
  )
  for
    short in [
      { ..limits, max_output_bytes: 1, },
      { ..limits, max_output_nodes: 1, },
      { ..limits, max_output_depth: 1, },
    ] {
    assert_true(
      prepare_record_delete_request([first], short) is Err(BudgetExceeded),
    )
  }
  let request = prepare_record_delete_request([first], limits).unwrap()
  let size = @utf8.encode(record_delete_request_body(request)).length()
  assert_true(
    prepare_record_delete_request([first], {
      ..limits,
      max_output_bytes: size - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_record_delete_request([first], { ..limits, max_output_bytes: size, })
    is Ok(_),
  )
}

///|
test "the provider hundred-record deletion bound does not truncate a larger candidate" {
  let rows = []
  for index in 0..<101 {
    rows.push(mutation_row((index + 1).to_string(), revision="7"))
  }
  let page = mutation_page(record_test_catalog(), rows)
  let targets = []
  for index in 0..<100 {
    targets.push(prepare_original_record_target(page, index, 100).unwrap())
  }
  assert_eq(
    record_delete_request_targets(
      prepare_record_delete_request(targets, mutation_limits()).unwrap(),
    ).length(),
    100,
  )
  targets.push(prepare_original_record_target(page, 100, 100).unwrap())
  assert_true(
    prepare_record_delete_request(targets, mutation_limits())
    is Err(BudgetExceeded),
  )
}

///|
test "delete response observation retains its original request and exact raw digest" {
  let page = mutation_page(record_test_catalog(), [mutation_row("7")])
  let target = prepare_original_record_target(page, 0, 100).unwrap()
  let request = prepare_record_delete_request([target], mutation_limits()).unwrap()
  let body = b" \r\n{}\t"
  let response = project_record_delete_acknowledgement(
    request, 200, body, 100, 10, 5,
  ).unwrap()
  assert_true(
    physical_equal(record_delete_acknowledgement_request(response), request),
  )
  assert_eq(response.response_sha256, @sha.hex(body))
}

///|
test "an error empty reply partial object or non-success status is not a delete acknowledgement" {
  let page = mutation_page(record_test_catalog(), [mutation_row("7")])
  let target = prepare_original_record_target(page, 0, 100).unwrap()
  let request = prepare_record_delete_request([target], mutation_limits()).unwrap()
  for status in [201, 202, 204, 400, 403, 409, 429, 500] {
    assert_true(
      project_record_delete_acknowledgement(request, status, b"{}", 100, 20, 5)
      is Err(UnexpectedStatus),
    )
  }
  for
    body in [
      b"", b"{", b"{}{}", b"[]", b"null", b"{\"ok\":true}", b"{\"code\":\"GAIA_CO02\"}",
      b"\xff",
    ] {
    assert_true(
      project_record_delete_acknowledgement(request, 200, body, 100, 20, 5)
      is Err(InvalidResponse),
    )
  }
  assert_true(
    project_record_delete_acknowledgement(request, 200, b"{}", 1, 20, 5)
    is Err(BudgetExceeded),
  )
  assert_true(
    project_record_delete_acknowledgement(request, 200, b"{}", 100, 0, 5)
    is Err(InvalidLimits),
  )
  assert_eq(record_delete_request_targets(request).length(), 1)
}

///|
test "delete target observation query retains original IDs and complete bounded fields" {
  let page = mutation_page(record_test_catalog(), [
    mutation_row("9007199254740992"),
    mutation_row("9007199254740993"),
  ])
  let request = prepare_record_delete_request(
    [
      prepare_original_record_target(page, 0, 100).unwrap(),
      prepare_original_record_target(page, 1, 100).unwrap(),
    ],
    mutation_limits(),
  ).unwrap()
  let body = record_delete_observation_body(request, 10, 1000, 100, 10).unwrap()
  assert_eq(
    body, "{\"app\":\"12\",\"fields\":[\"$id\",\"$revision\",\"number\",\"text\"],\"query\":\"$id in (9007199254740992,9007199254740993) order by $id asc limit 2\"}",
  )
  assert_eq(record_delete_request_app_id(request), "12")
  assert_eq(record_delete_request_count(request), 2)
  assert_true(
    record_delete_observation_body(request, 0, 1000, 100, 10)
    is Err(InvalidLimits),
  )
  assert_true(
    record_delete_observation_body(request, 999, 1000, 100, 10)
    is Err(InvalidLimits),
  )
  assert_true(
    record_delete_observation_body(request, 1, 1000, 100, 10)
    is Err(BudgetExceeded),
  )
  assert_true(
    record_delete_observation_body(request, 10, 10, 100, 10)
    is Err(BudgetExceeded),
  )
  let size = @utf8.encode(body).length()
  assert_true(
    record_delete_observation_body(request, 10, size - 1, 100, 10)
    is Err(BudgetExceeded),
  )
  assert_eq(
    record_delete_observation_body(request, 10, size, 100, 10).unwrap(),
    body,
  )
}

///|
test "delete current Form requires the original revision and exact field definitions" {
  let catalog = form_test_catalog(
    body="{\"revision\":\"7\",\"properties\":{\"text\":{\"code\":\"text\",\"type\":\"SINGLE_LINE_TEXT\"},\"number\":{\"code\":\"number\",\"type\":\"RECORD_NUMBER\"}}}",
  )
  let page = mutation_page(catalog, [mutation_row("7")])
  let request = prepare_record_delete_request(
    [prepare_original_record_target(page, 0, 100).unwrap()],
    mutation_limits(),
  ).unwrap()
  let body = "{\"revision\":\"7\",\"properties\":{\"number\":{\"code\":\"number\",\"type\":\"RECORD_NUMBER\"},\"text\":{\"code\":\"text\",\"type\":\"SINGLE_LINE_TEXT\"}}}"
  assert_true(
    recheck_record_delete_form(request, @utf8.encode(body), form_test_limits())
    is Ok(_),
  )
  for
    changed in [
      body.replace(old="\"7\"", new="\"8\""),
      body.replace(old="SINGLE_LINE_TEXT", new="MULTI_LINE_TEXT"),
    ] {
    assert_true(
      recheck_record_delete_form(
        request,
        @utf8.encode(changed),
        form_test_limits(),
      )
      is Err(ForeignCatalog),
    )
  }
  assert_true(
    recheck_record_delete_form(request, b"{", form_test_limits())
    is Err(Form(_)),
  )
}

///|
test "delete current record correlation refuses omission substitution duplicate and revision drift" {
  let catalog = record_test_catalog()
  let first = mutation_row("9007199254740992", revision="7")
  let second = mutation_row("9007199254740993", revision="8")
  let page = mutation_page(catalog, [first, second])
  let request = prepare_record_delete_request(
    [
      prepare_original_record_target(page, 0, 100).unwrap(),
      prepare_original_record_target(page, 1, 100).unwrap(),
    ],
    mutation_limits(),
  ).unwrap()
  let envelope = fn(rows : Array[String]) {
    @utf8.encode("{\"records\":[" + rows.join(",") + "],\"totalCount\":null}")
  }
  assert_true(
    recheck_record_delete_records(
      request,
      envelope([second, first]),
      record_test_limits(),
      10,
      1000,
    )
    is Ok(_),
  )
  assert_true(
    recheck_record_delete_records(
      request,
      envelope([first]),
      record_test_limits(),
      10,
      1000,
    )
    is Err(UncorrelatedResult),
  )
  assert_true(
    recheck_record_delete_records(
      request,
      envelope([first, second, mutation_row("9")]),
      record_test_limits(),
      10,
      1000,
    )
    is Err(UncorrelatedResult),
  )
  assert_true(
    recheck_record_delete_records(
      request,
      envelope([first, mutation_row("9")]),
      record_test_limits(),
      10,
      1000,
    )
    is Err(MissingTarget),
  )
  assert_true(
    recheck_record_delete_records(
      request,
      envelope([first, first]),
      record_test_limits(),
      10,
      1000,
    )
    is Err(Page(_)),
  )
  assert_true(
    recheck_record_delete_records(
      request,
      envelope([first, mutation_row("9007199254740993", revision="9")]),
      record_test_limits(),
      10,
      1000,
    )
    is Err(ChangedRevision),
  )
  assert_true(
    recheck_record_delete_records(
      request,
      envelope([first, second]),
      record_test_limits(),
      10,
      1,
    )
    is Err(BudgetExceeded),
  )
}
