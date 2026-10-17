///|
test "Notion people writes reject 101 supplied users at the actual vendor request boundary" {
  let value = write_test_value(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    "[" + Array::make(101, "\"user\"").join(",") + "]",
  )
  assert_eq(
    prepare_notion_property_write(write_test_source("people"), 0, value, {
      ..write_test_limits(),
      max_items: 101,
    }).unwrap_err(),
    BudgetExceeded,
  )
}

///|
fn projection_test_strings(value : String) -> @admitted.CheckedValue {
  write_test_value(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    value,
  )
}

///|
fn projection_test_options() -> NotionDataSourceCatalog {
  write_test_source(
    "multi_select",
    body="{\"options\":[{\"id\":\"a\",\"name\":\"é\"},{\"id\":\"b\",\"name\":\"Done\"}]}",
  )
}

///|
test "Notion people and relation writes retain vendor100 and stricter original supplied bounds" {
  let value = write_test_value(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    "[" + Array::make(100, "\"user\"").join(",") + "]",
  )
  for kind in ["people", "relation"] {
    let source = write_test_source(kind)
    assert_true(
      prepare_notion_property_write(source, 0, value, write_test_limits())
      is Ok(_),
    )
    assert_eq(
      prepare_notion_property_write(source, 0, value, {
        ..write_test_limits(),
        max_items: 99,
      }).unwrap_err(),
      BudgetExceeded,
    )
  }
}

///|
test "Notion multiselect encodes exact existing original ids and retains request order and occurrences" {
  let source = projection_test_options()
  let value = projection_test_strings("[\"Done\",\"é\",\"Done\"]")
  assert_eq(
    write_test_wire(source, value),
    "{\"properties\":{\"p%3Ax\":{\"multi_select\":[{\"id\":\"b\"},{\"id\":\"a\"},{\"id\":\"b\"}]}}}",
  )
  let original = prepare_notion_property_write(
    source,
    0,
    value,
    write_test_limits(),
  ).unwrap()
  assert_true(notion_property_write_matches(original, source, 0, value))
  assert_true(
    !notion_property_write_matches(
      original,
      projection_test_options(),
      0,
      value,
    ),
  )
  assert_true(
    !notion_property_write_matches(
      original,
      source,
      0,
      projection_test_strings("[\"Done\",\"é\",\"Done\"]"),
    ),
  )
}

///|
test "Notion multiselect empty array clears but null scalar and nontext elements never replace it" {
  let source = write_test_source("multi_select", body="{\"options\":[]}")
  let empty = projection_test_strings("[]")
  let write = prepare_notion_property_write(source, 0, empty, {
    ..write_test_limits(),
    max_items: 0,
  }).unwrap()
  assert_eq(
    notion_page_properties_write_wire(source, [write], write_test_limits()).unwrap(),
    "{\"properties\":{\"p%3Ax\":{\"multi_select\":[]}}}",
  )
  let null = @admitted.checked_null_value(
    @contract.primitive(StringType, nullable=true),
  ).unwrap()
  for
    value in [
      null,
      write_test_text("Done"),
      write_test_value(
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"boolean\",\"nullable\":false}}",
        "[false]",
      ),
    ] {
    assert_eq(
      prepare_notion_property_write(source, 0, value, write_test_limits()).unwrap_err(),
      InvalidValue("p%3Ax"),
    )
  }
}

///|
test "Notion multiselect never creates unknown normalized names or ignores malformed unselected options" {
  let source = projection_test_options()
  for text in ["[\"é\"]", "[\"new\"]"] {
    assert_eq(
      prepare_notion_property_write(
        source,
        0,
        projection_test_strings(text),
        write_test_limits(),
      ).unwrap_err(),
      UnknownOption("p%3Ax"),
    )
  }
  for
    body in [
      "{}", "{\"options\":null}", "{\"options\":[{\"id\":\"a\",\"name\":\"Done\"},{\"id\":\"b\",\"name\":null}]}",
      "{\"options\":[{\"id\":\"a\",\"name\":\"Done\"},{\"id\":\"a\",\"name\":\"Other\"}]}",
      "{\"options\":[{\"id\":\"a\",\"name\":\"Done\"},{\"id\":\"b\",\"name\":\"Done\"}]}",
    ] {
    for raw in ["[]", "[\"Done\"]"] {
      assert_eq(
        prepare_notion_property_write(
          write_test_source("multi_select", body~),
          0,
          projection_test_strings(raw),
          write_test_limits(),
        ).unwrap_err(),
        InvalidOptions("p%3Ax"),
      )
    }
  }
}

