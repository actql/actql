///|
fn null_response_decode(work : Int, bytes? : Int = 4) -> ModelResponseDecode {
  {
    phase: ParseAnswer(
      @source.start_json_parse(
        "null",
        { max_input_bytes: bytes, max_nodes: 1, max_depth: 1, },
        data_keys=true,
      ).unwrap(),
    ),
    remaining: work,
    limits: {
      request_bytes: 1,
      response_bytes: bytes,
      chunk_bytes: 1,
      chunks: 1,
      header_bytes: 1,
      metadata_bytes: 1,
      metadata_nodes: 1,
      metadata_depth: 1,
      parse_nodes: 1,
      parse_depth: 1,
      parse_work: work,
      adapter_holding_bytes: 6,
      adapter_workspace_bytes: 1,
      active_slots: 1,
      unsettled_slots: 1,
    },
  }
}

///|
test "answer cursor exact independent null work and value boundaries" {
  let output = @contract.string_contract(nullable=true).unwrap()
  let limits : @admitted.Limits = {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 0,
  }
  // Four input scalar scans + end preflight; literal + EOF grammar; one
  // decode node; one typed nullable node. These 5+2+1+1 units are independent
  // of the product's measured cumulative Run work.
  let exact = null_response_decode(9)
  for _ in 0..<8 {
    assert_true(
      advance_model_response_decode(exact, output, limits) is Ok(None),
    )
  }
  guard advance_model_response_decode(exact, output, limits) is Ok(Some(value)) else {
    abort("nine independent child transitions must fit exactly")
  }
  assert_true(value.value is @admitted.Null)
  assert_eq(exact.remaining, 0)
  assert_true(exact.phase is DecodeReclaimed)
  let short = null_response_decode(8)
  for _ in 0..<8 {
    assert_true(
      advance_model_response_decode(short, output, limits) is Ok(None),
    )
  }
  assert_true(
    advance_model_response_decode(short, output, limits) is Err(WorkLimit),
  )
  assert_true(short.phase is DecodeReclaimed)
  let bytes_short = null_response_decode(9, bytes=3)
  for _ in 0..<3 {
    assert_true(
      advance_model_response_decode(bytes_short, output, limits) is Ok(None),
    )
  }
  assert_true(
    advance_model_response_decode(bytes_short, output, limits)
    is Err(OutputValue),
  )
  let nodes_short = null_response_decode(9)
  let no_nodes : @admitted.Limits = { ..limits, max_nodes: 0, }
  for _ in 0..<8 {
    assert_true(
      advance_model_response_decode(nodes_short, output, no_nodes) is Ok(None),
    )
  }
  assert_true(
    advance_model_response_decode(nodes_short, output, no_nodes)
    is Err(OutputValue),
  )
  assert_true(nodes_short.phase is DecodeReclaimed)
}

///|
test "cancelled answer child cursor cannot restart or retain an active parser" {
  let cursor = null_response_decode(9)
  let output = @contract.string_contract(nullable=true).unwrap()
  let limits : @admitted.Limits = {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 0,
  }
  assert_true(advance_model_response_decode(cursor, output, limits) is Ok(None))
  cancel_model_response_decode(cursor)
  cancel_model_response_decode(cursor)
  assert_true(cursor.phase is DecodeReclaimed)
  assert_true(
    advance_model_response_decode(cursor, output, limits) is Err(OutputIdentity),
  )
}
