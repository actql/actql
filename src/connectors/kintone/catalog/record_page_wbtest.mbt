///|
fn record_test_limits() -> RecordPageLimits {
  {
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 24,
    max_rows: 10,
    max_columns: 20,
    max_cells: 100,
    max_table_rows: 20,
  }
}

///|
fn record_test_catalog() -> FormFieldCatalog {
  form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"number":{"type":"RECORD_NUMBER","code":"number"},"text":{"type":"SINGLE_LINE_TEXT","code":"text"},"amount":{"type":"NUMBER","code":"amount","displayScale":"3"},"date":{"type":"DATE","code":"date"},"time":{"type":"TIME","code":"time"},"choices":{"type":"MULTI_SELECT","code":"choices","options":{"a":{"label":"a"}}},"owner":{"type":"CREATOR","code":"owner"},"users":{"type":"USER_SELECT","code":"users"},"files":{"type":"FILE","code":"files"},"table":{"type":"SUBTABLE","code":"table","fields":{"id_text":{"type":"SINGLE_LINE_TEXT","code":"id_text"},"amount":{"type":"NUMBER","code":"amount"}}}}}
    ),
  )
}

///|
fn record_test_row() -> String {
  (
    #|{"$id":{"type":"__ID__","value":"3"},"$revision":{"type":"__REVISION__","value":"9007199254740993"},"number":{"type":"RECORD_NUMBER","value":"APPCODE-3"},"text":{"type":"SINGLE_LINE_TEXT","value":"e\u0301\r\n"},"amount":{"type":"NUMBER","value":"9007199254740993.125"},"date":{"type":"DATE","value":null},"time":{"type":"TIME","value":"09:15"},"choices":{"type":"MULTI_SELECT","value":["a","a",""]},"owner":{"type":"CREATOR","value":{"code":"guest/a@example.test","name":"Display"}},"users":{"type":"USER_SELECT","value":[{"code":"u2","name":"Second"},{"code":"u1","name":"First"}]},"files":{"type":"FILE","value":[{"fileKey":"original-key","contentType":"application/octet-stream","name":"../opaque-name","size":"9007199254740993"}]},"table":{"type":"SUBTABLE","value":[{"id":"82","value":{"id_text":{"type":"SINGLE_LINE_TEXT","value":"first"},"amount":{"type":"NUMBER","value":"1e-3"}}},{"id":"81","value":{"id_text":{"type":"SINGLE_LINE_TEXT","value":"second"},"amount":{"type":"NUMBER","value":""}}}]}}
  )
}

///|
fn record_test_page(
  row? : String = record_test_row(),
  names? : Array[String] = [
    "number", "text", "amount", "date", "time", "choices", "owner", "users", "files",
    "table",
  ],
  limits? : RecordPageLimits = record_test_limits(),
) -> Result[OriginalRecordPage, RecordPageIssue] {
  project_record_page(
    @utf8.encode("{\"records\":[" + row + "],\"totalCount\":null}"),
    record_test_catalog(),
    names,
    limits,
  )
}

///|
fn record_test_field(
  record : OriginalRecord,
  code : String,
) -> OriginalRecordField {
  let mut found = None
  for field in original_record_fields(record) {
    if field.metadata.code == code {
      found = Some(field)
      break
    }
  }
  found.unwrap()
}

///|
test "record identity keeps original API ID separate from app-coded record number and exact revision" {
  let page = record_test_page().unwrap()
  assert_eq(page.app_id, "12")
  assert_eq(page.form_revision, "7")
  assert_eq(page.total_count, None)
  let record = record_page_records(page)[0]
  assert_eq(record.record_id, "3")
  assert_eq(record.revision, "9007199254740993")
  assert_eq(
    @decode.text(original_record_value(record_test_field(record, "number"))).unwrap(),
    "APPCODE-3",
  )
  assert_true(
    require_form_unique_key(record_test_catalog(), "number")
    is Err(UniqueKeyUnconfirmed),
  )
  let coincident = record_test_page(
    row=record_test_row().replace(old="APPCODE-3", new="3"),
  ).unwrap()
  assert_eq(record_page_records(coincident)[0].record_id, "3")
  assert_eq(
    original_record_fields(record_page_records(coincident)[0]).length(),
    10,
  )
}

