///|
fn values_test_limits() -> RecordValueLimits {
  {
    max_columns: 30,
    max_name_bytes: 2000,
    max_nodes: 2000,
    max_depth: 20,
    max_text_bytes: 20000,
  }
}

///|
fn settings_test_body() -> String {
  (
    #|{"numberPrecision":{"digits":"16","decimalPlaces":"4","roundingMode":"HALF_EVEN"},"revision":"7"}
  )
}

///|
fn settings_test_original(
  body? : String = settings_test_body(),
  app_id? : String = "12",
) -> AppNumberSettings {
  project_number_settings(@utf8.encode(body), app_id, {
    max_bytes: 4000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
}

///|
fn values_test_catalog(
  display_scale? : String = "2",
  required? : Bool = false,
) -> FormFieldCatalog {
  form_test_catalog(
    body=(
        #|{"revision":"7","properties":{"amount":{"type":"NUMBER","code":"amount","displayScale":"DISPLAY","required":REQUIRED},"text":{"type":"SINGLE_LINE_TEXT","code":"text"},"number":{"type":"RECORD_NUMBER","code":"number"},"date":{"type":"DATE","code":"date"},"observed":{"type":"DATETIME","code":"observed"},"choices":{"type":"MULTI_SELECT","code":"choices","options":{"a":{"label":"a"}}},"owner":{"type":"CREATOR","code":"owner"},"users":{"type":"USER_SELECT","code":"users"},"calc":{"type":"CALC","code":"calc","format":"HOUR_MINUTE"},"table":{"type":"SUBTABLE","code":"table","fields":{"value":{"type":"NUMBER","code":"value","displayScale":"0"},"label":{"type":"SINGLE_LINE_TEXT","code":"label"}}},"time":{"type":"TIME","code":"time"},"files":{"type":"FILE","code":"files"}}}
      )
      .replace(old="DISPLAY", new=display_scale)
      .replace(old="REQUIRED", new=if required { "true" } else { "false" }),
  )
}

///|
fn values_test_row(amount? : String = "1.007") -> String {
  (
    #|{"$id":{"type":"__ID__","value":"9007199254740993"},"$revision":{"type":"__REVISION__","value":"7"},"amount":{"type":"NUMBER","value":"AMOUNT"},"text":{"type":"SINGLE_LINE_TEXT","value":"e\u0301\r\n"},"number":{"type":"RECORD_NUMBER","value":"APP-9007199254740993"},"date":{"type":"DATE","value":"2024-02-29"},"observed":{"type":"DATETIME","value":"2026-10-17T01:02:03Z"},"choices":{"type":"MULTI_SELECT","value":["a","a",""]},"owner":{"type":"CREATOR","value":{"code":"u0","name":"display only"}},"users":{"type":"USER_SELECT","value":[{"code":"u2","name":"second"},{"code":"u1","name":"first"}]},"calc":{"type":"CALC","value":"49:30"},"table":{"type":"SUBTABLE","value":[{"id":"81","value":{"value":{"type":"NUMBER","value":"1.2345"},"label":{"type":"SINGLE_LINE_TEXT","value":"first"}}}]},"time":{"type":"TIME","value":"09:15"},"files":{"type":"FILE","value":[]}}
  ).replace(old="AMOUNT", new=amount)
}

///|
fn values_test_page(
  names? : Array[String] = ["amount"],
  amount? : String = "1.007",
  display_scale? : String = "2",
  required? : Bool = false,
  row? : String? = None,
) -> OriginalRecordPage {
  let row = row.unwrap_or(values_test_row(amount~))
  project_record_page(
    @utf8.encode("{\"records\":[" + row + "],\"totalCount\":null}"),
    values_test_catalog(display_scale~, required~),
    names,
    record_test_limits(),
  ).unwrap()
}

///|
fn checked_values_test_page(
  page? : OriginalRecordPage = values_test_page(names=["text"]),
  settings? : AppNumberSettings? = Some(settings_test_original()),
) -> CheckedRecordPage {
  project_checked_record_page(page, settings, values_test_limits()).unwrap()
}

///|
test "original settings remain configuration while explicit per-value Common admission preserves 1.007" {
  let settings = settings_test_original()
  assert_eq(settings.digits, 16)
  assert_eq(settings.decimal_places, 4)
  assert_eq(settings.rounding_mode, "HALF_EVEN")
  assert_eq(
    settings.response_sha256,
    @sha.hex(@utf8.encode(settings_test_body())),
  )
  let contract = @contract.decimal_contract(16, 4, nullable=true).unwrap()
  for scale in ["", "0", "2", "6"] {
    let original = values_test_page(display_scale=scale)
    let field = original_record_fields(record_page_records(original)[0])[0]
    let checked = admit_record_number_value(
      field,
      contract,
      values_test_limits(),
    ).unwrap()
    assert_true(
      checked.contract.shape is @contract.Decimal(precision=16, scale=4),
    )
    assert_true(
      checked.value is @admitted.Decimal(value) && value.coefficient == "10070",
    )
    assert_eq(@decode.text(original_record_value(field)).unwrap(), "1.007")
    assert_true(
      project_checked_record_page(
        original,
        Some(settings),
        values_test_limits(),
      )
      is Err(FieldUnavailable("amount")),
    )
  }
}

///|
test "explicit per-value decimal contracts preserve exact range and scale without proving a Source envelope" {
  let contract = @contract.decimal_contract(30, 10, nullable=true).unwrap()
  fn number(
    value : String,
    contract : @contract.Contract,
  ) -> Result[@admitted.CheckedValue, RecordValueIssue] {
    let page = values_test_page(amount=value)
    admit_record_number_value(
      original_record_fields(record_page_records(page)[0])[0],
      contract,
      values_test_limits(),
    )
  }
  let positive = number("99999999999999999999.1234567890", contract).unwrap()
  assert_true(
    positive.value is @admitted.Decimal(value) &&
    value.coefficient == "999999999999999999991234567890",
  )
  assert_true(
    number("100000000000000000000", contract)
    is Err(DecimalValue("amount", @admitted.OutOfRange)),
  )
  assert_true(
    number("1.00000000001", contract)
    is Err(DecimalValue("amount", @admitted.BeyondScale)),
  )
  let exponent = number(
    "-12345e-4",
    @contract.decimal_contract(16, 4, nullable=true).unwrap(),
  ).unwrap()
  assert_true(
    exponent.value is @admitted.Decimal(value) && value.coefficient == "-12345",
  )
}

///|
test "missing foreign or unrepresentable original numeric settings never infer defaults" {
  assert_true(
    project_checked_record_page(values_test_page(), None, values_test_limits())
    is Err(FieldUnavailable("amount")),
  )
  for
    settings in [
      settings_test_original(app_id="13"),
      settings_test_original(
        body=settings_test_body().replace(
          old="\"revision\":\"7\"",
          new="\"revision\":\"8\"",
        ),
      ),
    ] {
    assert_true(
      project_checked_record_page(
        values_test_page(),
        Some(settings),
        values_test_limits(),
      )
      is Err(ForeignSettings),
    )
  }
  let impossible = settings_test_original(
    body=settings_test_body().replace(old="\"16\"", new="\"1\""),
  )
  assert_true(
    project_checked_record_page(
      values_test_page(),
      Some(impossible),
      values_test_limits(),
    )
    is Err(FieldUnavailable("amount")),
  )
  let independent = project_checked_record_page(
    values_test_page(names=["text"]),
    None,
    values_test_limits(),
  ).unwrap()
  assert_true(
    checked_record_rows(independent)[0][1].value is @admitted.Text("é\r\n"),
  )
}

///|
test "explicit Common numeric nullability retains refusal rather than an invented zero" {
  let contract = @contract.decimal_contract(16, 4, nullable=true).unwrap()
  let empty = original_record_fields(
      record_page_records(values_test_page(amount=""))[0],
    )[0]
  assert_true(
    admit_record_number_value(empty, contract, values_test_limits()).unwrap().value
    is @admitted.Null,
  )
  assert_true(
    admit_record_number_value(
      empty,
      @contract.with_nullability(contract, false),
      values_test_limits(),
    )
    is Err(
      ValueAdmission(
        "amount",
        @admitted.ValueIssue(@admitted.UnexpectedNull, ..)
      )
    ),
  )
  for value in ["#INVALID!", "1,000", "01", "1.23451"] {
    let original = values_test_page(amount=value)
    let field = original_record_fields(record_page_records(original)[0])[0]
    assert_true(
      admit_record_number_value(field, contract, values_test_limits())
      is Err(DecimalValue("amount", _)),
    )
    assert_eq(@decode.text(original_record_value(field)).unwrap(), value)
  }
}

///|
test "original text codes arrays and calculation formats become matching checked Common values" {
  let checked = checked_values_test_page(
    page=values_test_page(names=[
      "text", "number", "choices", "owner", "users", "calc",
    ]),
  )
  let row = checked_record_rows(checked)[0]
  assert_true(row[1].value is @admitted.Text("é\r\n"))
  assert_true(row[2].value is @admitted.Text("APP-9007199254740993"))
  guard row[3].value is @admitted.Array(choices) else { abort("choices") }
  assert_eq(@admitted.element_count(choices), 3)
  assert_true(@admitted.element_at(choices, 2).unwrap() is @admitted.Text(""))
  assert_true(row[4].value is @admitted.Text("u0"))
  guard row[5].value is @admitted.Array(users) else { abort("users") }
  assert_true(@admitted.element_at(users, 0).unwrap() is @admitted.Text("u2"))
  assert_true(@admitted.element_at(users, 1).unwrap() is @admitted.Text("u1"))
  assert_true(row[6].value is @admitted.Text("49:30"))
}

///|
test "calendar admission and whole second UTC use the existing temporal owner" {
  let checked = checked_values_test_page(
    page=values_test_page(names=["date", "observed"]),
  )
  let row = checked_record_rows(checked)[0]
  assert_true(row[1].value is @admitted.Date("2024-02-29"))
  assert_true(row[2].value is @admitted.Timestamp("2026-10-17T01:02:03.000Z"))
  for
    (old, replacement) in [
      ("2024-02-29", "2023-02-29"),
      ("01:02:03Z", "25:02:03Z"),
    ] {
    let page = values_test_page(
      names=["date", "observed"],
      row=Some(values_test_row().replace(old~, new=replacement)),
    )
    assert_true(
      project_checked_record_page(page, None, values_test_limits())
      is Err(ValueAdmission(_, _)),
    )
  }
}

///|
test "nonnumeric subtable row identity and original child contracts survive checked object admission" {
  let catalog = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"table":{"type":"SUBTABLE","code":"table","fields":{"label":{"type":"SINGLE_LINE_TEXT","code":"label"}}}}}
    ),
  )
  let bytes = @utf8.encode(
    (
      #|{"records":[{"$id":{"type":"__ID__","value":"1"},"$revision":{"type":"__REVISION__","value":"1"},"table":{"type":"SUBTABLE","value":[{"id":"81","value":{"label":{"type":"SINGLE_LINE_TEXT","value":"first"}}}]}}],"totalCount":null}
    ),
  )
  let original = project_record_page(
    bytes,
    catalog,
    ["table"],
    record_test_limits(),
  ).unwrap()
  let checked = project_checked_record_page(
    original,
    None,
    values_test_limits(),
  ).unwrap()
  guard checked_record_rows(checked)[0][1].value is @admitted.Array(rows) &&
    @admitted.element_at(rows, 0).unwrap() is @admitted.Object(fields) else {
    abort("table")
  }
  let fields = @admitted.elements(fields)
  assert_eq(fields.map(field => field.0), ["id", "label"])
  assert_true(fields[0].1 is @admitted.Text("81"))
  assert_true(fields[1].1 is @admitted.Text("first"))
  assert_true(physical_equal(checked_record_original(checked), original))
  // Numeric children are not silently dropped to make a table available.
  assert_true(
    project_checked_record_page(
      values_test_page(names=["table"]),
      Some(settings_test_original()),
      values_test_limits(),
    )
    is Err(FieldUnavailable("value")),
  )
}

