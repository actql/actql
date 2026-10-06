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