///|
test "native number time and original Unicode remain observations rather than lossy logical substitutes" {
  let record = record_page_records(record_test_page().unwrap())[0]
  for
    (code, expected) in [
      ("text", "é\r\n"),
      ("amount", "9007199254740993.125"),
      ("time", "09:15"),
    ] {
    assert_eq(
      @decode.text(original_record_value(record_test_field(record, code))).unwrap(),
      expected,
    )
  }
  assert_true(
    @decode.is_null(original_record_value(record_test_field(record, "date"))),
  )
  assert_eq(
    record_test_field(record, "amount").metadata.display_scale,
    Some("3"),
  )
  let values = original_record_value(record_test_field(record, "choices"))
  assert_eq(@decode.array_length(values), Some(3))
  assert_eq(@decode.text(@decode.element_at(values, 2).unwrap()).unwrap(), "")
}

///|
test "principal codes attachment metadata and original table row IDs retain their native association" {
  let record = record_page_records(record_test_page().unwrap())[0]
  let principal = @decode.open_object(
    original_record_value(record_test_field(record, "owner")),
  ).unwrap()
  assert_eq(form_text(principal, "code"), Some("guest/a@example.test"))
  let files = original_record_value(record_test_field(record, "files"))
  let file = @decode.open_object(@decode.element_at(files, 0).unwrap()).unwrap()
  assert_eq(form_text(file, "fileKey"), Some("original-key"))
  assert_eq(form_text(file, "size"), Some("9007199254740993"))
  let table = original_record_table_rows(record_test_field(record, "table")).unwrap()
  assert_eq(table.map(row => row.id), ["82", "81"])
  assert_eq(original_table_fields(table[0])[1].metadata.path, [
    "table", "amount",
  ])
  assert_eq(
    @decode.text(original_record_value(original_table_fields(table[0])[1])).unwrap(),
    "1e-3",
  )
  assert_eq(
    @decode.text(original_record_value(original_table_fields(table[1])[1])).unwrap(),
    "",
  )
}

///|
test "missing fields native type mismatches and invalid nulls cannot become an empty or successful row" {
  let row = record_test_row()
  for
    changed in [
      row.replace(old="\"$id\":", new="\"foreign_id\":"),
      row.replace(old="\"$revision\":", new="\"foreign_revision\":"),
      row.replace(old="\"type\":\"__ID__\"", new="\"type\":\"RECORD_NUMBER\""),
      row.replace(old="\"value\":\"3\"", new="\"value\":\"APPCODE-3\""),
      row.replace(old="\"text\":", new="\"foreign_text\":"),
      row.replace(
        old="\"type\":\"SINGLE_LINE_TEXT\"",
        new="\"type\":\"NUMBER\"",
      ),
      row.replace(
        old="\"value\":\"9007199254740993.125\"",
        new="\"value\":null",
      ),
      row.replace(
        old="\"value\":\"9007199254740993.125\"",
        new="\"value\":1.125",
      ),
    ] {
    assert_true(record_test_page(row=changed) is Err(_))
  }
  assert_true(
    record_test_page(names=["text", "text"]) is Err(DuplicateSelection("text")),
  )
  assert_true(
    record_test_page(names=["id_text"]) is Err(FieldUnavailable("id_text")),
  )
}

///|
test "subtable completeness duplicates and row shape are checked against original child metadata" {
  let row = record_test_row()
  for
    changed in [
      row.replace(old="\"id\":\"81\"", new="\"id\":\"82\""),
      row.replace(old="\"id_text\":", new="\"renamed\":"),
      row.replace(old="\"id\":\"81\"", new="\"id\":null"),
      row.replace(old="\"fileKey\":\"original-key\"", new="\"fileKey\":null"),
      row.replace(
        old="\"size\":\"9007199254740993\"",
        new="\"size\":9007199254740992",
      ),
      row.replace(old="\"code\":\"u1\"", new="\"code\":null"),
    ] {
    assert_true(record_test_page(row=changed) is Err(_))
  }
  assert_true(
    record_test_page(row=row.replace(old="\"id\":\"81\"", new="\"id\":\"82\""))
    is Err(DuplicateTableRow("82")),
  )
}