///|
test "same schema and checked cells are admitted by the existing Relation owner without a primitive fallback" {
  let checked = checked_values_test_page(
    page=values_test_page(names=["text", "choices"]),
  )
  let columns = checked_record_columns(checked)
  let row = checked_record_rows(checked)[0]
  let fields = []
  for index, name in columns {
    fields.push((@schema.Unqualified(name), row[index].contract))
  }
  let relation = @schema.from_fields(fields, max_fields=30, max_name_bytes=2000).unwrap()
  assert_eq(@schema.field_count(relation), 3)
  assert_true(
    @schema.lookup(relation, @schema.Unqualified("choices")).unwrap().shape
    is @contract.Array(_, ..),
  )
  let wire = record_schema_wire(
    values_test_catalog(),
    Some(settings_test_original()),
    ["text", "choices"],
    values_test_limits(),
    20000,
  ).unwrap()
  assert_true(wire.contains("\"type\":\"array\""))
  assert_true(wire.contains("\"$id\":{\"nullable\":false,\"type\":\"string\"}"))
  assert_eq(
    record_schema_wire(
      values_test_catalog(),
      None,
      ["text"],
      values_test_limits(),
      20000,
    ),
    Ok(
      "{\"$id\":{\"nullable\":false,\"type\":\"string\"},\"text\":{\"nullable\":false,\"type\":\"string\"}}",
    ),
  )
}