///|
test "Notion multiselect charges every original option and supplied occurrence at exact work and item limits" {
  let source = projection_test_options()
  let value = projection_test_strings("[\"Done\"]")
  assert_true(
    prepare_notion_property_write(source, 0, value, {
      ..write_test_limits(),
      max_work: 33,
    })
    is Ok(_),
  )
  assert_eq(
    prepare_notion_property_write(source, 0, value, {
      ..write_test_limits(),
      max_work: 32,
    }).unwrap_err(),
    BudgetExceeded,
  )
  let empty = projection_test_strings("[]")
  assert_true(
    prepare_notion_property_write(source, 0, empty, {
      ..write_test_limits(),
      max_work: 24,
    })
    is Ok(_),
  )
  assert_eq(
    prepare_notion_property_write(source, 0, empty, {
      ..write_test_limits(),
      max_work: 23,
    }).unwrap_err(),
    BudgetExceeded,
  )
  let hundred = projection_test_strings(
    "[" + Array::make(100, "\"Done\"").join(",") + "]",
  )
  assert_true(
    prepare_notion_property_write(source, 0, hundred, write_test_limits())
    is Ok(_),
  )
  let over = projection_test_strings(
    "[" + Array::make(101, "\"Done\"").join(",") + "]",
  )
  assert_eq(
    prepare_notion_property_write(source, 0, over, {
      ..write_test_limits(),
      max_items: 101,
    }).unwrap_err(),
    BudgetExceeded,
  )
}

///|
test "Notion date writes consume original checked Date and Timestamp without text parsing or timezone defaults" {
  let source = write_test_source("date")
  let date = write_test_value(
    "{\"type\":\"date\",\"nullable\":false}", "\"2024-02-29\"",
  )
  assert_eq(
    write_test_wire(source, date),
    "{\"properties\":{\"p%3Ax\":{\"date\":{\"start\":\"2024-02-29\"}}}}",
  )
  let timestamp = write_test_value(
    "{\"type\":\"timestamp\",\"nullable\":false}", "\"2024-02-29T12:34:56.789Z\"",
  )
  assert_eq(
    write_test_wire(source, timestamp),
    "{\"properties\":{\"p%3Ax\":{\"date\":{\"start\":\"2024-02-29T12:34:56.789Z\"}}}}",
  )
  for
    text in [
      "2024-02-29", "2024-02-29T12:34:56.789Z", "2024-02-29T12:34:56-07:00",
    ] {
    assert_eq(
      prepare_notion_property_write(
        source,
        0,
        write_test_text(text),
        write_test_limits(),
      ).unwrap_err(),
      InvalidValue("p%3Ax"),
    )
  }
}

///|
test "Notion date clearing retains explicit null and refuses to discard supplied range or timezone fields" {
  let source = write_test_source("date")
  let null = @admitted.checked_null_value(
    @contract.primitive(DateType, nullable=true),
  ).unwrap()
  assert_eq(
    write_test_wire(source, null),
    "{\"properties\":{\"p%3Ax\":{\"date\":null}}}",
  )
  let range = write_test_value(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"start\":{\"type\":\"date\",\"nullable\":false},\"end\":{\"type\":\"date\",\"nullable\":true}},\"additional_properties\":false}",
    "{\"start\":\"2024-02-29\",\"end\":\"2024-03-01\"}",
  )
  assert_eq(
    prepare_notion_property_write(source, 0, range, write_test_limits()).unwrap_err(),
    InvalidValue("p%3Ax"),
  )
}

///|
test "Notion typed temporal writer preserves actual text work and encoder refusal boundaries" {
  let source = write_test_source("date")
  let date = write_test_value(
    "{\"type\":\"date\",\"nullable\":false}", "\"2024-02-29\"",
  )
  assert_true(
    prepare_notion_property_write(source, 0, date, {
      ..write_test_limits(),
      max_work: 16,
      max_text_units: 10,
    })
    is Ok(_),
  )
  for
    bounds in [
      { ..write_test_limits(), max_work: 15, },
      { ..write_test_limits(), max_text_units: 9, },
      { ..write_test_limits(), max_nodes: 2, },
      { ..write_test_limits(), max_depth: 1, },
    ] {
    assert_eq(
      prepare_notion_property_write(source, 0, date, bounds).unwrap_err(),
      BudgetExceeded,
    )
  }
}