///|
test "empty arrays and documented nulls remain distinct from missing values" {
  let row = record_test_row()
  let empty = row.replace(
    old="\"value\":[\"a\",\"a\",\"\"]",
    new="\"value\":[]",
  )
  let record = record_page_records(record_test_page(row=empty).unwrap())[0]
  assert_eq(
    @decode.array_length(
      original_record_value(record_test_field(record, "choices")),
    ),
    Some(0),
  )
  assert_true(
    record_test_page(
      row=row.replace(old="\"value\":[\"a\",\"a\",\"\"]", new="\"value\":null"),
    )
    is Err(InvalidField("choices")),
  )
  assert_true(
    record_test_page(
      row=row.replace(old="\"value\":null", new="\"not_value\":null"),
    )
    is Err(InvalidField("date")),
  )
}

///|
test "native wrapper families remain exact data and unavailable fields do not pass on an empty page" {
  for
    (native_type, value) in [
      ("MULTI_LINE_TEXT", "\"\""),
      ("RICH_TEXT", "\"<b>original</b>\""),
      ("LINK", "\"https://example.test/path\""),
      ("CALC", "\"49:30\""),
      ("DATETIME", "\"2026-10-17T00:00:00Z\""),
      ("CREATED_TIME", "\"2026-10-17T00:00:00Z\""),
      ("UPDATED_TIME", "\"2026-10-17T00:00:00Z\""),
      ("DATE", "null"),
      ("TIME", "null"),
      ("RADIO_BUTTON", "null"),
      ("DROP_DOWN", "null"),
      ("STATUS", "\"Open\""),
      ("CHECK_BOX", "[]"),
      ("CATEGORY", "[\"c\",\"c\"]"),
      ("ORGANIZATION_SELECT", "[]"),
      ("GROUP_SELECT", "[]"),
      ("STATUS_ASSIGNEE", "[]"),
      ("MODIFIER", "{\"code\":\"u\",\"name\":\"display\"}"),
      ("FILE", "[]"),
    ] {
    let catalog = form_test_catalog(
      body="{\"revision\":\"7\",\"properties\":{\"f\":{\"type\":\"" +
        native_type +
        "\",\"code\":\"f\"}}}",
    )
    let row = "{\"$id\":{\"type\":\"__ID__\",\"value\":\"1\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"1\"},\"f\":{\"type\":\"" +
      native_type +
      "\",\"value\":" +
      value +
      "}}"
    assert_true(
      project_record_page(
        @utf8.encode("{\"records\":[" + row + "],\"totalCount\":null}"),
        catalog,
        ["f"],
        record_test_limits(),
      )
      is Ok(_),
    )
  }
  for native_type in ["REFERENCE_TABLE", "GROUP", "FUTURE_TYPE"] {
    let catalog = form_test_catalog(
      body="{\"revision\":\"7\",\"properties\":{\"f\":{\"type\":\"" +
        native_type +
        "\",\"code\":\"f\"}}}",
    )
    assert_true(
      project_record_page(
        b"{\"records\":[],\"totalCount\":null}",
        catalog,
        ["f"],
        record_test_limits(),
      )
      is Err(FieldUnavailable("f")),
    )
  }
}

///|
test "canonically equivalent external field codes are separate original dictionary keys" {
  let catalog = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"e\u0301":{"type":"SINGLE_LINE_TEXT","code":"e\u0301"},"é":{"type":"SINGLE_LINE_TEXT","code":"é"}}}
    ),
  )
  let bytes = @utf8.encode(
    (
      #|{"records":[{"$id":{"type":"__ID__","value":"1"},"$revision":{"type":"__REVISION__","value":"1"},"e\u0301":{"type":"SINGLE_LINE_TEXT","value":"NFD"},"é":{"type":"SINGLE_LINE_TEXT","value":"NFC"}}],"totalCount":null}
    ),
  )
  let page = project_record_page(
    bytes,
    catalog,
    ["é", "é"],
    record_test_limits(),
  ).unwrap()
  let record = record_page_records(page)[0]
  assert_eq(
    @decode.text(original_record_value(record_test_field(record, "é"))).unwrap(),
    "NFD",
  )
  assert_eq(
    @decode.text(original_record_value(record_test_field(record, "é"))).unwrap(),
    "NFC",
  )
}

