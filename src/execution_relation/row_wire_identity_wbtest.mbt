///|
fn row_wire_limits() -> RowWireLimits {
  {
    max_columns: 100,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
}

///|
test "query receipt and result hashes retain different actual scopes and owners" {
  let (query, owner) = query_sequence_fixture()
  let prepared = prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
  let receipt = admit_query_receipt(
    prepared,
    [
      input_cursor("{\"id\":3}"),
      input_cursor("{\"id\":1}"),
      input_cursor("{\"id\":2}"),
    ],
    3,
    run_limits().input_values,
  ).unwrap()
  let before = identify_query_receipt_rows(receipt, row_wire_limits()).unwrap()
  // Independent SHA-256 of the literal canonical [{id:3},{id:1},{id:2}].
  assert_eq(
    row_wire_cid(before),
    "sha256:77e98e23cd26d76b7d4549460e2d627af92fbdabe8de4cb20c0106d26470d26d",
  )
  assert_eq(row_wire_usage(before), (28, 7, 3))
  let result = execute_query_receipt(prepared, receipt, compute_test_limits()).unwrap()
  let output = completed_output(result, Step(1)).unwrap()
  let after = identify_completed_rows(output, row_wire_limits()).unwrap()
  assert_eq(
    row_wire_cid(after),
    "sha256:b578d4eb7cd3e1c8e66fd5758a9c5a98dc05739e4c6fa282fc372aec70930e18",
  )
  assert_eq(row_wire_usage(after), (19, 5, 2))
  assert_true(row_wire_matches_receipt(before, receipt))
  assert_true(row_wire_matches_output(after, output))
  assert_false(row_wire_matches_receipt(after, receipt))
  assert_false(row_wire_matches_output(before, output))
  let again = execute_query_receipt(prepared, receipt, compute_test_limits()).unwrap()
  let other_output = completed_output(again, Step(1)).unwrap()
  assert_eq(
    row_wire_cid(
      identify_completed_rows(other_output, row_wire_limits()).unwrap(),
    ),
    row_wire_cid(after),
  )
  assert_false(row_wire_matches_output(after, other_output))
  for
    limits in [
      { ..row_wire_limits(), max_bytes: 18, },
      { ..row_wire_limits(), max_nodes: 4, },
      { ..row_wire_limits(), max_depth: 1, },
    ] {
    assert_true(identify_completed_rows(output, limits) is Err(Encoding(_)))
  }
  assert_true(
    identify_completed_rows(output, {
      ..row_wire_limits(),
      max_bytes: 19,
      max_nodes: 5,
      max_depth: 2,
    })
    is Ok(_),
  )
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_columns: 0, })
    is Err(OrderLimit),
  )
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_order_work: 0, })
    is Err(OrderLimit),
  )
  assert_true(
    identify_query_receipt_rows(receipt, {
      ..row_wire_limits(),
      max_order_work: 1,
    })
    is Err(OrderLimit),
  )
  assert_true(
    identify_query_receipt_rows(receipt, {
      ..row_wire_limits(),
      max_order_work: 2,
    })
    is Ok(_),
  )
  assert_true(
    identify_completed_rows(output, { ..row_wire_limits(), max_bytes: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "canonical row hashing reads typed completion without rearranging projection or rows" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true},\"z\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":null,\"z\":3},{\"a\":2,\"z\":1},{\"a\":null,\"z\":3}]},\"as\":\"seed\"},{\"derive\":[{\"a\":\"a + 0\"}]}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [
      ordered_sequence_fragment_context(
        sequence,
        1000L,
        limits=Some({
          max_input_rows: 3L,
          max_value_bytes: 1000L,
          max_live_value_bytes: 10000L,
          max_work: 1000L,
        }),
      ),
    ],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let typed = completed_output(test_typed_completion(generated, 7), Step(1)).unwrap()
  let row = completed_output(
    execute_generated_sequence(generated, [], compute_test_limits()).unwrap(),
    Step(1),
  ).unwrap()
  assert_true(typed.table is NumberTable(_))
  for output in [typed, row] {
    let identity = identify_completed_rows(output, row_wire_limits()).unwrap()
    assert_eq(
      row_wire_cid(identity),
      "sha256:5b1660c31f271e1af59f2233baa91fc7fa9ad754d93182904a134fec76c62e20",
    )
    assert_eq(row_wire_usage(identity), (49, 10, 3))
  }
  let receiver = typed_receiver(owner, "[{\"select\":[\"z\",\"a\"]}]")
  let consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(consumer, [], compute_test_limits(), produced=[
    bind_completed_input(receiver, 0, owner, typed).unwrap(),
  ]).unwrap()
  let output = completed_output(result, Step(0)).unwrap()
  assert_true(output.table is NumberTable(_))
  assert_eq(completed_column_name(output, 0), Some("z"))
  assert_eq(
    row_wire_cid(identify_completed_rows(output, row_wire_limits()).unwrap()),
    "sha256:5b1660c31f271e1af59f2233baa91fc7fa9ad754d93182904a134fec76c62e20",
  )
  assert_eq(completed_column_name(output, 0), Some("z"))
}

///|
test "wire hashing retains zero-column row multiplicity and rejects malformed private layouts" {
  let owner = row_owner("")
  for
    (rows, cid, bytes, nodes) in [
      (
        [],
        "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        2,
        1,
      ),
      (
        [[], [], []],
        "sha256:82e81eff8fdb5188cbadaa4754e41b0adc3108568125a7f65fece0475d932f94",
        10,
        4,
      ),
    ] {
    let table : Table = { owner, id: "empty", names: [], rows, }
    assert_eq(
      hash_row_wire(table, [], row_wire_limits()).unwrap(),
      (cid, bytes, nodes),
    )
  }
  let malformed : Table = { owner, id: "bad", names: ["a", "a"], rows: [], }
  assert_true(
    hash_row_wire(malformed, malformed.names, row_wire_limits())
    is Err(InvalidLayout),
  )
  let malformed : Table = { owner, id: "bad", names: ["a"], rows: [[]], }
  assert_true(
    hash_row_wire(malformed, malformed.names, row_wire_limits())
    is Err(InvalidLayout),
  )
}

///|
test "typed wire uses exact decimals UTF16 keys and opaque nested business data" {
  let table : Table = {
    owner: row_owner(""),
    id: "wire",
    names: ["\u{e000}", "😀", "j", "d"],
    rows: [
      [
        Boolean(false),
        Text("é"),
        logical_literal("{\"a\":[true,null],\"$param\":\"business\"}"),
        decimal_value("1.00", 2),
      ],
    ],
  }
  assert_eq(
    hash_row_wire(table, table.names, row_wire_limits()).unwrap(),
    (
      "sha256:c85c9d378502bcb5ee5d3ff71943a230c7d04ecf42dd7606349f9d4fc6860f13",
      80, 10,
    ),
  )
  assert_eq(table.names, ["\u{e000}", "😀", "j", "d"])
  assert_true(
    hash_row_wire(table, table.names, {
      ..row_wire_limits(),
      max_order_work: 4,
    })
    is Err(OrderLimit),
  )
  assert_true(
    hash_row_wire(table, table.names, { ..row_wire_limits(), max_bytes: 79, })
    is Err(Encoding(_)),
  )
}
