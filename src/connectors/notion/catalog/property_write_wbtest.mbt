///|
fn write_test_limits() -> NotionPropertyWriteLimits {
  {
    max_bytes: 65536,
    max_nodes: 4096,
    max_depth: 16,
    max_properties: 16,
    max_items: 100,
    max_text_units: 10000,
    max_work: 100000,
  }
}

///|
fn write_test_source(
  kind : String,
  body? : String = "{}",
) -> NotionDataSourceCatalog {
  let wire = "{\"object\":\"data_source\",\"id\":\"s2\",\"parent\":{\"type\":\"database_id\",\"database_id\":\"db\"},\"properties\":{\"é\":{\"id\":\"p%3Ax\",\"name\":\"é\",\"type\":\"" +
    kind +
    "\",\"" +
    kind +
    "\":" +
    body +
    "}}}"
  project_notion_data_source(
    database_test_original(),
    1,
    @utf8.encode(wire),
    database_test_limits(),
  ).unwrap()
}

///|
fn write_test_value(
  contract : String,
  value : String,
) -> @admitted.CheckedValue {
  let limits = { max_nodes: 512, max_depth: 16, max_text_bytes: 65536, }
  let metadata = {
    ..database_test_limits(),
    max_bytes: 65536,
    max_nodes: 2048,
  }
  let contract = @contract.read_checked(
    database_cursor(@utf8.encode(contract), metadata).unwrap(),
    limits,
  ).unwrap()
  @admitted.admit_wire(
    contract,
    database_cursor(@utf8.encode(value), metadata).unwrap(),
    limits,
  ).unwrap()
}

///|
fn write_test_text(value : String) -> @admitted.CheckedValue {
  @admitted.checked_text_value(
    value,
    @contract.primitive(StringType, nullable=false),
  ).unwrap()
}

///|
fn write_test_wire(
  source : NotionDataSourceCatalog,
  value : @admitted.CheckedValue,
) -> String {
  let write = prepare_notion_property_write(
    source,
    0,
    value,
    write_test_limits(),
  ).unwrap()
  notion_page_properties_write_wire(source, [write], write_test_limits()).unwrap()
}

///|
test "Notion property writes retain exact Decimal tokens and never round through Number" {
  let source = write_test_source("number")
  let value = write_test_value(
    "{\"type\":\"decimal\",\"nullable\":false,\"precision\":20,\"scale\":2}", "\"9007199254740993.25\"",
  )
  assert_eq(
    write_test_wire(source, value),
    "{\"properties\":{\"p%3Ax\":{\"number\":9007199254740993.25}}}",
  )
  let number = @admitted.checked_number_value(
    42.0,
    @contract.primitive(NumberType, nullable=false),
  ).unwrap()
  assert_eq(
    prepare_notion_property_write(source, 0, number, write_test_limits()).unwrap_err(),
    InvalidValue("p%3Ax"),
  )
  assert_eq(
    prepare_notion_property_write(
      source,
      0,
      write_test_text("42"),
      write_test_limits(),
    ).unwrap_err(),
    InvalidValue("p%3Ax"),
  )
}

///|
test "Notion property write identity binds original source and checked input without display-name substitution" {
  let source = write_test_source("checkbox")
  let value = @admitted.checked_boolean_value(
    false,
    @contract.primitive(BooleanType, nullable=false),
  ).unwrap()
  let write = prepare_notion_property_write(
    source,
    0,
    value,
    write_test_limits(),
  ).unwrap()
  assert_eq(
    write_test_wire(source, value),
    "{\"properties\":{\"p%3Ax\":{\"checkbox\":false}}}",
  )
  assert_true(notion_property_write_matches(write, source, value))
  assert_true(
    !notion_property_write_matches(write, write_test_source("checkbox"), value),
  )
  let copy = @admitted.checked_boolean_value(false, value.contract).unwrap()
  assert_true(!notion_property_write_matches(write, source, copy))
  assert_eq(
    notion_page_properties_write_wire(
      write_test_source("checkbox"),
      [write],
      write_test_limits(),
    ).unwrap_err(),
    ForeignOriginal,
  )
  assert_eq(
    notion_page_properties_write_wire(
      source,
      [write, write],
      write_test_limits(),
    ).unwrap_err(),
    DuplicateProperty("p%3Ax"),
  )
  assert_eq(
    prepare_notion_property_write(source, -1, value, write_test_limits()).unwrap_err(),
    InvalidSelection,
  )
}