///|
test "complete response count and record identity checks return no partial page" {
  let catalog = record_test_catalog()
  let row = record_test_row()
  for
    body in [
      "{\"records\":[" + row + "," + row + "],\"totalCount\":null}",
      "{\"records\":[" + row + "]}",
      "{\"records\":[],\"totalCount\":0}",
      "{\"records\":[],\"totalCount\":\"-1\"}",
      "{\"records\":[],\"records\":[],\"totalCount\":null}",
      "{\"records\":[],\"totalCount\":null} trailing",
    ] {
    assert_true(
      project_record_page(
        @utf8.encode(body),
        catalog,
        ["text"],
        record_test_limits(),
      )
      is Err(_),
    )
  }
  let bytes = b"{\"records\":[],\"totalCount\":\"9007199254740993\"}"
  let page = project_record_page(bytes, catalog, ["text"], record_test_limits()).unwrap()
  assert_eq(page.total_count, Some("9007199254740993"))
  assert_eq(page.response_sha256, @sha.hex(bytes))
  assert_eq(record_page_records(page).length(), 0)
}

///|
test "original catalog nominal association and copied collection getters do not admit foreign observations" {
  let catalog = record_test_catalog()
  let bytes = @utf8.encode(
    "{\"records\":[" + record_test_row() + "],\"totalCount\":null}",
  )
  let page = project_record_page(
    bytes,
    catalog,
    ["table"],
    record_test_limits(),
  ).unwrap()
  assert_true(record_page_uses_catalog(page, catalog))
  assert_true(!record_page_uses_catalog(page, record_test_catalog()))
  let records = record_page_records(page)
  records.clear()
  assert_eq(record_page_records(page).length(), 1)
  let record = record_page_records(page)[0]
  let fields = original_record_fields(record)
  fields.clear()
  assert_eq(original_record_fields(record).length(), 1)
  let table = original_record_table_rows(original_record_fields(record)[0]).unwrap()
  let table_fields = original_table_fields(table[0])
  table_fields.clear()
  table.clear()
  assert_eq(
    original_table_fields(
      original_record_table_rows(original_record_fields(record)[0]).unwrap()[0],
    ).length(),
    2,
  )
}

///|
test "all physical projection bounds are positive and cumulative across original table cells" {
  let original = record_test_limits()
  for
    limits in [
      { ..original, max_bytes: 100, },
      { ..original, max_nodes: 2, },
      { ..original, max_depth: 2, },
      { ..original, max_columns: 1, },
      { ..original, max_cells: 12, },
      { ..original, max_table_rows: 1, },
    ] {
    assert_true(record_test_page(limits~) is Err(BudgetExceeded))
  }
  for
    limits in [
      { ..original, max_bytes: 0, },
      { ..original, max_nodes: 0, },
      { ..original, max_depth: 0, },
      { ..original, max_rows: 0, },
      { ..original, max_columns: 0, },
      { ..original, max_cells: 0, },
      { ..original, max_table_rows: 0, },
    ] {
    assert_true(record_test_page(limits~) is Err(InvalidLimits))
  }
  let row = record_test_row()
  let two_rows = "{\"records\":[" +
    row +
    "," +
    row.replace(old="\"value\":\"3\"", new="\"value\":\"4\"") +
    "],\"totalCount\":null}"
  assert_true(
    project_record_page(
      @utf8.encode(two_rows),
      record_test_catalog(),
      ["text"],
      { ..original, max_rows: 1, },
    )
    is Err(BudgetExceeded),
  )
}
