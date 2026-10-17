///|
fn write_test_limits() -> RecordWriteLimits {
  {
    max_fields: 30,
    max_name_bytes: 1000,
    max_nodes: 1000,
    max_depth: 12,
    max_text_bytes: 10000,
    max_output_bytes: 20000,
  }
}

///|
fn write_test_catalog() -> FormFieldCatalog {
  form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"text":{"type":"SINGLE_LINE_TEXT","code":"text","label":"Label"},"memo":{"type":"MULTI_LINE_TEXT","code":"memo"},"rich":{"type":"RICH_TEXT","code":"rich"},"link":{"type":"LINK","code":"link"},"radio":{"type":"RADIO_BUTTON","code":"radio"},"drop":{"type":"DROP_DOWN","code":"drop"},"date":{"type":"DATE","code":"date"},"stamp":{"type":"DATETIME","code":"stamp"},"checks":{"type":"CHECK_BOX","code":"checks"},"choices":{"type":"MULTI_SELECT","code":"choices"},"users":{"type":"USER_SELECT","code":"users"},"orgs":{"type":"ORGANIZATION_SELECT","code":"orgs"},"groups":{"type":"GROUP_SELECT","code":"groups"},"number":{"type":"NUMBER","code":"number"},"calc":{"type":"CALC","code":"calc"},"creator":{"type":"CREATOR","code":"creator"},"modifier":{"type":"MODIFIER","code":"modifier"},"created":{"type":"CREATED_TIME","code":"created"},"updated":{"type":"UPDATED_TIME","code":"updated"},"record_number":{"type":"RECORD_NUMBER","code":"record_number"},"status":{"type":"STATUS","code":"status"},"assignee":{"type":"STATUS_ASSIGNEE","code":"assignee"},"category":{"type":"CATEGORY","code":"category"},"files":{"type":"FILE","code":"files"},"time":{"type":"TIME","code":"time"},"e\u0301":{"type":"SINGLE_LINE_TEXT","code":"e\u0301"},"é":{"type":"SINGLE_LINE_TEXT","code":"é"},"table":{"type":"SUBTABLE","code":"table","fields":{"child":{"type":"SINGLE_LINE_TEXT","code":"child"}}}}}
    ),
  )
}