///|
test "unsupported shared logical types and original field collisions remain unavailable before record I/O" {
  for name in ["time", "files", "$revision"] {
    assert_true(
      record_schema_wire(
        values_test_catalog(),
        None,
        [name],
        values_test_limits(),
        20000,
      )
      is Err(FieldUnavailable(actual)) &&
      actual == name,
    )
  }
  let catalog = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"table":{"type":"SUBTABLE","code":"table","fields":{"id":{"type":"SINGLE_LINE_TEXT","code":"id"}}}}}
    ),
  )
  assert_true(
    record_schema_wire(catalog, None, ["table"], values_test_limits(), 20000)
    is Err(UnrepresentableField("id")),
  )
  assert_true(
    record_schema_wire(
      values_test_catalog(),
      None,
      ["text", "text"],
      values_test_limits(),
      20000,
    )
    is Err(UnrepresentableField("text")),
  )
}

///|
test "copied row and column arrays cannot change the original checked page" {
  let original = values_test_page(names=["text"])
  let checked = checked_values_test_page(page=original)
  let names = record_page_columns(original)
  names.clear()
  assert_eq(record_page_columns(original), ["text"])
  let columns = checked_record_columns(checked)
  columns[1] = "foreign"
  let rows = checked_record_rows(checked)
  rows[0].clear()
  rows.clear()
  assert_eq(checked_record_columns(checked), ["$id", "text"])
  assert_eq(checked_record_rows(checked)[0].length(), 2)
}

