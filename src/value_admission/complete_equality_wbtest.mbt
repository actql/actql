///|
fn equality_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      source_path="complete-equality.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 20,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn equality_contract(text : String) -> @contract.Contract {
  @contract.read_checked(equality_cursor(text), {
    max_nodes: 1000,
    max_depth: 20,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn equality_value(contract : @contract.Contract, text : String) -> CheckedValue {
  admit(contract, equality_cursor(text), {
    max_nodes: 1000,
    max_depth: 20,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn values_equal(
  left : CheckedValue,
  right : CheckedValue,
  limits? : Limits = { max_nodes: 1000, max_depth: 20, max_text_bytes: 10000, },
  quantum? : Int = 1,
) -> Result[(Bool, Int), CompleteEqualityIssue] {
  let state = start_complete_equality(left, right, limits).unwrap()
  let mut work = 0
  while true {
    match advance_complete_equality(state, quantum) {
      EqualityContinue(work=used) => work += used
      EqualityComplete(equal~, work=used) => return Ok((equal, work + used))
      EqualityFailed(issue, work=used) => {
        ignore(used)
        return Err(issue)
      }
    }
  } nobreak {
    Err(CompleteEqualityTerminal)
  }
}

///|
test "complete equality handles nullable and nested property values" {
  let nullable_text = equality_contract(
    "{\"type\":\"string\",\"nullable\":true}",
  )
  assert_eq(
    values_equal(
      equality_value(nullable_text, "\"x\""),
      equality_value(nullable_text, "\"x\""),
    ).unwrap().0,
    true,
  )
  let required_text = equality_contract(
    "{\"type\":\"string\",\"nullable\":false}",
  )
  assert_eq(
    values_equal(
      equality_value(nullable_text, "\"x\""),
      equality_value(required_text, "\"x\""),
    ).unwrap().0,
    true,
  )
  assert_eq(
    values_equal(
      equality_value(nullable_text, "null"),
      equality_value(nullable_text, "null"),
    ).unwrap().0,
    true,
  )
  assert_eq(
    values_equal(
      equality_value(nullable_text, "null"),
      equality_value(nullable_text, "\"x\""),
    ).unwrap().0,
    false,
  )
  let nested = equality_contract(
    "{\"type\":\"object\",\"nullable\":false," +
    "\"additional_properties\":false,\"fields\":{" +
    "\"items\":{\"type\":\"array\",\"nullable\":false," +
    "\"items\":{\"type\":\"vector\",\"nullable\":false," +
    "\"dimensions\":2,\"element_type\":\"f32\"}}}}",
  )
  assert_eq(
    values_equal(
      equality_value(nested, "{\"items\":[[1,2],[3,4]]}"),
      equality_value(nested, "{\"items\":[[1,2],[3,4]]}"),
    ).unwrap().0,
    true,
  )
  assert_eq(
    values_equal(
      equality_value(nested, "{\"items\":[[1,2],[3,4]]}"),
      equality_value(nested, "{\"items\":[[1,2],[3,5]]}"),
    ).unwrap().0,
    false,
  )
}

///|
test "complete equality is resumable and enforces exact value limits" {
  let array = equality_contract(
    "{\"type\":\"array\",\"nullable\":false," +
    "\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  let left = equality_value(array, "[1,2,3]")
  let right = equality_value(array, "[1,2,3]")
  let (_, work) = values_equal(left, right).unwrap()
  assert_true(work > 1)
  assert_eq(
    values_equal(left, right, limits={
      max_nodes: 3,
      max_depth: 2,
      max_text_bytes: 0,
    }),
    Err(CompleteEqualityLimit),
  )
  assert_eq(
    values_equal(left, right, limits={
      max_nodes: 4,
      max_depth: 2,
      max_text_bytes: 0,
    }).unwrap().0,
    true,
  )
}

///|
test "complete equality shares admission node and depth limits" {
  let number = equality_contract("{\"type\":\"number\",\"nullable\":false}")
  let scalar = equality_value(number, "1")
  for quantum in [1, 2, 3, 4, 31, 32, 1024] {
    assert_eq(
      values_equal(
        scalar,
        scalar,
        limits={ max_nodes: 1, max_depth: 0, max_text_bytes: 0, },
        quantum~,
      ).unwrap().0,
      true,
    )
  }

  let vector = equality_contract(
    "{\"type\":\"vector\",\"nullable\":false," +
    "\"dimensions\":3,\"element_type\":\"f32\"}",
  )
  let vector_value = equality_value(vector, "[1,2,3]")
  for quantum in [1, 1024] {
    assert_eq(
      values_equal(
        vector_value,
        vector_value,
        limits={ max_nodes: 3, max_depth: 1, max_text_bytes: 0, },
        quantum~,
      ),
      Err(CompleteEqualityLimit),
    )
    assert_eq(
      values_equal(
        vector_value,
        vector_value,
        limits={ max_nodes: 4, max_depth: 1, max_text_bytes: 0, },
        quantum~,
      ).unwrap().0,
      true,
    )
  }

  let array = equality_contract(
    "{\"type\":\"array\",\"nullable\":false," +
    "\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  let array_value = equality_value(array, "[1]")
  assert_eq(
    values_equal(array_value, array_value, limits={
      max_nodes: 2,
      max_depth: 0,
      max_text_bytes: 0,
    }),
    Err(CompleteEqualityLimit),
  )
  assert_eq(
    values_equal(array_value, array_value, limits={
      max_nodes: 2,
      max_depth: 1,
      max_text_bytes: 0,
    }).unwrap().0,
    true,
  )
}

///|
test "complete equality splits long text charges and comparison by quantum" {
  let contract = equality_contract("{\"type\":\"string\",\"nullable\":false}")
  let prefix = "x".repeat(512)
  let left = equality_value(contract, "\"" + prefix + "a\"")
  let same = equality_value(contract, "\"" + prefix + "a\"")
  let different = equality_value(contract, "\"" + prefix + "b\"")
  let expected_work = 1 + 3 * 513
  assert_eq(
    values_equal(
      left,
      same,
      limits={ max_nodes: 1, max_depth: 0, max_text_bytes: 1026, },
      quantum=1,
    ),
    Ok((true, expected_work)),
  )
  assert_eq(
    values_equal(
      left,
      different,
      limits={ max_nodes: 1, max_depth: 0, max_text_bytes: 1026, },
      quantum=1,
    ),
    Ok((false, expected_work)),
  )
  assert_eq(
    values_equal(
      left,
      same,
      limits={ max_nodes: 1, max_depth: 0, max_text_bytes: 1025, },
      quantum=1,
    ),
    Err(CompleteEqualityLimit),
  )
  let active = start_complete_equality(left, same, {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 1026,
  }).unwrap()
  for _ in 0..<100 {
    assert_true(
      advance_complete_equality(active, 1) is EqualityContinue(work=1),
    )
  }
}

///|
test "complete equality bounds object names and decimal digits" {
  let name = "field_" + "x".repeat(256)
  let object = equality_contract(
    "{\"type\":\"object\",\"nullable\":false," +
    "\"additional_properties\":false,\"fields\":{\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  let left = equality_value(object, "{\"" + name + "\":1}")
  let right = equality_value(object, "{\"" + name + "\":1}")
  let result = values_equal(left, right, quantum=1).unwrap()
  assert_true(result.0)
  assert_true(result.1 > 256)
  assert_eq(
    values_equal(
      left,
      right,
      limits={ max_nodes: 2, max_depth: 1, max_text_bytes: 523, },
      quantum=1,
    ),
    Err(CompleteEqualityLimit),
  )
  let decimal = equality_contract(
    "{\"type\":\"decimal\",\"nullable\":false," +
    "\"precision\":38,\"scale\":2}",
  )
  let amount = equality_value(
    decimal, "\"123456789012345678901234567890123456.78\"",
  )
  let compared = values_equal(amount, amount, quantum=1).unwrap()
  assert_true(compared.0)
  assert_true(compared.1 > 38)
}

///|
test "complete equality charges supplementary text bytes before comparison" {
  let contract = equality_contract("{\"type\":\"string\",\"nullable\":false}")
  let value = equality_value(contract, "\"\u{1f600}\"")
  assert_eq(
    values_equal(
      value,
      value,
      limits={ max_nodes: 1, max_depth: 0, max_text_bytes: 8, },
      quantum=1,
    ),
    Ok((true, 5)),
  )
  assert_eq(
    values_equal(
      value,
      value,
      limits={ max_nodes: 1, max_depth: 0, max_text_bytes: 7, },
      quantum=1,
    ),
    Err(CompleteEqualityLimit),
  )
}

///|
test "complete equality drops pending frames at a terminal mismatch" {
  let contract = equality_contract(
    "{\"type\":\"array\",\"nullable\":false," +
    "\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  let left = equality_value(contract, "[1,2,3]")
  let right = equality_value(contract, "[0,2,3]")
  let active = start_complete_equality(left, right, {
    max_nodes: 4,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
  assert_true(
    advance_complete_equality(active, 10) is EqualityComplete(equal=false, ..),
  )
  assert_eq(active.frames.length(), 0)
}
