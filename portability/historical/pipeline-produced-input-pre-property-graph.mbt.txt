///|
test "producer inputs retain exact counts ownership and repeated operand occurrences" {
  for n in [0, 1, 4] {
    let producer = @pipeline_typing.check_carriers(
      cursor("[" + count_values(n, "rows") + "]"),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    let input = @pipeline_typing.produced_input(producer, Step(0)).unwrap()
    let supplied = [("prior", @pipeline_typing.ProducedInput(input))]
    let source = cursor(
      "[{\"append\":{\"with\":\"prior\"}},{\"take\":{\"count\":2,\"offset\":1}}]",
    )
    let p = @pipeline_typing.check_with_evidence(
      source,
      supplied,
      None,
      None,
      limits(),
    ).unwrap()
    let retained = @pipeline_typing.input_producer(p, 0).unwrap()
    assert_true(physical_equal(retained, input))
    assert_true(
      physical_equal(@pipeline_typing.producer_pipeline(retained), producer),
    )
    assert_eq(@pipeline_typing.producer_target(retained), Step(0))
    let count = @pipeline_typing.row_count(p, Input(0)).unwrap()
    assert_eq(count.upper, n.to_int64())
    assert_true(count.exact)
    assert_count(p, 0, (n * 2).to_int64(), true)
    assert_count(p, 1, if n == 0 { 0L } else if n == 1 { 1L } else { 2L }, true)
    assert_true(@pipeline_typing.graph_count(p, Input(0)) is None)
    assert_true(@pipeline_typing.input_producer(p, -1) is None)
    assert_true(@pipeline_typing.input_producer(p, 1) is None)
    assert_true(@pipeline_typing.produced_input(producer, Step(-1)) is None)
    assert_true(@pipeline_typing.produced_input(producer, Step(1)) is None)
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_text_bytes: u.text_bytes,
      max_nodes: u.nodes,
      max_tokens: u.tokens,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, supplied, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_with_evidence(source, supplied, None, None, {
        ..exact,
        max_work: u.work - 1,
      })
      is Err(_),
    )
  }
}

///|
test "producer Graph counts keep node edge and row quantities separate" {
  for n in [0, 3] {
    let producer = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        graph_count_seed(n) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    let input = @pipeline_typing.produced_input(producer, Step(1)).unwrap()
    let p = @pipeline_typing.check_with_evidence(
      cursor(
        "[{\"union_graphs\":{\"with\":\"g\"},\"as\":\"combined\"},{\"node_rows\":true},{\"edge_rows\":true,\"from\":\"combined\"}]",
      ),
      [("g", @pipeline_typing.ProducedInput(input))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.row_count(p, Input(0)) is None)
    let bound = @pipeline_typing.graph_count(p, Input(0)).unwrap()
    assert_eq(bound.nodes.unwrap().upper, (2 * n).to_int64())
    assert_eq(bound.edges.unwrap().upper, n.to_int64())
    assert_count(p, 1, (4 * n).to_int64(), n == 0)
    assert_count(p, 2, (2 * n).to_int64(), n == 0)
  }
}

///|
test "producer inputs do not fabricate counts from schema or discard key producers" {
  let producer = @pipeline_typing.check(
    cursor("[{\"distinct\":true}]"),
    [("raw", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[{\"derive\":{}}]"),
    [
      (
        "rows",
        @pipeline_typing.ProducedInput(
          @pipeline_typing.produced_input(producer, Step(0)).unwrap(),
        ),
      ),
    ],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.row_count(p, Input(0)) is None)
  assert_true(@pipeline_typing.row_count(p, Step(0)) is None)
  let original = @pipeline_typing.candidate_key(producer, Step(0)).unwrap()
  let retained = @pipeline_typing.candidate_key(p, Input(0)).unwrap()
  assert_true(physical_equal(original, retained))
  assert_eq(@evidence.key_pending(retained), [ValidateKeyProducer])
  // A plain Carrier with the identical type does not inherit a producer count.
  let plain = @pipeline_typing.check_carriers(
    cursor("[]"),
    [("rows", @pipeline_typing.carrier_at(producer, Step(0)).unwrap())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.input_producer(plain, 0) is None)
}

///|
test "producer input forwarding caches counts without recursive traversal" {
  let mut p = @pipeline_typing.check_carriers(
    cursor("[" + count_values(2, "rows") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let mut target = @pipeline_typing.Step(0)
  let source = cursor("[]")
  for _ in 0..<2000 {
    let input = @pipeline_typing.produced_input(p, target).unwrap()
    p = @pipeline_typing.check_with_evidence(
      source,
      [("rows", @pipeline_typing.ProducedInput(input))],
      None,
      None,
      limits(),
    ).unwrap()
    target = @pipeline_typing.Input(0)
  }
  let count = @pipeline_typing.row_count(p, target).unwrap()
  assert_eq(count.upper, 2L)
  assert_true(count.exact)
}
