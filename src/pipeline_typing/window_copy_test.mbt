///|
test "window exact copies preserve value roles across snapshot and prior slots" {
  let prefix = "{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}}"
  for
    body in [
      "{\"a\":\"window_start\",\"z\":\"window_end\"}", "{\"a\":\"window_start\",\"b\":\"window_start\",\"z\":\"window_end\"}",
      "[{\"tmp\":\"window_start\"},{\"window_start\":\"at\"},{\"b\":\"tmp\"},{\"a\":\"b\"},{\"z\":\"window_end\"}]",
      "[{\"window_start\":\"window_start\"},{\"a\":\"window_start\"},{\"z\":\"window_end\"}]",
    ] {
    let source = cursor(
      "[" +
      prefix +
      ",{\"derive\":" +
      body +
      "},{\"select\":[\"a\",\"z\"]},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
    )
    let inputs = [("rows", window_input())]
    let checked = @pipeline_typing.check_carriers(
      source,
      inputs,
      None,
      None,
      limits(),
    )
    assert_true(checked is Ok(_), msg=body)
    let p = checked.unwrap()
    let roles = @pipeline_typing.window_evidence_at(p, Step(2)).unwrap()
    assert_eq(
      @pipeline_typing.window_fields(roles),
      (Unqualified("a"), Unqualified("z")),
    )
    let owned = @pipeline_typing.produced_input(p, Step(2)).unwrap()
    assert_true(
      @pipeline_typing.check_with_evidence(
        cursor("[{\"window_group\":{\"by\":[],\"aggregates\":{}}}]"),
        [("rows", @pipeline_typing.ProducedInput(owned))],
        None,
        None,
        limits(),
      )
      is Ok(_),
    )
    // Identical schema without its producer cannot manufacture window roles.
    assert_true(
      @pipeline_typing.check_carriers(
        cursor("[{\"window_group\":{\"by\":[],\"aggregates\":{}}}]"),
        [("rows", @pipeline_typing.step_at(p, 2).unwrap().output)],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
    let used = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: used.work,
      max_text_bytes: used.text_bytes,
      max_nodes: used.nodes,
      max_tokens: used.tokens,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, {
        ..exact,
        max_work: used.work - 1,
      })
      is Err(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, {
        ..exact,
        max_text_bytes: used.text_bytes - 1,
      })
      is Err(_),
    )
  }
}

///|
test "window roles follow the final value version rather than names or equal arithmetic" {
  for
    body in [
      "{\"a\":\"window_start + 0\",\"z\":\"window_end\"}", "[{\"window_start\":\"at\"},{\"a\":\"window_start\"},{\"z\":\"window_end\"}]",
      "{\"a\":\"window_start\",\"z\":\"window_start\"}",
    ] {
    let result = @pipeline_typing.check_carriers(
      cursor(
        "[{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}},{\"derive\":" +
        body +
        "},{\"select\":[\"a\",\"z\"]},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
      ),
      [("rows", window_input())],
      None,
      None,
      limits(),
    )
    assert_eq(result.unwrap_err().kind, MissingWindowEvidence)
  }
}
