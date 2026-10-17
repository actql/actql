///|
fn range_test_value(kind : String, value : String) -> @admitted.CheckedValue {
  write_test_value("{\"type\":\"" + kind + "\",\"nullable\":true}", value)
}

///|
test "Notion date ranges retain both original checked Date and Timestamp scalars" {
  let source = write_test_source("date")
  for
    (kind, start_wire, end_wire, expected) in [
      (
        "date", "\"2024-02-29\"", "\"2024-03-01\"", "{\"properties\":{\"p%3Ax\":{\"date\":{\"start\":\"2024-02-29\",\"end\":\"2024-03-01\"}}}}",
      ),
      (
        "timestamp", "\"2024-02-29T12:34:56.789Z\"", "\"2024-03-01T01:02:03.456Z\"",
        "{\"properties\":{\"p%3Ax\":{\"date\":{\"start\":\"2024-02-29T12:34:56.789Z\",\"end\":\"2024-03-01T01:02:03.456Z\"}}}}",
      ),
    ] {
    let start = range_test_value(kind, start_wire)
    let end = range_test_value(kind, end_wire)
    let write = prepare_notion_date_range_property_write(
      source,
      0,
      start,
      end,
      write_test_limits(),
    ).unwrap()
    assert_eq(
      notion_page_properties_write_wire(source, [write], write_test_limits()).unwrap(),
      expected,
    )
    assert_true(
      notion_date_range_property_write_matches(write, source, 0, start, end),
    )
  }
}

///|
test "Notion range explicit typed null end remains original and legacy absent end bytes stay unchanged" {
  let source = write_test_source("date")
  let start = range_test_value("date", "\"2024-02-29\"")
  let end = range_test_value("date", "null")
  let range = prepare_notion_date_range_property_write(
    source,
    0,
    start,
    end,
    write_test_limits(),
  ).unwrap()
  assert_eq(
    notion_page_properties_write_wire(source, [range], write_test_limits()).unwrap(),
    "{\"properties\":{\"p%3Ax\":{\"date\":{\"start\":\"2024-02-29\",\"end\":null}}}}",
  )
  let scalar = prepare_notion_property_write(
    source,
    0,
    start,
    write_test_limits(),
  ).unwrap()
  assert_eq(
    notion_page_properties_write_wire(source, [scalar], write_test_limits()).unwrap(),
    "{\"properties\":{\"p%3Ax\":{\"date\":{\"start\":\"2024-02-29\"}}}}",
  )
  assert_true(notion_property_write_matches(scalar, source, 0, start))
  assert_false(notion_property_write_matches(range, source, 0, start))
  assert_false(
    notion_date_range_property_write_matches(scalar, source, 0, start, end),
  )
}

///|
test "Notion range matching checks both physical originals and the selected source occurrence" {
  let source = write_test_source("date")
  let start = range_test_value("date", "\"2024-02-29\"")
  let end = range_test_value("date", "\"2024-03-01\"")
  let write = prepare_notion_date_range_property_write(
    source,
    0,
    start,
    end,
    write_test_limits(),
  ).unwrap()
  assert_false(
    notion_date_range_property_write_matches(
      write,
      source,
      0,
      range_test_value("date", "\"2024-02-29\""),
      end,
    ),
  )
  assert_false(
    notion_date_range_property_write_matches(
      write,
      source,
      0,
      start,
      range_test_value("date", "\"2024-03-01\""),
    ),
  )
  assert_false(
    notion_date_range_property_write_matches(write, source, 0, end, start),
  )
  assert_false(
    notion_date_range_property_write_matches(
      write,
      write_test_source("date"),
      0,
      start,
      end,
    ),
  )
  assert_false(
    notion_date_range_property_write_matches(write, source, 1, start, end),
  )
}

///|
test "Notion date range requires present typed start and the same temporal kind including null end" {
  let source = write_test_source("date")
  let date = range_test_value("date", "\"2024-02-29\"")
  let timestamp = range_test_value("timestamp", "\"2024-02-29T12:34:56.789Z\"")
  let null_date = range_test_value("date", "null")
  let null_timestamp = range_test_value("timestamp", "null")
  let text = write_test_text("2024-02-29")
  for
    (start, end) in [
      (date, timestamp),
      (timestamp, date),
      (date, null_timestamp),
      (timestamp, null_date),
      (null_date, date),
      (null_date, null_date),
      (text, date),
      (date, text),
    ] {
    assert_eq(
      prepare_notion_date_range_property_write(
        source,
        0,
        start,
        end,
        write_test_limits(),
      ).unwrap_err(),
      InvalidValue("p%3Ax"),
    )
  }
}

///|
test "Notion range work and encoder limits charge both scalars at the exact boundary" {
  let source = write_test_source("date")
  let start = range_test_value("date", "\"2024-02-29\"")
  let end = range_test_value("date", "\"2024-03-01\"")
  let wire = "{\"date\":{\"start\":\"2024-02-29\",\"end\":\"2024-03-01\"}}"
  let exact = {
    ..write_test_limits(),
    max_work: 26,
    max_text_units: 10,
    max_bytes: wire.length(),
    max_nodes: 4,
    max_depth: 2,
  }
  assert_true(
    prepare_notion_date_range_property_write(source, 0, start, end, exact)
    is Ok(_),
  )
  for
    limits in [
      { ..exact, max_work: 25, },
      { ..exact, max_text_units: 9, },
      { ..exact, max_bytes: wire.length() - 1, },
      { ..exact, max_nodes: 3, },
      { ..exact, max_depth: 1, },
    ] {
    assert_eq(
      prepare_notion_date_range_property_write(source, 0, start, end, limits).unwrap_err(),
      BudgetExceeded,
    )
  }
}

///|
test "Notion range final body retains original duplicate and foreign property refusal" {
  let source = write_test_source("date")
  let start = range_test_value("date", "\"2024-02-29\"")
  let end = range_test_value("date", "\"2024-03-01\"")
  let write = prepare_notion_date_range_property_write(
    source,
    0,
    start,
    end,
    write_test_limits(),
  ).unwrap()
  assert_eq(
    notion_page_properties_write_wire(
      source,
      [write, write],
      write_test_limits(),
    ).unwrap_err(),
    DuplicateProperty("p%3Ax"),
  )
  assert_eq(
    notion_page_properties_write_wire(
      write_test_source("date"),
      [write],
      write_test_limits(),
    ).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    prepare_notion_date_range_property_write(
      source,
      1,
      start,
      end,
      write_test_limits(),
    ).unwrap_err(),
    InvalidSelection,
  )
  assert_eq(
    prepare_notion_date_range_property_write(
      write_test_source("number"),
      0,
      start,
      end,
      write_test_limits(),
    ).unwrap_err(),
    UnsupportedProperty("p%3Ax"),
  )
  assert_eq(
    prepare_notion_date_range_property_write(source, 0, start, end, {
      ..write_test_limits(),
      max_work: 0,
    }).unwrap_err(),
    InvalidLimits,
  )
}