///|
test "Notion rich text splits without losing Unicode or emitting more than the actual item budget" {
  let source = write_test_source("rich_text")
  let text = String::make(1999, 'a') + "😀é"
  let value = write_test_text(text)
  let output = write_test_wire(source, value)
  let cursor = database_cursor(@utf8.encode(output), {
    ..database_test_limits(),
    max_bytes: 65536,
  }).unwrap()
  let root = @decode.open_object(cursor).unwrap()
  let props = @decode.open_object(@decode.lookup(root, "properties").unwrap()).unwrap()
  let prop = @decode.open_object(@decode.lookup(props, "p%3Ax").unwrap()).unwrap()
  let parts = @decode.lookup(prop, "rich_text").unwrap()
  assert_eq(@decode.array_length(parts), Some(2))
  let joined = StringBuilder()
  for i in 0..<2 {
    let part = @decode.open_object(@decode.element_at(parts, i).unwrap()).unwrap()
    let content = @decode.open_object(@decode.lookup(part, "text").unwrap()).unwrap()
    joined.write_string(
      @decode.text(@decode.lookup(content, "content").unwrap()).unwrap(),
    )
  }
  assert_eq(joined.to_string(), text)
  assert_eq(
    prepare_notion_property_write(source, 0, value, {
      ..write_test_limits(),
      max_items: 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    write_test_wire(source, write_test_text("")),
    "{\"properties\":{\"p%3Ax\":{\"rich_text\":[]}}}",
  )
}

///|
test "Notion select and status use only exact original option identities and check unused options" {
  for kind in ["select", "status"] {
    let source = write_test_source(
      kind,
      body="{\"options\":[{\"id\":\"a\",\"name\":\"é\"},{\"id\":\"b\",\"name\":\"Done\"}]}",
    )
    assert_eq(
      write_test_wire(source, write_test_text("Done")),
      "{\"properties\":{\"p%3Ax\":{\"" + kind + "\":{\"id\":\"b\"}}}}",
    )
    assert_eq(
      prepare_notion_property_write(
        source,
        0,
        write_test_text("é"),
        write_test_limits(),
      ).unwrap_err(),
      UnknownOption("p%3Ax"),
    )
    assert_eq(
      prepare_notion_property_write(
        source,
        0,
        write_test_text("new option"),
        write_test_limits(),
      ).unwrap_err(),
      UnknownOption("p%3Ax"),
    )
    let malformed = write_test_source(
      kind,
      body="{\"options\":[{\"id\":\"b\",\"name\":\"Done\"},{\"id\":\"z\",\"name\":null}]}",
    )
    assert_eq(
      prepare_notion_property_write(
        malformed,
        0,
        write_test_text("Done"),
        write_test_limits(),
      ).unwrap_err(),
      InvalidOptions("p%3Ax"),
    )
  }
}

///|
test "Notion nullable native fields retain null and never conflate false or empty text" {
  let null = @admitted.checked_null_value(
    @contract.primitive(StringType, nullable=true),
  ).unwrap()
  for kind in ["url", "email", "phone_number", "select", "status", "number"] {
    assert_eq(
      write_test_wire(write_test_source(kind), null),
      "{\"properties\":{\"p%3Ax\":{\"" + kind + "\":null}}}",
    )
  }
  for kind in ["title", "rich_text", "checkbox", "people", "relation"] {
    assert_eq(
      prepare_notion_property_write(
        write_test_source(kind),
        0,
        null,
        write_test_limits(),
      ).unwrap_err(),
      InvalidValue("p%3Ax"),
    )
  }
  assert_eq(
    prepare_notion_property_write(
      write_test_source("url"),
      0,
      write_test_text(""),
      write_test_limits(),
    ).unwrap_err(),
    InvalidValue("p%3Ax"),
  )
}

///|
test "Notion relation and people encode actual checked identifier arrays without issuing references" {
  let value = write_test_value(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    "[\"one\",\"é\"]",
  )
  for kind in ["people", "relation"] {
    let source = write_test_source(kind)
    assert_eq(
      write_test_wire(source, value),
      "{\"properties\":{\"p%3Ax\":{\"" +
      kind +
      "\":[{\"id\":\"one\"},{\"id\":\"é\"}]}}}",
    )
    assert_eq(
      prepare_notion_property_write(source, 0, value, {
        ..write_test_limits(),
        max_items: 1,
      }).unwrap_err(),
      BudgetExceeded,
    )
  }
}

///|
test "Notion computed native properties and unimplemented Content or temporal projections never become writable JSON" {
  for
    kind in [
      "formula", "rollup", "created_time", "last_edited_time", "created_by", "last_edited_by",
      "unique_id", "files", "date",
    ] {
    assert_eq(
      prepare_notion_property_write(
        write_test_source(kind),
        0,
        write_test_text("fake"),
        write_test_limits(),
      ).unwrap_err(),
      UnsupportedProperty("p%3Ax"),
    )
  }
}

///|
test "Notion property and aggregate writers fail closed at actual work and output bounds" {
  let source = write_test_source("title")
  let value = write_test_text("ab")
  let bounds = write_test_limits()
  let write = prepare_notion_property_write(source, 0, value, bounds).unwrap()
  let wire = notion_page_properties_write_wire(source, [write], bounds).unwrap()
  assert_eq(
    notion_page_properties_write_wire(source, [write], {
      ..bounds,
      max_bytes: wire.length(),
    }),
    Ok(wire),
  )
  assert_eq(
    notion_page_properties_write_wire(source, [write], {
      ..bounds,
      max_bytes: wire.length() - 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    prepare_notion_property_write(source, 0, value, { ..bounds, max_work: 1, }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    prepare_notion_property_write(source, 0, value, {
      ..bounds,
      max_text_units: 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    prepare_notion_property_write(source, 0, value, { ..bounds, max_nodes: 1, }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    prepare_notion_property_write(source, 0, value, { ..bounds, max_depth: 1, }).unwrap_err(),
    BudgetExceeded,
  )
  assert_eq(
    prepare_notion_property_write(source, 0, value, { ..bounds, max_bytes: 0, }).unwrap_err(),
    InvalidLimits,
  )
}
