///|
fn page_limits() -> ObjectPageLimits {
  {
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 20,
    max_rows: 50,
    max_columns: 20,
    max_cursor_units: 128,
    max_value_nodes: 1000,
    max_value_text_bytes: 20000,
  }
}

///|
fn object_catalog() -> PropertyCatalog {
  catalog(
    (
      #|{"results":[{"name":"name","type":"string","fieldType":"text"},{"name":"amount","type":"number","fieldType":"number"},{"name":"live","type":"bool","fieldType":"booleancheckbox"},{"name":"day","type":"date","fieldType":"date"},{"name":"instant","type":"datetime","fieldType":"date"},{"name":"tags","type":"enumeration","fieldType":"checkbox","options":[{"value":"a"},{"value":"b"}]},{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"internal"}]}]}
    ),
  )
}

///|
fn page(
  body : String,
  names : Array[String],
) -> Result[ObjectPage, ObjectPageIssue] {
  project_object_page(
    @utf8.encode(body),
    object_catalog(),
    names,
    page_limits(),
  )
}

///|
test "record page preserves exact IDs decimals booleans enum values and paging" {
  let body =
    #|{"results":[{"id":"9007199254740993","archived":false,"properties":{"name":"ACME","amount":"9007199254740993.01","live":"false","tags":"a;b","stage":"internal"}}],"paging":{"next":{"after":"opaque_cursor","link":"https://foreign.example/not-followed"}}}
  let observed = page(body, ["name", "amount", "live", "tags", "stage"]).unwrap()
  assert_eq(observed.response_sha256, @sha.hex(@utf8.encode(body)))
  assert_eq(observed.next_after, Some("opaque_cursor"))
  let rows = object_page_rows(observed)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].id, "9007199254740993")
  let values = object_row_values(rows[0])
  assert_true(values[0].value is @admitted.Text("ACME"))
  assert_true(
    values[1].value is @admitted.Decimal(number) &&
    number.coefficient == "90071992547409930100000000" &&
    number.precision == 38 &&
    number.scale == 10,
  )
  assert_true(values[2].value is @admitted.Boolean(false))
  assert_true(
    values[3].value is @admitted.Array(items) &&
    @admitted.element_at(items, 0) is Some(@admitted.Text("a")) &&
    @admitted.element_at(items, 1) is Some(@admitted.Text("b")),
  )
  assert_true(values[4].value is @admitted.Text("internal"))
}

///|
test "epoch and UTC temporal properties use Common time conversion without rounding" {
  let observed = page(
    (
      #|{"results":[{"id":"1","archived":false,"properties":{"day":"8640000000","instant":"-1"}},{"id":"2","archived":false,"properties":{"day":"2026-10-16T00:00:00.000Z","instant":"2026-10-16T12:34:56.7+00:00"}}]}
    ),
    ["day", "instant"],
  ).unwrap()
  let rows = object_page_rows(observed)
  let first = object_row_values(rows[0])
  assert_true(first[0].value is @admitted.Date("1970-04-11"))
  assert_true(first[1].value is @admitted.Timestamp("1969-12-31T23:59:59.999Z"))
  let second = object_row_values(rows[1])
  assert_true(second[0].value is @admitted.Date("2026-10-16"))
  assert_true(
    second[1].value is @admitted.Timestamp("2026-10-16T12:34:56.700Z"),
  )
}

///|
test "explicit unset scalars stay nullable and empty checkboxes stay an empty array" {
  let observed = page(
    (
      #|{"results":[{"id":"1","archived":false,"properties":{"name":"","amount":null,"live":"","tags":"","stage":""}}]}
    ),
    ["name", "amount", "live", "tags", "stage"],
  ).unwrap()
  let values = object_row_values(object_page_rows(observed)[0])
  assert_true(values[0].value is @admitted.Text(""))
  assert_true(values[1].value is @admitted.Null)
  assert_true(values[2].value is @admitted.Null)
  assert_true(
    values[3].value is @admitted.Array(items) &&
    @admitted.elements(items).is_empty(),
  )
  assert_true(values[4].value is @admitted.Null)
}

///|
test "missing selected properties and inexact values refuse the complete page" {
  assert_true(
    page(
      (
        #|{"results":[{"id":"1","archived":false,"properties":{}}]}
      ),
      ["amount"],
    )
    is Err(MissingProperty("amount")),
  )
  assert_true(
    page(
      (
        #|{"results":[{"id":"1","archived":false,"properties":{"amount":"0.00000000001"}}]}
      ),
      ["amount"],
    )
    is Err(DecimalCell("amount", @admitted.BeyondScale)),
  )
  assert_true(
    page(
      (
        #|{"results":[{"id":"1","archived":false,"properties":{"amount":"1e28"}}]}
      ),
      ["amount"],
    )
    is Err(DecimalCell("amount", @admitted.OutOfRange)),
  )
  for
    body in [
      (
        #|{"results":[{"id":"1","archived":false,"properties":{"live":"yes"}}]}
      ),
      (
        #|{"results":[{"id":"1","archived":false,"properties":{"live":true}}]}
      ),
    ] {
    assert_true(page(body, ["live"]) is Err(InvalidCell("live")))
  }
  assert_true(
    page(
      (
        #|{"results":[{"id":"1","archived":false,"properties":{"day":"2026-10-16T00:00:00.001Z"}}]}
      ),
      ["day"],
    )
    is Err(InvalidCell("day")),
  )
}

