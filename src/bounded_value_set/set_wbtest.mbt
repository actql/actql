///|
fn cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(text, {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
}

///|
fn set_value(text : String) -> @value.CheckedValue {
  let item = @contract.primitive(@contract.StringType, nullable=true)
  let contract = @contract.array_contract(
    item,
    nullable=false,
    max_items=Some(20L),
  ).unwrap()
  @value.admit(contract, cursor(text), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
fn finish(execution : Execution) -> @value.CheckedValue raise {
  while true {
    match advance(execution, 1).unwrap() {
      Continue(work~, ..) => assert_true(work > 0L)
      Complete(value, ..) => return value
      Failed(_, ..) => fail("set merge failed")
      Stopped(_, ..) => fail("set merge stopped")
    }
  }
  abort("unreachable")
}

///|
test "bounded set merge orders values and observes cancellation" {
  let left = set_value("[\"b\",\"a\",null,\"a\"]")
  let right = set_value("[\"c\",null,\"b\"]")
  let limits : @value.Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  let union = start(
    @bounded.control(),
    Union,
    left,
    right,
    left.contract,
    limits,
    64,
  ).unwrap()
  let result = finish(union)
  guard result.value is @value.Array(values) else { fail("union array") }
  assert_eq(
    @value.elements(values).map(value => {
      match value {
        @value.Null => "null"
        @value.Text(text) => text
        _ => "unexpected"
      }
    }),
    ["null", "a", "b", "c"],
  )
  assert_true(stopped(union))
  assert_true(cleanup_pending(union))
  assert_eq(cleanup(union), Ok(true))

  let difference = start(
    @bounded.control(),
    Difference,
    left,
    right,
    left.contract,
    limits,
    64,
  ).unwrap()
  guard finish(difference).value is @value.Array(values) else {
    fail("difference array")
  }
  assert_eq(
    @value.elements(values).map(value => {
      match value {
        @value.Text(text) => text
        _ => "unexpected"
      }
    }),
    ["a"],
  )
  assert_eq(cleanup(difference), Ok(true))

  let control = @bounded.control()
  let cancelled = start(control, Union, left, right, left.contract, limits, 64).unwrap()
  assert_true(advance(cancelled, 1).unwrap() is Continue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance(cancelled, 1).unwrap() is Stopped(_))
  assert_eq(cleanup(cancelled), Ok(true))
}

///|
test "bounded set merge admits workspace before execution" {
  let left = set_value("[\"b\",\"a\",null,\"a\"]")
  let right = set_value("[\"c\",null,\"b\"]")
  let limits : @value.Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  assert_true(
    start(@bounded.control(), Union, left, right, left.contract, limits, 63)
    is Err(WorkspaceLimit),
  )
  let exact = start(
    @bounded.control(),
    Union,
    left,
    right,
    left.contract,
    limits,
    64,
  ).unwrap()
  assert_eq(max_noninterruptible_value_nodes(exact), 404)
  assert_eq(max_noninterruptible_value_bytes(exact), 15728)
  assert_eq(cleanup(exact), Err(Execution(@bounded.NotStopped)))
}