///|
fn write_checked(
  text : String,
  contract : @contract.Contract,
) -> @admitted.CheckedValue {
  let parsed = @source.parse_json_bytes_preserving(@utf8.encode(text), {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 12,
  }).unwrap()
  let cursor = @decode.admit(parsed, {
    max_nodes: 1000,
    max_depth: 12,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  @admitted.admit(contract, cursor, {
    max_nodes: 1000,
    max_depth: 12,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn write_text(value : String) -> @admitted.CheckedValue {
  @admitted.checked_text_value(
    value,
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
}

///|
fn write_array(json : String) -> @admitted.CheckedValue {
  write_checked(
    json,
    @contract.array_contract(
      @contract.primitive(@contract.StringType, nullable=false),
      nullable=false,
    ).unwrap(),
  )
}

///|
test "native write fields preserve exact original codes and text without type or label synthesis" {
  let catalog = write_test_catalog()
  let cells = [("é", write_text("é\r\n東京")), ("é", write_text("é"))]
  let original = prepare_record_write_values(
    catalog,
    cells,
    write_test_limits(),
  ).unwrap()
  assert_eq(
    record_write_values_body(original),
    "{\"é\":{\"value\":\"é\\r\\n東京\"},\"é\":{\"value\":\"é\"}}",
  )
  assert_eq(record_write_values_fields(original), ["é", "é"])
  cells.clear()
  record_write_values_fields(original).clear()
  assert_eq(record_write_values_fields(original), ["é", "é"])
  assert_true(record_write_values_match_catalog(original, catalog))
  assert_false(
    record_write_values_match_catalog(original, write_test_catalog()),
  )
  assert_true(
    prepare_record_write_values(
      catalog,
      [("Label", write_text("x"))],
      write_test_limits(),
    )
    is Err(FieldUnavailable("Label")),
  )
}

///|
test "native text writes keep supplied empties and never fill omitted default fields" {
  let catalog = write_test_catalog()
  let original = prepare_record_write_values(
    catalog,
    [
      ("text", write_text("")),
      ("memo", write_text("a\nb")),
      ("rich", write_text("<p>x</p>")),
      ("link", write_text("https://example.test/")),
    ],
    write_test_limits(),
  ).unwrap()
  assert_eq(
    record_write_values_body(original),
    "{\"text\":{\"value\":\"\"},\"memo\":{\"value\":\"a\\nb\"},\"rich\":{\"value\":\"<p>x</p>\"},\"link\":{\"value\":\"https://example.test/\"}}",
  )
  assert_eq(original.originals.length(), 4)
}

///|
test "selection arrays preserve order duplicates empty tokens and exact original account codes" {
  let values = write_array("[\"u2\",\"u1\",\"u2\",\"\"]")
  for code in ["checks", "choices"] {
    let document = prepare_record_write_values(
      write_test_catalog(),
      [(code, values)],
      write_test_limits(),
    ).unwrap()
    assert_eq(
      record_write_values_body(document),
      "{\"" + code + "\":{\"value\":[\"u2\",\"u1\",\"u2\",\"\"]}}",
    )
  }
  for code in ["users", "orgs", "groups"] {
    let document = prepare_record_write_values(
      write_test_catalog(),
      [(code, values)],
      write_test_limits(),
    ).unwrap()
    assert_eq(
      record_write_values_body(document),
      "{\"" +
      code +
      "\":{\"value\":[{\"code\":\"u2\"},{\"code\":\"u1\"},{\"code\":\"u2\"},{\"code\":\"\"}]}}",
    )
    assert_eq(
      record_write_values_body(
        prepare_record_write_values(
          write_test_catalog(),
          [(code, write_array("[]"))],
          write_test_limits(),
        ).unwrap(),
      ),
      "{\"" + code + "\":{\"value\":[]}}",
    )
  }
}

///|
test "dropdown clear is explicit null while radio empty cannot silently select its default" {
  let catalog = write_test_catalog()
  let null_text = write_checked(
    "null",
    @contract.primitive(@contract.StringType, nullable=true),
  )
  assert_eq(
    record_write_values_body(
      prepare_record_write_values(
        catalog,
        [("drop", null_text)],
        write_test_limits(),
      ).unwrap(),
    ),
    "{\"drop\":{\"value\":null}}",
  )
  for code in ["radio", "drop"] {
    assert_eq(
      record_write_values_body(
        prepare_record_write_values(
          catalog,
          [(code, write_text("value"))],
          write_test_limits(),
        ).unwrap(),
      ),
      "{\"" + code + "\":{\"value\":\"value\"}}",
    )
    assert_true(
      prepare_record_write_values(
        catalog,
        [(code, write_text(""))],
        write_test_limits(),
      )
      is Err(UnrepresentableValue(_)),
    )
  }
  assert_true(
    prepare_record_write_values(
      catalog,
      [("radio", null_text)],
      write_test_limits(),
    )
    is Err(UnrepresentableValue("radio")),
  )
  assert_true(
    prepare_record_write_values(
      catalog,
      [("text", null_text)],
      write_test_limits(),
    )
    is Err(InvalidValue("text")),
  )
}

///|
test "Date and Timestamp writes preserve typed meaning and refuse fractional-second loss" {
  let date = @contract.primitive(@contract.DateType, nullable=true)
  let timestamp = @contract.primitive(@contract.TimestampType, nullable=true)
  let catalog = write_test_catalog()
  let body = prepare_record_write_values(
    catalog,
    [
      ("date", write_checked("\"2024-02-29\"", date)),
      ("stamp", write_checked("\"2026-10-17T01:02:03.000Z\"", timestamp)),
    ],
    write_test_limits(),
  ).unwrap()
  assert_eq(
    record_write_values_body(body),
    "{\"date\":{\"value\":\"2024-02-29\"},\"stamp\":{\"value\":\"2026-10-17T01:02:03Z\"}}",
  )
  for (code, contract) in [("date", date), ("stamp", timestamp)] {
    assert_eq(
      record_write_values_body(
        prepare_record_write_values(
          catalog,
          [(code, write_checked("null", contract))],
          write_test_limits(),
        ).unwrap(),
      ),
      "{\"" + code + "\":{\"value\":null}}",
    )
  }
  assert_true(
    prepare_record_write_values(
      catalog,
      [("stamp", write_checked("\"2026-10-17T01:02:03.001Z\"", timestamp))],
      write_test_limits(),
    )
    is Err(UnrepresentableValue("stamp")),
  )
  assert_true(
    prepare_record_write_values(
      catalog,
      [("date", write_checked("\"0999-12-31\"", date))],
      write_test_limits(),
    )
    is Err(UnrepresentableValue("date")),
  )
  assert_true(
    prepare_record_write_values(
      catalog,
      [("date", write_text("2024-02-29"))],
      write_test_limits(),
    )
    is Err(InvalidValue("date")),
  )
}

///|
test "read-only fields and missing original carrier connections cannot become native writes" {
  for
    code in [
      "$id", "$revision", "record_number", "calc", "creator", "modifier", "created",
      "updated", "status", "category", "assignee", "number", "time", "files", "table",
      "child",
    ] {
    assert_true(
      prepare_record_write_values(
        write_test_catalog(),
        [(code, write_text("7"))],
        write_test_limits(),
      )
      is Err(FieldUnavailable(_)),
    )
  }
  assert_true(
    prepare_record_write_values(
      write_test_catalog(),
      [("text", write_array("[]"))],
      write_test_limits(),
    )
    is Err(InvalidValue("text")),
  )
  assert_true(
    prepare_record_write_values(
      write_test_catalog(),
      [("users", write_text("u1"))],
      write_test_limits(),
    )
    is Err(InvalidValue("users")),
  )
}

///|
test "write encoding bounds the whole field inventory and retains no partial document" {
  let catalog = write_test_catalog()
  let one = [("text", write_text("abcdef"))]
  assert_true(
    prepare_record_write_values(catalog, [], write_test_limits())
    is Err(EmptyWrite),
  )
  assert_true(
    prepare_record_write_values(
      catalog,
      [("text", write_text("a")), ("text", write_text("b"))],
      write_test_limits(),
    )
    is Err(DuplicateField("text")),
  )
  for
    limits in [
      { ..write_test_limits(), max_fields: 0, },
      { ..write_test_limits(), max_depth: 0, },
    ] {
    assert_true(
      prepare_record_write_values(catalog, one, limits) is Err(InvalidLimits),
    )
  }
  for
    limits in [
      { ..write_test_limits(), max_name_bytes: 1, },
      { ..write_test_limits(), max_output_bytes: 1, },
      { ..write_test_limits(), max_nodes: 1, },
      { ..write_test_limits(), max_depth: 1, },
    ] {
    assert_true(prepare_record_write_values(catalog, one, limits) is Err(_))
  }
  assert_true(
    prepare_record_write_values(
      catalog,
      [("text", write_text("a")), ("memo", write_text("b"))],
      { ..write_test_limits(), max_text_bytes: 9, },
    )
    is Err(InvalidValue("memo")),
  )
}

///|
test "independent native response returns the same typed carriers through the original read owner" {
  let catalog = write_test_catalog()
  let date = @contract.primitive(@contract.DateType, nullable=true)
  let timestamp = @contract.primitive(@contract.TimestampType, nullable=true)
  let write = prepare_record_write_values(
    catalog,
    [
      ("text", write_text("é\r\n")),
      (
        "drop",
        write_checked(
          "null",
          @contract.primitive(@contract.StringType, nullable=true),
        ),
      ),
      ("date", write_checked("\"2024-02-29\"", date)),
      ("stamp", write_checked("\"2026-10-17T01:02:03.000Z\"", timestamp)),
      ("users", write_array("[\"u2\",\"u1\",\"u2\"]")),
    ],
    write_test_limits(),
  ).unwrap()
  assert_eq(
    record_write_values_body(write),
    "{\"text\":{\"value\":\"é\\r\\n\"},\"drop\":{\"value\":null},\"date\":{\"value\":\"2024-02-29\"},\"stamp\":{\"value\":\"2026-10-17T01:02:03Z\"},\"users\":{\"value\":[{\"code\":\"u2\"},{\"code\":\"u1\"},{\"code\":\"u2\"}]}}",
  )
  // Independent native response bytes, not expectations derived from write.
  let bytes = @utf8.encode(
    (
      #|{"records":[{"$id":{"type":"__ID__","value":"9007199254740993"},"$revision":{"type":"__REVISION__","value":"9"},"text":{"type":"SINGLE_LINE_TEXT","value":"e\u0301\r\n"},"drop":{"type":"DROP_DOWN","value":null},"date":{"type":"DATE","value":"2024-02-29"},"stamp":{"type":"DATETIME","value":"2026-10-17T01:02:03Z"},"users":{"type":"USER_SELECT","value":[{"code":"u2","name":"second"},{"code":"u1","name":"first"},{"code":"u2","name":"second"}]}}],"totalCount":null}
    ),
  )
  let page = project_record_page(
    bytes,
    catalog,
    ["text", "drop", "date", "stamp", "users"],
    record_test_limits(),
  ).unwrap()
  let checked = project_checked_record_page(page, None, values_test_limits()).unwrap()
  let rows = checked_record_rows(checked)
  assert_true(rows[0][0].value is @admitted.Text("9007199254740993"))
  assert_true(rows[0][1].value is @admitted.Text("é\r\n"))
  assert_true(rows[0][2].value is @admitted.Null)
  assert_true(rows[0][3].value is @admitted.Date("2024-02-29"))
  assert_true(
    rows[0][4].value is @admitted.Timestamp("2026-10-17T01:02:03.000Z"),
  )
  guard rows[0][5].value is @admitted.Array(users) else {
    abort("expected users")
  }
  assert_eq(@admitted.element_count(users), 3)
  assert_true(@admitted.element_at(users, 0) is Some(@admitted.Text("u2")))
  assert_true(@admitted.element_at(users, 1) is Some(@admitted.Text("u1")))
  assert_true(@admitted.element_at(users, 2) is Some(@admitted.Text("u2")))
  assert_true(record_write_values_match_catalog(write, catalog))
}
