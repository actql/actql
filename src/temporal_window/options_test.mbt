///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 30000,
    }).unwrap(),
    {
      max_nodes: 100000,
      max_depth: 30000,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
  ).unwrap()
}

///|
fn limits() -> @temporal_window.Limits {
  {
    max_nodes: 100000,
    max_depth: 30000,
    max_work: 100000,
    max_text_bytes: 1000000,
  }
}

///|
test "window milliseconds retain signed offsets and exact duration units" {
  let value = @temporal_window.read_options(
    cursor(
      "{\"kind\":\"sliding\",\"time\":\"at\",\"size\":\"1h\",\"step\":\"15M\",\"offset\":-1}",
    ),
    relation=true,
    None,
    limits(),
  ).unwrap()
  assert_true(@temporal_window.kind(value) is Sliding)
  assert_true(@temporal_window.size(value) is Literal(3600000L))
  assert_true(@temporal_window.step(value) is Some(Literal(900000L)))
  assert_true(@temporal_window.offset(value) is Literal(-1L))
  for suffix in ["", ",\"offset\":0"] {
    let value = @temporal_window.read_options(
      cursor("{\"kind\":\"fixed\",\"size\":1" + suffix + "}"),
      relation=false,
      None,
      limits(),
    ).unwrap()
    assert_true(@temporal_window.offset(value) is Literal(0L))
    assert_true(@temporal_window.time_source(value) is None)
  }
}

///|
test "window options reject malformed and out-of-range values" {
  for
    text in [
      "{}", "{\"kind\":\"sliding\",\"size\":1}", "{\"kind\":\"Fixed\",\"size\":1}",
      "{\"kind\":\"fixed\",\"size\":0}", "{\"kind\":\"fixed\",\"size\":1.5}", "{\"kind\":\"fixed\",\"size\":\"1.5s\"}",
      "{\"kind\":\"fixed\",\"size\":1,\"offset\":9007199254740992}", "{\"kind\":\"fixed\",\"size\":1,\"offset\":\"-1s\"}",
      "{\"kind\":\"fixed\",\"size\":1,\"time\":\"at\"}",
    ] {
    assert_true(
      @temporal_window.read_options(
        cursor(text),
        relation=false,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "window parameter references retain binding domains without reading defaults" {
  let ds = @parameter.read_declarations(
    Some(
      cursor(
        "{\"size\":{\"type\":\"number\",\"default\":-1},\"duration\":{\"type\":\"string\",\"format\":\"duration\"}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let value = @temporal_window.read_options(
    cursor(
      "{\"kind\":\"fixed\",\"size\":{\"$param\":\"size\"},\"offset\":{\"$param\":\"duration\"}}",
    ),
    relation=false,
    Some(ds),
    limits(),
  ).unwrap()
  assert_true(
    @temporal_window.size(value)
    is Parameter("size", duration=false, domain=PositiveMilliseconds),
  )
  assert_true(
    @temporal_window.offset(value)
    is Parameter("duration", duration=true, domain=SignedMilliseconds),
  )
}

///|
test "window source budget endpoints and diagnostic paths" {
  let source = cursor("{\"kind\":\"fixed\",\"size\":1}")
  let value = @temporal_window.read_options(
    source,
    relation=false,
    None,
    limits(),
  ).unwrap()
  let used = @temporal_window.usage(value)
  assert_true(
    @temporal_window.read_options(source, relation=false, None, {
      max_nodes: used.nodes,
      max_depth: 1,
      max_work: used.work,
      max_text_bytes: used.text_bytes,
    })
    is Ok(_),
  )
  assert_true(
    @temporal_window.read_options(source, relation=false, None, {
      max_nodes: used.nodes - 1,
      max_depth: 1,
      max_work: used.work,
      max_text_bytes: used.text_bytes,
    })
    is Err(_),
  )
  let rejected = @temporal_window.read_options(
    cursor("{\"kind\":\"fixed\",\"size\":0}"),
    relation=false,
    None,
    limits(),
  )
  match rejected {
    Err(e) => assert_eq(e.path, [@source.Key("size")])
    Ok(_) => fail("expected rejection")
  }
}
