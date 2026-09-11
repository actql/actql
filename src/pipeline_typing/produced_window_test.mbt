///|
test "producer window roles retain every alias without trusting equal schemas" {
  for reversed in [false, true] {
    let fields = if reversed {
      "[{\"b\":\"window_start\"},{\"a\":\"window_start\"},{\"d\":\"window_end\"},{\"c\":\"window_end\"}]"
    } else {
      "[{\"a\":\"window_start\"},{\"b\":\"window_start\"},{\"c\":\"window_end\"},{\"d\":\"window_end\"}]"
    }
    let producer = @pipeline_typing.check_carriers(
      cursor(
        "[{\"row_window\":{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":3}},{\"select\":" +
        fields +
        "}]",
      ),
      [("rows", window_input())],
      None,
      None,
      limits(),
    ).unwrap()
    let input = @pipeline_typing.produced_input(producer, Step(1)).unwrap()
    let source = cursor(
      "[{\"drop\":[\"a\",\"c\"]},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
    )
    let inputs = [("rows", @pipeline_typing.ProducedInput(input))]
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let roles = @pipeline_typing.window_evidence_at(p, Input(0)).unwrap()
    let (starts, ends) = @pipeline_typing.window_aliases(roles)
    assert_eq(starts.length(), 2)
    assert_eq(ends.length(), 2)
    starts.clear()
    ends.clear()
    assert_eq(@pipeline_typing.window_aliases(roles).0.length(), 2)
    assert_eq(
      @pipeline_typing.window_fields(
        @pipeline_typing.window_evidence_at(p, Step(1)).unwrap(),
      ),
      (Unqualified("b"), Unqualified("d")),
    )
    assert_true(
      physical_equal(
        @pipeline_typing.producer_pipeline(
          @pipeline_typing.input_producer(p, 0).unwrap(),
        ),
        producer,
      ),
    )
    assert_true(@pipeline_typing.window_evidence_at(p, Input(-1)) is None)
    assert_true(@pipeline_typing.window_evidence_at(p, Step(2)) is None)
    let plain = @pipeline_typing.check_carriers(
      source,
      [("rows", @pipeline_typing.carrier_at(producer, Step(1)).unwrap())],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(plain.kind, MissingWindowEvidence)
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_text_bytes: u.text_bytes,
      max_nodes: u.nodes,
      max_tokens: u.tokens,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, {
        ..exact,
        max_work: u.work - 1,
      })
      is Err(_),
    )
  }
}

///|
test "producer window roles are invalidated by boundary overwrite" {
  let producer = @pipeline_typing.check_carriers(
    cursor(
      "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}}]",
    ),
    [("rows", window_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let input = @pipeline_typing.produced_input(producer, Step(0)).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[{\"derive\":[{\"window_start\":{\"literal\":0}}]}]"),
    [("rows", @pipeline_typing.ProducedInput(input))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.window_evidence_at(p, Step(0)) is None)
  let forwarded = @pipeline_typing.produced_input(p, Step(0)).unwrap()
  let error = @pipeline_typing.check_with_evidence(
    cursor("[{\"window_group\":{\"by\":[],\"aggregates\":{}}}]"),
    [("rows", @pipeline_typing.ProducedInput(forwarded))],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(error.kind, MissingWindowEvidence)
}

///|
test "producer Event window roles survive forwarding and the row bridge" {
  let producer = @pipeline_typing.check_carriers(
    cursor(
      "[{\"to_events\":{\"id\":\"value\",\"time\":\"at\"}},{\"window_events\":{\"kind\":\"sliding\",\"size\":10,\"step\":3}}]",
    ),
    [("rows", window_input())],
    None,
    None,
    limits(),
  ).unwrap()
  let mut input = @pipeline_typing.produced_input(producer, Step(1)).unwrap()
  let marked = @pipeline_typing.check_with_evidence(
    cursor("[{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\"}}]"),
    [("events", @pipeline_typing.ProducedInput(input))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.window_evidence_at(marked, Step(0)) is Some(_))
  input = @pipeline_typing.produced_input(marked, Step(0)).unwrap()
  for _ in 0..<2000 {
    let p = @pipeline_typing.check_with_evidence(
      cursor("[]"),
      [("events", @pipeline_typing.ProducedInput(input))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.window_evidence_at(p, Input(0)) is Some(_))
    input = @pipeline_typing.produced_input(p, Input(0)).unwrap()
  }
  let p = @pipeline_typing.check_with_evidence(
    cursor(
      "[{\"events\":true},{\"distinct\":true},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
    ),
    [("events", @pipeline_typing.ProducedInput(input))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.window_fields(
      @pipeline_typing.window_evidence_at(p, Step(2)).unwrap(),
    ),
    (Unqualified("window_start_ms"), Unqualified("window_end_ms")),
  )
}
