///|
fn write_limits() -> WriteBodyLimits {
  {
    max_input_bytes: 4096,
    max_nodes: 1000,
    max_depth: 20,
    max_fields: 10,
    max_name_bytes: 100,
    max_value_nodes: 1000,
    max_value_text_bytes: 4096,
    max_comparison_work: 10000,
    max_output_bytes: 4096,
    max_output_nodes: 1000,
    max_output_depth: 20,
  }
}

///|
fn write_catalog() -> PropertyCatalog {
  catalog(
    (
      #|{"results":[{"name":"name","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"amount","type":"number","fieldType":"number","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"live","type":"bool","fieldType":"booleancheckbox","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"day","type":"date","fieldType":"date","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"instant","type":"datetime","fieldType":"date","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"tags","type":"enumeration","fieldType":"checkbox","options":[{"value":"a"},{"value":"b"}],"calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"qualified","label":"Qualified lead"}],"calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
}

///|
test "write candidate preserves every Common carrier in independently expected provider strings" {
  let names = ["tags", "stage", "name", "live", "instant", "day", "amount"]
  let body = prepare_write_body(
    write_catalog(),
    names,
    @utf8.encode(
      (
        #|{"name":"Café","tags":["a","b"],"stage":"qualified","live":true,"instant":"2024-02-29T12:34:56.789Z","day":"2024-02-29","amount":"9007199254740993.0100000000"}
      ),
    ),
    write_limits(),
  ).unwrap()
  assert_eq(
    write_body_properties_json(body),
    (
      #|{"amount":"9007199254740993.0100000000","day":"2024-02-29","instant":"2024-02-29T12:34:56.789Z","live":"true","name":"Café","stage":"qualified","tags":"a;b"}
    ),
  )
  assert_eq(
    write_body_value_json(body),
    (
      #|{"amount":"9007199254740993.0100000000","day":"2024-02-29","instant":"2024-02-29T12:34:56.789Z","live":true,"name":"Café","stage":"qualified","tags":["a","b"]}
    ),
  )
  assert_eq(write_body_property_names(body), names)
}

///|
test "write fields are the original complete mapping and may not be silently omitted or injected" {
  let properties = write_catalog()
  assert_true(
    prepare_write_body(properties, ["name"], @utf8.encode("{}"), write_limits())
    is Err(MissingField("name")),
  )
  assert_true(
    prepare_write_body(
      properties,
      ["name"],
      @utf8.encode("{\"name\":\"x\",\"foreign\":1}"),
      write_limits(),
    )
    is Err(UnexpectedField("foreign")),
  )
  assert_true(
    prepare_write_body(
      properties,
      ["name"],
      @utf8.encode("{\"name\":\"x\",\"name\":\"y\"}"),
      write_limits(),
    )
    is Err(InvalidBody),
  )
  assert_true(
    prepare_write_body(
      properties,
      ["name", "name"],
      @utf8.encode("{\"name\":\"x\"}"),
      write_limits(),
    )
    is Err(InvalidBody),
  )
  assert_true(
    prepare_write_body(
      properties,
      ["missing"],
      @utf8.encode("{\"missing\":\"x\"}"),
      write_limits(),
    )
    is Err(Property(PropertyUnconfirmed("missing"))),
  )
}

///|
test "writability comes only from positive original metadata not its input value" {
  let properties = catalog(
    (
      #|{"results":[{"name":"unknown","type":"string","fieldType":"text"},{"name":"calculated","type":"number","fieldType":"calculation_equation","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"readonly","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":true}},{"name":"archived","type":"string","fieldType":"text","archived":true,"calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
  assert_true(
    prepare_write_body(
      properties,
      ["unknown"],
      @utf8.encode("{\"unknown\":\"x\"}"),
      write_limits(),
    )
    is Err(Property(WriteUnconfirmed("unknown"))),
  )
  for name in ["calculated", "readonly", "archived"] {
    assert_true(
      prepare_write_body(properties, [name], @utf8.encode("{}"), write_limits())
      is Err(Property(ReadOnlyProperty(_))),
    )
  }
}

///|
test "options use internal metadata values and never labels or unobserved additions" {
  let properties = write_catalog()
  assert_true(
    prepare_write_body(
      properties,
      ["stage"],
      @utf8.encode("{\"stage\":\"Qualified lead\"}"),
      write_limits(),
    )
    is Err(UnlistedOption("stage")),
  )
  assert_true(
    prepare_write_body(
      properties,
      ["tags"],
      @utf8.encode("{\"tags\":[\"a\",\"new\"]}"),
      write_limits(),
    )
    is Err(UnlistedOption("tags")),
  )
  assert_true(
    prepare_write_body(
      properties,
      ["tags"],
      @utf8.encode("{\"tags\":[null]}"),
      write_limits(),
    )
    is Err(ValueAdmission("tags", _)),
  )
}

///|
test "checkbox representation never appends changes a delimiter or erases an empty array element" {
  let properties = write_catalog()
  for
    value in [
      "{\"tags\":[\"\",\"a\"]}", "{\"tags\":[\"a;b\"]}", "{\"tags\":[\";a\"]}",
    ] {
    assert_true(
      prepare_write_body(
        properties,
        ["tags"],
        @utf8.encode(value),
        write_limits(),
      )
      is Err(UnrepresentableValue("tags")),
    )
  }
  let body = prepare_write_body(
    properties,
    ["tags"],
    @utf8.encode("{\"tags\":[]}"),
    write_limits(),
  ).unwrap()
  assert_eq(write_body_properties_json(body), "{\"tags\":\"\"}")
  assert_eq(write_body_value_json(body), "{\"tags\":[]}")
}

///|
test "clear spellings roundtrip through the actual original read decoder rather than unconditionally coercing null" {
  let properties = write_catalog()
  let body = prepare_write_body(
    properties,
    ["amount", "live", "day", "instant", "stage"],
    @utf8.encode(
      "{\"amount\":null,\"live\":null,\"day\":null,\"instant\":null,\"stage\":null}",
    ),
    write_limits(),
  ).unwrap()
  assert_eq(
    write_body_properties_json(body),
    "{\"amount\":\"\",\"day\":\"\",\"instant\":\"\",\"live\":\"\",\"stage\":\"\"}",
  )
  assert_eq(
    write_body_value_json(body),
    "{\"amount\":null,\"day\":null,\"instant\":null,\"live\":null,\"stage\":null}",
  )
  for (name, wire) in [("name", "{\"name\":null}"), ("tags", "{\"tags\":null}")] {
    assert_true(
      prepare_write_body(properties, [name], @utf8.encode(wire), write_limits())
      is Err(UnrepresentableValue(_)),
    )
  }
  let empty = prepare_write_body(
    properties,
    ["name"],
    @utf8.encode("{\"name\":\"\"}"),
    write_limits(),
  ).unwrap()
  assert_eq(write_body_value_json(empty), "{\"name\":\"\"}")
}

///|
test "decimal38 remains exact and a binary64 numeric token is never used as an approved decimal" {
  let properties = write_catalog()
  for
    wire in [
      "{\"amount\":9007199254740993.01}", "{\"amount\":\"1.00000000001\"}", "{\"amount\":\"1.2\"}",
    ] {
    assert_true(
      prepare_write_body(
        properties,
        ["amount"],
        @utf8.encode(wire),
        write_limits(),
      )
      is Err(ValueAdmission("amount", _)),
    )
  }
  let negative = prepare_write_body(
    properties,
    ["amount"],
    @utf8.encode("{\"amount\":\"-0.0100000000\"}"),
    write_limits(),
  ).unwrap()
  assert_eq(
    write_body_properties_json(negative),
    "{\"amount\":\"-0.0100000000\"}",
  )
}

///|
test "original temporal types reject invalid leap days offsets and submillisecond spellings" {
  let properties = write_catalog()
  for
    (name, wire) in [
      ("day", "{\"day\":\"2023-02-29\"}"),
      ("instant", "{\"instant\":\"2024-02-29T12:34:56.789000Z\"}"),
      ("instant", "{\"instant\":\"2024-02-29T12:34:56.789+00:00\"}"),
    ] {
    assert_true(
      prepare_write_body(properties, [name], @utf8.encode(wire), write_limits())
      is Err(ValueAdmission(_, _)),
    )
  }
}

///|
test "candidate name projections cannot mutate the original mapped fields" {
  let names = ["name"]
  let body = prepare_write_body(
    write_catalog(),
    names,
    @utf8.encode("{\"name\":\"original\"}"),
    write_limits(),
  ).unwrap()
  names[0] = "injected"
  let projected = write_body_property_names(body)
  projected[0] = "replaced"
  projected.push("new")
  assert_eq(write_body_property_names(body), ["name"])
  assert_eq(write_body_properties_json(body), "{\"name\":\"original\"}")
}

///|
test "body recheck uses the complete same original Catalog rather than response digest equality" {
  let original = write_catalog()
  let body = prepare_write_body(
    original,
    ["name"],
    @utf8.encode("{\"name\":\"original\"}"),
    write_limits(),
  ).unwrap()
  assert_eq(recheck_write_body(body, write_catalog(), 100), Ok(()))
  let changed = catalog(
    (
      #|{"results":[{"name":"name","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
  assert_eq(recheck_write_body(body, changed, 100), Err(ForeignCatalog))
  assert_eq(recheck_write_body(body, original, 0), Err(InvalidLimits))
}

///|
test "complete UTF8 input and each full output are independently bounded" {
  let properties = write_catalog()
  let wire = "{\"name\":\"é\"}"
  let input_bytes = @utf8.encode(wire).length()
  assert_true(
    prepare_write_body(properties, ["name"], @utf8.encode(wire), {
      ..write_limits(),
      max_input_bytes: input_bytes,
      max_output_bytes: input_bytes,
    })
    is Ok(_),
  )
  assert_true(
    prepare_write_body(properties, ["name"], @utf8.encode(wire), {
      ..write_limits(),
      max_input_bytes: input_bytes - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_write_body(properties, ["name"], @utf8.encode(wire), {
      ..write_limits(),
      max_output_bytes: input_bytes - 1,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "every representation and comparison budget refuses without a partial candidate" {
  let properties = write_catalog()
  let wire = @utf8.encode("{\"tags\":[\"a\",\"b\"]}")
  for index in 0..<5 {
    let full = write_limits()
    let limits = match index {
      0 => { ..full, max_nodes: 1, }
      1 => { ..full, max_value_nodes: 1, }
      2 => { ..full, max_comparison_work: 1, }
      3 => { ..full, max_output_nodes: 1, }
      _ => { ..full, max_output_depth: 1, }
    }
    assert_true(
      prepare_write_body(properties, ["tags"], wire, limits) is Err(_),
    )
  }
  for
    limit in [
      { ..write_limits(), max_input_bytes: 0, },
      { ..write_limits(), max_comparison_work: 0, },
      { ..write_limits(), max_fields: 0, },
      { ..write_limits(), max_name_bytes: 0, },
    ] {
    assert_true(
      prepare_write_body(properties, ["tags"], wire, limit)
      is Err(InvalidLimits),
    )
  }
}
