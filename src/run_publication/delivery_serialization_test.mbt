///|
fn delivery_schema_wire() -> String {
  (
    #|{"amount":{"nullable":false,"precision":4,"scale":2,"type":"decimal"},"enabled":{"nullable":false,"type":"boolean"},"meta":{"additional_properties":false,"fields":{"k":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"missing":{"nullable":true,"type":"number"},"name":{"nullable":false,"type":"string"},"score":{"nullable":false,"type":"number"}}
  )
}

///|
test "JSON delivery retains domain tags data keys and declared column order" {
  let schema = "{\"j\":{\"nullable\":true,\"type\":\"json\"},\"sql\":{\"nullable\":true,\"type\":\"number\"}}"
  let value = prepare_result_delivery_serializer(
    "jsonl",
    schema,
    ["sql", "j"],
    4096,
    100,
    10,
  ).unwrap()
  assert_eq(begin_result_delivery(value), Ok(""))
  for
    (wire, expected) in [
      (
        "{\"j\":{\"$json\":null},\"sql\":null}", "{\"sql\":null,\"j\":{\"$json\":null}}\n",
      ),
      (
        "{\"j\":{\"$json\":{\"e\u{301}\":1,\"é\":2}},\"sql\":null}", "{\"sql\":null,\"j\":{\"$json\":{\"e\u{301}\":1,\"é\":2}}}\n",
      ),
      ("{\"j\":null,\"sql\":null}", "{\"sql\":null,\"j\":null}\n"),
    ] {
    assert_eq(next_result_delivery_row(value, wire), Ok(expected))
  }
  assert_eq(finish_result_delivery(value), Ok(""))
}

///|
fn delivery_fields() -> Array[String] {
  ["name", "score", "amount", "enabled", "missing", "meta"]
}

///|
fn serializer(format : String) -> ResultDeliverySerializer {
  prepare_result_delivery_serializer(
    format,
    delivery_schema_wire(),
    delivery_fields(),
    4096,
    64,
    8,
  ).unwrap()
}

///|
test "canonical Result delivery preserves declared order and format rules" {
  let row =
    #|{"amount":"2.30","enabled":false,"meta":{"k":"é"},"missing":null,"name":"x,\"y","score":1.5}
  let expected_json =
    #|{"name":"x,\"y","score":1.5,"amount":"2.30","enabled":false,"missing":null,"meta":{"k":"é"}}
  let json = serializer("json")
  assert_eq(begin_result_delivery(json), Ok("["))
  assert_eq(next_result_delivery_row(json, row), Ok(expected_json))
  assert_eq(finish_result_delivery(json), Ok("]"))

  let jsonl = serializer("jsonl")
  assert_eq(begin_result_delivery(jsonl), Ok(""))
  assert_eq(next_result_delivery_row(jsonl, row), Ok(expected_json + "\n"))
  assert_eq(finish_result_delivery(jsonl), Ok(""))

  let csv = serializer("csv")
  assert_eq(
    begin_result_delivery(csv),
    Ok("\"name\",\"score\",\"amount\",\"enabled\",\"missing\",\"meta\"\n"),
  )
  assert_eq(
    next_result_delivery_row(csv, row),
    Ok("\"x,\"\"y\",1.5,2.30,false,\\N,\"{\"\"k\"\":\"\"é\"\"}\"\n"),
  )
  assert_eq(finish_result_delivery(csv), Ok(""))
}

///|
test "empty delivery has exact delimiters and CSV header" {
  let json = serializer("json")
  assert_eq(begin_result_delivery(json), Ok("["))
  assert_eq(finish_result_delivery(json), Ok("]"))
  let jsonl = serializer("jsonl")
  assert_eq(begin_result_delivery(jsonl), Ok(""))
  assert_eq(finish_result_delivery(jsonl), Ok(""))
  let csv = serializer("csv")
  assert_true(begin_result_delivery(csv).unwrap().has_suffix("\n"))
  assert_eq(finish_result_delivery(csv), Ok(""))
}

///|
test "delivery rejects missing fields type mismatches NUL and reuse" {
  let missing = serializer("json")
  ignore(begin_result_delivery(missing))
  assert_true(
    next_result_delivery_row(
      missing,
      (
        #|{"amount":"2.30","enabled":false,"meta":{"k":"x"},"missing":null,"name":"x"}
      ),
    )
    is Err(DeliverySerializationInvalidRow),
  )
  let wrong = serializer("csv")
  ignore(begin_result_delivery(wrong))
  assert_true(
    next_result_delivery_row(
      wrong,
      (
        #|{"amount":"2.30","enabled":false,"meta":{"k":"x"},"missing":null,"name":"x","score":"1.5"}
      ),
    )
    is Err(DeliverySerializationTypeMismatch("number")),
  )
  let nul = serializer("csv")
  ignore(begin_result_delivery(nul))
  assert_true(
    next_result_delivery_row(
      nul, "{\"amount\":\"2.30\",\"enabled\":false,\"meta\":{\"k\":\"x\"},\"missing\":null,\"name\":\"x\\u0000y\",\"score\":1.5}",
    )
    is Err(DeliverySerializationNul),
  )
  let closed = serializer("json")
  assert_eq(begin_result_delivery(closed), Ok("["))
  assert_eq(finish_result_delivery(closed), Ok("]"))
  assert_true(
    next_result_delivery_row(closed, "{}") is Err(DeliverySerializationClosed),
  )
}

///|
test "serializer validates exact schema coverage and output bounds" {
  assert_true(
    prepare_result_delivery_serializer(
      "yaml",
      delivery_schema_wire(),
      delivery_fields(),
      4096,
      64,
      8,
    )
    is Err(DeliverySerializationUnsupportedFormat("yaml")),
  )
  assert_true(
    prepare_result_delivery_serializer(
      "json",
      delivery_schema_wire(),
      ["name"],
      4096,
      64,
      8,
    )
    is Err(DeliverySerializationInvalidFields),
  )
  let bounded = prepare_result_delivery_serializer(
    "json",
    "{\"x\":{\"nullable\":false,\"type\":\"string\"}}",
    ["x"],
    48,
    16,
    4,
  ).unwrap()
  assert_eq(begin_result_delivery(bounded), Ok("["))
  assert_true(
    next_result_delivery_row(
      bounded, "{\"x\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}",
    )
    is Ok(_),
  )
  assert_true(
    next_result_delivery_row(
      bounded, "{\"x\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}",
    )
    is Err(DeliverySerializationOutputLimit),
  )
}

///|
test "CSV delivery preserves admitted safe integers" {
  let integer = prepare_result_delivery_serializer(
    "csv",
    "{\"value\":{\"nullable\":false,\"type\":\"integer\"}}",
    ["value"],
    4096,
    32,
    8,
  ).unwrap()
  assert_eq(begin_result_delivery(integer), Ok("\"value\"\n"))
  assert_eq(next_result_delivery_row(integer, "{\"value\":7}"), Ok("7\n"))
  assert_true(
    next_result_delivery_row(integer, "{\"value\":1.5}")
    is Err(DeliverySerializationTypeMismatch("integer")),
  )
}