///|
test "positive cumulative checked value schema output and original settings bounds refuse without partial output" {
  let original = values_test_limits()
  for
    limits in [
      { ..original, max_nodes: 1, },
      { ..original, max_depth: 1, },
      { ..original, max_text_bytes: 10, },
      { ..original, max_columns: 1, },
      { ..original, max_name_bytes: 2, },
    ] {
    assert_true(
      project_checked_record_page(
        values_test_page(names=["text", "choices"]),
        Some(settings_test_original()),
        limits,
      )
      is Err(BudgetExceeded),
    )
  }
  for
    limits in [
      { ..original, max_nodes: 0, },
      { ..original, max_depth: 0, },
      { ..original, max_text_bytes: 0, },
      { ..original, max_columns: 0, },
      { ..original, max_name_bytes: 0, },
    ] {
    assert_true(
      project_checked_record_page(
        values_test_page(),
        Some(settings_test_original()),
        limits,
      )
      is Err(InvalidLimits),
    )
  }
  assert_true(
    record_schema_wire(values_test_catalog(), None, ["text"], original, 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    record_schema_wire(values_test_catalog(), None, ["text"], original, 0)
    is Err(InvalidLimits),
  )
  let body = @utf8.encode(settings_test_body())
  for
    limits in [
      { max_bytes: 1, max_nodes: 100, max_depth: 10, },
      { max_bytes: 4000, max_nodes: 1, max_depth: 10, },
      { max_bytes: 4000, max_nodes: 100, max_depth: 1, },
    ] {
    assert_true(
      project_number_settings(body, "12", limits) is Err(BudgetExceeded),
    )
  }
}

///|
test "settings numbers are original strings and missing malformed or unknown values cannot become a profile" {
  for
    body in [
      "{}",
      settings_test_body().replace(old="\"16\"", new="16"),
      settings_test_body().replace(old="\"16\"", new="\"31\""),
      settings_test_body().replace(old="\"16\"", new="\"0\""),
      settings_test_body().replace(old="\"4\"", new="\"11\""),
      settings_test_body().replace(old="\"HALF_EVEN\"", new="\"DEFAULT\""),
      settings_test_body().replace(
        old="\"digits\":\"16\"",
        new="\"other\":\"16\"",
      ),
      settings_test_body().replace(
        old="\"revision\":\"7\"",
        new="\"revision\":null",
      ),
      settings_test_body() + " trailing",
    ] {
    assert_true(
      project_number_settings(@utf8.encode(body), "12", {
        max_bytes: 4000,
        max_nodes: 100,
        max_depth: 10,
      })
      is Err(InvalidResponse),
    )
  }
}

///|
test "historical numeric values and required flags are not narrowed by current settings or Form revision" {
  let settings = settings_test_original()
  let original = values_test_page(amount="1.234567")
  let field = original_record_fields(record_page_records(original)[0])[0]
  let explicit_value_contract = @contract.decimal_contract(
    20,
    10,
    nullable=true,
  ).unwrap()
  assert_true(
    admit_record_number_value(
      field,
      explicit_value_contract,
      values_test_limits(),
    ).unwrap().value
    is @admitted.Decimal(value) &&
    value.coefficient == "12345670000",
  )
  assert_true(
    record_schema_wire(
      values_test_catalog(),
      Some(settings),
      ["amount"],
      values_test_limits(),
      20000,
    )
    is Err(FieldUnavailable("amount")),
  )
  assert_eq(@decode.text(original_record_value(field)).unwrap(), "1.234567")
  let catalog = form_test_catalog(
    body=(
      #|{"revision":"7","properties":{"date":{"type":"DATE","code":"date","required":true}}}
    ),
  )
  let original = project_record_page(
    b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"1\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"1\"},\"date\":{\"type\":\"DATE\",\"value\":null}}],\"totalCount\":null}",
    catalog,
    ["date"],
    record_test_limits(),
  ).unwrap()
  let checked = project_checked_record_page(
    original,
    None,
    values_test_limits(),
  ).unwrap()
  assert_true(checked_record_rows(checked)[0][1].value is @admitted.Null)
}

///|
test "per-value numeric admission does not retarget a text field or replace the explicit Common contract" {
  let page = values_test_page(names=["text", "amount"])
  let fields = original_record_fields(record_page_records(page)[0])
  let decimal = @contract.decimal_contract(20, 10, nullable=true).unwrap()
  assert_true(
    admit_record_number_value(fields[0], decimal, values_test_limits())
    is Err(InvalidValue("text")),
  )
  let text = @contract.primitive(@contract.StringType, nullable=false)
  assert_true(
    admit_record_number_value(fields[1], text, values_test_limits())
    is Err(InvalidValue("amount")),
  )
  let selected = checked_values_test_page(page=values_test_page(names=["text"]))
  assert_true(
    physical_equal(
      checked_record_settings(selected).unwrap(),
      selected.settings.unwrap(),
    ),
  )
}
