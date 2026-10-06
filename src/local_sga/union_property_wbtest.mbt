///|
fn union_property_test_value(
  contract : @contract.Contract,
  text : String,
) -> @value.CheckedValue {
  let source = @source.parse_json(text, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 1000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  @value.admit(contract, cursor, {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn union_property_test_cursor(
  left : @value.CheckedValue,
  right : @value.CheckedValue?,
  output : @contract.Contract,
  strategy : @graph_type.UnionPropertyStrategy,
  max_items? : Int = 100,
  max_order_bytes? : Int? = None,
) -> UnionProperty {
  start_union_property(
    left,
    right,
    output,
    strategy,
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_items,
    max_order_bytes~,
  ).unwrap()
}

///|
fn union_property_test_finish(
  cursor : UnionProperty,
  quantum : Int,
) -> (@value.CheckedValue, Int) raise {
  let mut total = 0
  for _ in 0..<10000 {
    match advance_union_property(cursor, quantum) {
      PropertyContinue(work) => {
        assert_true(work > 0 && work <= quantum)
        total += work
      }
      PropertyComplete(value, work) => {
        total += work
        return (value, total)
      }
      PropertyFailed(issue, _) =>
        abort("unexpected union property failure: " + @debug.to_string(issue))
    }
  }
  abort("union property exceeded finite fixture steps")
}

///|
fn union_property_test_wire(value : @value.CheckedValue) -> String raise {
  let out = @encode.writer(10000, 1000, 100)
  @value.emit_checked_wire_value(value, out)
  @encode.finish(out)
}

///|
test "union property cancellation retains inputs while a long order key is emitting" {
  let contract = @contract.array_contract(
    @contract.primitive(StringType, nullable=false),
    nullable=false,
  ).unwrap()
  let original = "[\"" + "x".repeat(4096) + "\"]"
  let left = union_property_test_value(contract, original)
  let right = union_property_test_value(contract, "[]")
  let cursor = union_property_test_cursor(
    left,
    Some(right),
    contract,
    @graph_type.UnionSetUnion,
  )
  for _ in 0..<256 {
    if cursor.phase is OrderItem {
      break
    }
    assert_true(advance_union_property(cursor, 1) is PropertyContinue(1))
  } nobreak {
    abort("order phase was not reached")
  }
  // The nested order recheck is node + 64 chunks + terminal = 66; setup
  // plus setup and two emission chunks follows. A synchronous-drain
  // substitution has already left OrderItem at this fixed boundary.
  for _ in 0..<69 {
    assert_true(advance_union_property(cursor, 1) is PropertyContinue(1))
  }
  assert_true(cursor.phase is OrderItem && cursor.order is Some(_))
  assert_true(cursor.items.is_empty() && cursor.candidate_order == "")
  let pending_order = cursor.order.unwrap()
  cleanup_union_property(cursor)
  cleanup_union_property(cursor)
  assert_true(
    cursor.order is None && cursor.items.is_empty() && cursor.terminal,
  )
  assert_true(
    @value.advance_complete_order(pending_order, 1)
    is @value.OrderFailed(_, work=0),
  )
  assert_eq(union_property_test_wire(left), original)
  assert_eq(union_property_test_wire(right), "[]")
  assert_true(
    advance_union_property(cursor, 1) is PropertyFailed(InvalidUnionProperty, 0),
  )
}

///|
test "union property long Text order keeps fixed work and exact temporary bytes across quantums" {
  let contract = @contract.array_contract(
    @contract.primitive(StringType, nullable=false),
    nullable=false,
  ).unwrap()
  let original = "[\"" + "x".repeat(4096) + "\"]"
  let left = union_property_test_value(contract, original)
  let right = union_property_test_value(contract, "[]")
  // Set setup/read 2 + candidate recheck 66 + typed order 132 + no-peer
  // comparison/sort 2 + two input exhaustion transitions 2 + two output
  // transitions 2 + final array recheck 69 = 275 physical steps.
  // The one typed order key is 4096 data bytes + 11 framing bytes = 4107.
  for quantum in [1, 7, 256] {
    let cursor = union_property_test_cursor(
      left,
      Some(right),
      contract,
      @graph_type.UnionSetUnion,
      max_order_bytes=Some(4107),
    )
    let (result, work) = union_property_test_finish(cursor, quantum)
    assert_eq(work, 275)
    assert_eq(union_property_test_wire(result), original)
    let one_short = union_property_test_cursor(
      left,
      Some(right),
      contract,
      @graph_type.UnionSetUnion,
      max_order_bytes=Some(4106),
    )
    for _ in 0..<1000 {
      match advance_union_property(one_short, quantum) {
        PropertyContinue(_) => ()
        PropertyFailed(UnionPropertyOrder(@value.CompleteOrderLimit), _) =>
          break
        _ => abort("one-short long order quota was not refused")
      }
    } nobreak {
      abort("one-short long order did not stop")
    }
    assert_true(one_short.terminal && one_short.order is None)
    assert_true(
      one_short.items.is_empty() && one_short.retained_order_bytes == 0,
    )
    assert_eq(union_property_test_wire(left), original)
  }
}

///|
test "union property applies numeric strategies to equal shared values without occurrence shortcuts" {
  let contract = @contract.primitive(NumberType, nullable=true)
  let two = union_property_test_value(contract, "2")
  for quantum in [1, 64] {
    for
      (strategy, expected) in [
        (@graph_type.UnionNumberSum, "4"),
        (@graph_type.UnionNumberMean, "2"),
        (@graph_type.UnionNumberMax, "2"),
        (@graph_type.UnionNumberMin, "2"),
      ] {
      let (result, work) = union_property_test_finish(
        union_property_test_cursor(two, Some(two), contract, strategy),
        quantum,
      )
      assert_eq(union_property_test_wire(result), expected)
      // Strategy application + scalar recheck + recheck completion.
      assert_eq(work, 3)
    }
    let largest = union_property_test_value(contract, "1.7976931348623157e308")
    let (result, _) = union_property_test_finish(
      union_property_test_cursor(
        largest,
        Some(largest),
        contract,
        @graph_type.UnionNumberMean,
      ),
      quantum,
    )
    guard result.value is @value.Number(number) else {
      abort("number expected")
    }
    assert_eq(number.reinterpret_as_uint64(), 0x7fefffffffffffffUL)
  }
}

///|
test "union property preserves one sided null but rejects null numeric operands overflow and unequal values" {
  let contract = @contract.primitive(NumberType, nullable=true)
  let null = @value.checked_null_value(contract).unwrap()
  let two = union_property_test_value(contract, "2")
  let largest = union_property_test_value(contract, "1.7976931348623157e308")
  let (result, _) = union_property_test_finish(
    union_property_test_cursor(null, None, contract, @graph_type.UnionNumberSum),
    1,
  )
  assert_eq(union_property_test_wire(result), "null")
  for
    cursor in [
      union_property_test_cursor(
        null,
        Some(two),
        contract,
        @graph_type.UnionNumberSum,
      ),
      union_property_test_cursor(
        largest,
        Some(largest),
        contract,
        @graph_type.UnionNumberSum,
      ),
      union_property_test_cursor(
        two,
        Some(largest),
        contract,
        @graph_type.UnionExactEqual,
      ),
    ] {
    for _ in 0..<100 {
      if advance_union_property(cursor, 1) is PropertyFailed(_, work) {
        assert_true(work > 0)
        assert_true(
          cursor.terminal && cursor.items.is_empty() && cursor.recheck is None,
        )
        break
      }
    } nobreak {
      abort("invalid shared value was not refused")
    }
  }
}

///|
test "union property set strategies preserve typed null deduplicate and use canonical order" {
  let item = @contract.primitive(NumberType, nullable=true)
  let contract = @contract.array_contract(item, nullable=true).unwrap()
  let left = union_property_test_value(contract, "[2,null,1,2]")
  let right = union_property_test_value(contract, "[1,3,null,3]")
  for quantum in [1, 64] {
    for
      (strategy, expected) in [
        (@graph_type.UnionSetUnion, "[null,1,2,3]"),
        (@graph_type.UnionSetDifference, "[2]"),
      ] {
      let (result, _) = union_property_test_finish(
        union_property_test_cursor(left, Some(right), contract, strategy),
        quantum,
      )
      assert_eq(union_property_test_wire(result), expected)
    }
  }
}

///|
test "union property temporary limit and cancellation cannot expose a partially merged set" {
  let contract = @contract.array_contract(
    @contract.primitive(NumberType, nullable=false),
    nullable=false,
  ).unwrap()
  let left = union_property_test_value(contract, "[2,1]")
  let right = union_property_test_value(contract, "[3]")
  let limited = union_property_test_cursor(
    left,
    Some(right),
    contract,
    @graph_type.UnionSetUnion,
    max_items=2,
  )
  for _ in 0..<1000 {
    if advance_union_property(limited, 1)
      is PropertyFailed(UnionPropertyLimit, _) {
      assert_true(
        limited.items.is_empty() && limited.array is None && limited.terminal,
      )
      break
    }
  } nobreak {
    abort("set limit was not enforced")
  }
  let cancelled = union_property_test_cursor(
    left,
    Some(right),
    contract,
    @graph_type.UnionSetUnion,
  )
  assert_true(advance_union_property(cancelled, 2) is PropertyContinue(2))
  cleanup_union_property(cancelled)
  assert_true(
    cancelled.items.is_empty() &&
    cancelled.recheck is None &&
    cancelled.order is None,
  )
  assert_true(
    advance_union_property(cancelled, 1)
    is PropertyFailed(InvalidUnionProperty, 0),
  )
}

///|
test "union property meters retained order bytes and bounded candidate keys independently of text values" {
  let contract = @contract.array_contract(
    @contract.primitive(NumberType, nullable=false),
    nullable=false,
  ).unwrap()
  let left = union_property_test_value(contract, "[2,1]")
  let right = union_property_test_value(contract, "[2]")
  // Each independent canonical key is ["number",1] or ["number",2]: twelve
  // UTF-8 bytes. Duplicate equality consumes work but no retained key bytes.
  for quantum in [1, 64] {
    let exact = union_property_test_cursor(
      left,
      Some(right),
      contract,
      @graph_type.UnionSetUnion,
      max_order_bytes=Some(24),
    )
    let (result, _) = union_property_test_finish(exact, quantum)
    assert_eq(union_property_test_wire(result), "[1,2]")
    assert_eq(exact.retained_order_bytes, 0)
    let short = union_property_test_cursor(
      left,
      Some(right),
      contract,
      @graph_type.UnionSetUnion,
      max_order_bytes=Some(23),
    )
    for _ in 0..<1000 {
      if advance_union_property(short, quantum)
        is PropertyFailed(UnionPropertyLimit, work) {
        assert_true(work > 0)
        assert_true(
          short.items.is_empty() &&
          short.order is None &&
          short.retained_order_bytes == 0,
        )
        break
      }
    } nobreak {
      abort("one-short retained order quota did not fail")
    }
    let writer_short = union_property_test_cursor(
      left,
      Some(right),
      contract,
      @graph_type.UnionSetUnion,
      max_order_bytes=Some(11),
    )
    for _ in 0..<1000 {
      if advance_union_property(writer_short, quantum)
        is PropertyFailed(UnionPropertyOrder(_), work) {
        assert_true(work > 0)
        assert_true(writer_short.items.is_empty() && writer_short.order is None)
        break
      }
    } nobreak {
      abort("one-short provisional writer quota did not fail")
    }
  }
}