///|
test "duplicate archived malformed cursor and foreign selection cannot become a partial source" {
  assert_true(
    page(
      (
        #|{"results":[{"id":"1","archived":false,"properties":{}},{"id":"1","archived":false,"properties":{}}]}
      ),
      [],
    )
    is Err(DuplicateRecord("1")),
  )
  assert_true(
    page(
      (
        #|{"results":[{"id":"1","archived":true,"properties":{}}]}
      ),
      [],
    )
    is Err(ArchivedRecord),
  )
  assert_true(
    page("{\"results\":[],\"paging\":{\"next\":{}}}", []) is Err(InvalidCursor),
  )
  assert_true(
    page("{\"results\":[]}", ["name", "name"])
    is Err(DuplicateSelection("name")),
  )
  assert_true(
    page("{\"results\":[]}", ["foreign"])
    is Err(Property(PropertyUnconfirmed("foreign"))),
  )
}

///|
test "whole response and simultaneous retained value budgets reject before exposure" {
  let body = @utf8.encode(
    (
      #|{"results":[{"id":"1","archived":false,"properties":{"tags":"a;b"}}]}
    ),
  )
  for
    bound in [
      { ..page_limits(), max_bytes: body.length() - 1, },
      { ..page_limits(), max_nodes: 2, },
      { ..page_limits(), max_depth: 1, },
      { ..page_limits(), max_value_nodes: 3, },
      { ..page_limits(), max_value_text_bytes: 1, },
    ] {
    assert_true(
      project_object_page(body, object_catalog(), ["tags"], bound)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    project_object_page(body, object_catalog(), ["tags"], {
      ..page_limits(),
      max_rows: 0,
    })
    is Err(InvalidLimits),
  )
}

///|
test "returned row and field arrays cannot modify the original page" {
  let observed = page(
    (
      #|{"results":[{"id":"1","archived":false,"properties":{"name":"original"}}]}
    ),
    ["name"],
  ).unwrap()
  let names = object_page_columns(observed)
  names[0] = "foreign"
  let rows = object_page_rows(observed)
  let values = object_row_values(rows[0])
  values.clear()
  rows.clear()
  assert_eq(object_page_columns(observed), ["name"])
  assert_eq(object_page_rows(observed).length(), 1)
  assert_true(
    object_row_values(object_page_rows(observed)[0])[0].value
    is @admitted.Text("original"),
  )
}

///|
fn check_duplicate_company_domain(properties_body : String) -> Unit raise {
  let properties = catalog(properties_body)
  let observed = project_object_page(
    @utf8.encode(
      (
        #|{"results":[{"id":"101","archived":false,"properties":{"domain":"same.example","external_key":"first"}},{"id":"202","archived":false,"properties":{"domain":"same.example","external_key":"second"}}]}
      ),
    ),
    properties,
    ["domain", "external_key"],
    page_limits(),
  ).unwrap()
  let rows = object_page_rows(observed)
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].id, "101")
  assert_eq(rows[1].id, "202")
  for row in rows {
    assert_true(
      object_row_values(row)[0].value is @admitted.Text("same.example"),
    )
  }
  assert_true(object_row_values(rows[0])[1].value is @admitted.Text("first"))
  assert_true(object_row_values(rows[1])[1].value is @admitted.Text("second"))
  // Reading both records is valid; their shared lookup value cannot prove a
  // unique write target. The actual property Owner makes that independent call.
  assert_eq(
    require_unique_property(properties, "domain"),
    Err(UniqueKeyUnconfirmed("domain")),
  )
  assert_eq(require_unique_property(properties, "hs_object_id"), Ok(()))
  assert_eq(require_unique_property(properties, "external_key"), Ok(()))
}

///|
test "two company ids can retain the same domain when metadata says nonunique" {
  check_duplicate_company_domain(
    (
      #|{"results":[{"name":"domain","type":"string","fieldType":"text","hasUniqueValue":false},{"name":"external_key","type":"string","fieldType":"text","hasUniqueValue":true},{"name":"hs_object_id","type":"number","fieldType":"number","hasUniqueValue":false}]}
    ),
  )
}

///|
test "two company ids can retain the same domain when uniqueness metadata is missing" {
  check_duplicate_company_domain(
    (
      #|{"results":[{"name":"domain","type":"string","fieldType":"text"},{"name":"external_key","type":"string","fieldType":"text","hasUniqueValue":true},{"name":"hs_object_id","type":"number","fieldType":"number","hasUniqueValue":false}]}
    ),
  )
}
