///|
fn public_task_contract_limits() -> ModelTaskLimits {
  {
    bodies: { max_bytes: 10000, max_nodes: 1000, max_depth: 32, max_members: 100, },
    contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
    max_work: 100000,
  }
}

///|
fn public_task_contract_cursor(wire : String) -> @decode.Cursor {
  let original = @source.parse_json(wire, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 32,
  }).unwrap()
  @decode.admit(original, {
    max_nodes: 1000,
    max_depth: 32,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
}

///|
test "public Task field map uses original Contract and independent canonical schema identity" {
  let root = public_task_contract_cursor(
    #|{"notes":"string","enabled":"boolean","score":{"type":"number","nullable":true}}
  )
  let admitted = read_public_model_task_contract(root, public_task_contract_limits()).unwrap()
  assert_true(physical_equal(public_model_task_contract_original(admitted), root))
  let expected =
    #|{"additional_properties":false,"fields":{"enabled":{"nullable":false,"type":"boolean"},"notes":{"nullable":false,"type":"string"},"score":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"}
  let (wire, cid) = public_model_task_contract_schema(admitted)
  assert_eq(wire, expected)
  // Independent Node crypto vector, not a product-generated expectation.
  assert_eq(cid, "sha256:c0dbdd42bf076149eee0225b6a218d66a7ee652b838a0cb6970641f3f13df5dc")
  let checked = @value_contract.read_checked(
    public_task_contract_cursor(expected),
    public_task_contract_limits().contracts,
  ).unwrap()
  assert_true(@value_contract.type_equal(
    public_model_task_contract(admitted), checked, 1000,
  ))
}

///|
test "public Task enums preserve order repetitions empty Unicode and separate nullable semantics" {
  let a = read_public_model_task_contract(public_task_contract_cursor(
    #|{"level":{"enum":["low","high","low","😀"],"type":"string"},"empty":{"type":"string","enum":[],"nullable":true}}
  ), public_task_contract_limits()).unwrap()
  let (wire, cid) = public_model_task_contract_schema(a)
  assert_eq(wire,
    #|{"additional_properties":false,"fields":{"empty":{"enum":[],"nullable":true,"type":"string"},"level":{"enum":["low","high","low","😀"],"nullable":false,"type":"string"}},"nullable":false,"type":"object"}
  )
  let b = read_public_model_task_contract(public_task_contract_cursor(
    #|{"level":{"type":"string","enum":["high","low","😀"]},"empty":{"nullable":true,"enum":[],"type":"string"}}
  ), public_task_contract_limits()).unwrap()
  assert_true(cid != public_model_task_contract_schema(b).1)
  assert_false(@value_contract.type_equal(
    public_model_task_contract(a), public_model_task_contract(b), 1000,
  ))
}

///|
test "public Task recursive type positions expand without interpreting enum or field names" {
  let value = read_public_model_task_contract(public_task_contract_cursor(
    #|{"items":{"type":"array","items":{"type":"object","fields":{"type":"string","nullable":{"type":"string","enum":["number","nullable"]},"price":{"type":"decimal","precision":9,"scale":2}}}}}
  ), public_task_contract_limits()).unwrap()
  assert_eq(public_model_task_contract_schema(value).0,
    #|{"additional_properties":false,"fields":{"items":{"items":{"additional_properties":false,"fields":{"nullable":{"enum":["number","nullable"],"nullable":false,"type":"string"},"price":{"nullable":false,"precision":9,"scale":2,"type":"decimal"},"type":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"nullable":false,"type":"array"}},"nullable":false,"type":"object"}
  )
}

///|
test "public Task rejects malformed extra or Parameter-only constraints rather than dropping them" {
  for wire in [
    #|{"v":{"type":"string","enum":null}}
    #|{"v":{"type":"string","enum":["a",1]}}
    #|{"v":{"type":"string","nullable":null}}
    #|{"v":{"type":"string","default":"a"}}
    #|{"v":{"type":"number","integer":true}}
    #|{"v":{"type":"string","min_length":1}}
    #|{"v":{"type":"object","fields":{},"additional_properties":true}}
    #|{"v":{"type":"array","items":null}}
    #|{"v":{"type":"root-invented-type"}}
    #|{"__actql_private":"string"}
  ] {
    assert_true(read_public_model_task_contract(
      public_task_contract_cursor(wire), public_task_contract_limits(),
    ) is Err({kind: InvalidValueContract(_), ..}))
  }
  for wire in ["[]", "null", "{\"v\":null}", "{\"v\":false}"] {
    assert_true(read_public_model_task_contract(
      public_task_contract_cursor(wire), public_task_contract_limits(),
    ) is Err(_))
  }
}

///|
test "public Task aggregate semantic and work budgets include every enum occurrence" {
  let root = public_task_contract_cursor(
    #|{"v":{"type":"string","enum":["a","a","😀"]}}
  )
  let limits = public_task_contract_limits()
  let result = read_public_model_task_contract(root, limits).unwrap()
  let (work, nodes, text) = public_model_task_contract_usage(result)
  assert_true(work > 0 && nodes > 0 && text > 0)
  assert_true(read_public_model_task_contract(root, {
    ..limits, max_work: work,
    contracts: { ..limits.contracts, max_nodes: nodes, max_text_bytes: text, },
  }) is Ok(_))
  assert_true(read_public_model_task_contract(root, {
    ..limits, max_work: work - 1,
  }) is Err({kind: WorkLimit, ..}))
  assert_true(read_public_model_task_contract(root, {
    ..limits, contracts: { ..limits.contracts, max_nodes: nodes - 1, },
  }) is Err({kind: InvalidValueContract(_), ..}))
  assert_true(read_public_model_task_contract(root, {
    ..limits, contracts: { ..limits.contracts, max_text_bytes: text - 1, },
  }) is Err({kind: InvalidValueContract(_), ..}))
}

///|
test "public Task complete fields depth and canonical body are bounded including empty maps" {
  let root = public_task_contract_cursor("{\"v\":\"string\"}")
  let limits = public_task_contract_limits()
  assert_true(read_public_model_task_contract(root, {
    ..limits, bodies: { ..limits.bodies, max_members: 0, },
  }) is Err({kind: TaskLimit, ..}))
  assert_true(read_public_model_task_contract(root, {
    ..limits, bodies: { ..limits.bodies, max_bytes: 10, },
  }) is Err({kind: BodyLimit, ..}))
  assert_true(read_public_model_task_contract(root, {
    ..limits, contracts: { ..limits.contracts, max_depth: 0, },
  }) is Err({kind: InvalidValueContract(_), ..}))
  assert_true(read_public_model_task_contract(root, {
    ..limits, max_work: -1,
  }) is Err({kind: InvalidLimits, ..}))
  let empty = read_public_model_task_contract(public_task_contract_cursor("{}"), limits).unwrap()
  assert_eq(public_model_task_contract_schema(empty).0,
    #|{"additional_properties":false,"fields":{},"nullable":false,"type":"object"}
  )
}
