///|
test "object schema retains the original record key and every selected Common carrier" {
  let original = object_catalog()
  let names = ["tags", "instant", "name", "live", "amount", "day"]
  let expected =
    #|{"amount":{"nullable":true,"precision":38,"scale":10,"type":"decimal"},"day":{"nullable":true,"type":"date"},"id":{"nullable":false,"type":"string"},"instant":{"nullable":true,"type":"timestamp"},"live":{"nullable":true,"type":"boolean"},"name":{"nullable":true,"type":"string"},"tags":{"items":{"nullable":false,"type":"string"},"nullable":true,"type":"array"}}
  assert_eq(
    object_schema_wire(original, names, 7, 100, 4096, 100, 10),
    Ok(expected),
  )
  assert_eq(
    object_schema_wire(
      original,
      ["amount", "day", "live", "name", "instant", "tags"],
      7,
      100,
      4096,
      100,
      10,
    ),
    Ok(expected),
  )
  assert_eq(property_names(original), [
    "name", "amount", "live", "day", "instant", "tags", "stage",
  ])
}

///|
test "schema selection never replaces the record key or discards unsupported selected properties" {
  let original = catalog(
    (
      #|{"results":[{"name":"name","type":"string","fieldType":"text"},{"name":"unknown","type":"new_native_type","fieldType":"text"},{"name":"id","type":"string","fieldType":"text"}]}
    ),
  )
  assert_eq(
    object_schema_wire(original, ["name"], 2, 100, 4096, 100, 10),
    Ok(
      "{\"id\":{\"nullable\":false,\"type\":\"string\"},\"name\":{\"nullable\":true,\"type\":\"string\"}}",
    ),
  )
  assert_eq(
    object_schema_wire(original, ["unknown"], 2, 100, 4096, 100, 10),
    Err(Property(UnsupportedProperty("unknown"))),
  )
  assert_eq(
    object_schema_wire(original, ["missing"], 2, 100, 4096, 100, 10),
    Err(Property(PropertyUnconfirmed("missing"))),
  )
  for names in [["id"], ["name", "name"]] {
    let duplicate = if names[0] == "id" { "id" } else { "name" }
    assert_eq(
      object_schema_wire(original, names, 3, 100, 4096, 100, 10),
      Err(DuplicateSelection(duplicate)),
    )
  }
  assert_eq(
    object_schema_wire(original, [], 1, 2, 100, 10, 3),
    Ok("{\"id\":{\"nullable\":false,\"type\":\"string\"}}"),
  )
}

///|
test "complete schema output bounds are separate from original metadata admission" {
  let original = object_catalog()
  let expected = "{\"id\":{\"nullable\":false,\"type\":\"string\"},\"name\":{\"nullable\":true,\"type\":\"string\"}}"
  let bytes = @utf8.encode(expected).length()
  assert_eq(
    object_schema_wire(original, ["name"], 2, 6, bytes, 100, 10),
    Ok(expected),
  )
  assert_eq(
    object_schema_wire(original, ["name"], 1, 6, bytes, 100, 10),
    Err(BudgetExceeded),
  )
  assert_eq(
    object_schema_wire(original, ["name"], 2, 5, bytes, 100, 10),
    Err(BudgetExceeded),
  )
  assert_eq(
    object_schema_wire(original, ["name"], 2, 6, bytes - 1, 100, 10),
    Err(BudgetExceeded),
  )
  assert_eq(
    object_schema_wire(original, ["name"], 2, 6, bytes, 1, 10),
    Err(BudgetExceeded),
  )
  assert_eq(
    object_schema_wire(original, ["name"], 2, 6, bytes, 100, 1),
    Err(BudgetExceeded),
  )
  for index in 0..<5 {
    let limits = [2, 6, bytes, 100, 10]
    limits[index] = 0
    assert_eq(
      object_schema_wire(
        original,
        ["name"],
        limits[0],
        limits[1],
        limits[2],
        limits[3],
        limits[4],
      ),
      Err(InvalidLimits),
    )
  }
}

///|
test "schema names use original UTF8 budget and Common canonical validation without repair" {
  let original = catalog(
    (
      #|{"results":[{"name":"é","type":"string","fieldType":"text"},{"name":"😀","type":"string","fieldType":"text"},{"name":"e\u0301","type":"string","fieldType":"text"},{"name":"a.b","type":"string","fieldType":"text"}]}
    ),
  )
  let expected =
    #|{"id":{"nullable":false,"type":"string"},"é":{"nullable":true,"type":"string"},"😀":{"nullable":true,"type":"string"}}
  assert_eq(
    object_schema_wire(original, ["😀", "é"], 3, 8, 4096, 100, 10),
    Ok(expected),
  )
  assert_eq(
    object_schema_wire(original, ["😀", "é"], 3, 7, 4096, 100, 10),
    Err(BudgetExceeded),
  )
  for name in ["e\u{0301}", "a.b"] {
    assert_eq(
      object_schema_wire(original, [name], 2, 100, 4096, 100, 10),
      Err(InvalidResponse),
    )
  }
}
