///|
fn mean_property_test_cursor(
  strategy : @graph_type.MeanStrategy,
  output : @contract.Contract,
  samples : Int,
  work? : Int = 100000,
  bits? : Int = 8192,
) -> MeanProperty {
  start_mean_property(
    strategy,
    output,
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 100000, },
    samples,
    work,
    bits,
  ).unwrap()
}

///|
fn mean_property_test_finish(
  cursor : MeanProperty,
  samples : Array[(Double, @value.CheckedValue?)],
  quantum : Int,
) -> Result[(@value.CheckedValue, Int), MeanPropertyIssue] {
  let mut next = 0
  let mut total = 0
  for _ in 0..<100000 {
    match advance_mean_property(cursor, quantum) {
      MeanPropertyNeedsSample(work) => {
        total += work
        guard samples.get(next) is Some((weight, property)) else {
          return Err(InvalidMeanProperty)
        }
        match supply_mean_property_sample(cursor, weight, property) {
          Ok(_) => next += 1
          Err(issue) => return Err(issue)
        }
      }
      MeanPropertyContinue(work) => {
        if work < 1 || work > quantum {
          return Err(InvalidMeanProperty)
        }
        total += work
      }
      MeanPropertyComplete(result, work) => return Ok((result, total + work))
      MeanPropertyFailed(issue, _) => return Err(issue)
    }
  }
  Err(InvalidMeanProperty)
}

///|
test "Mean property preserves the four independent missing and NULL means" {
  let input = @contract.primitive(NumberType, nullable=true)
  let six = union_property_test_value(input, "6")
  let null = union_property_test_value(input, "null")
  let samples = [(1.0, Some(six)), (2.0, Some(null)), (3.0, None)]
  for
    (missing, nulls, expected) in [
      (@graph_type.ExcludeMissing, @graph_type.ExcludeNull, "6"),
      (@graph_type.ExcludeMissing, @graph_type.ZeroNull, "2"),
      (@graph_type.ZeroMissing, @graph_type.ExcludeNull, "1.5"),
      (@graph_type.ZeroMissing, @graph_type.ZeroNull, "1"),
    ] {
    for quantum in [1, 7, 64] {
      let cursor = mean_property_test_cursor(
        @graph_type.WeightedMean(missing, nulls),
        input,
        3,
      )
      let (result, _) = mean_property_test_finish(cursor, samples, quantum).unwrap()
      assert_eq(union_property_test_wire(result), expected)
      assert_true(cursor.phase == MeanPropertyTerminal)
      assert_true(cursor.arithmetic is None && cursor.chosen is None)
    }
  }
}

///|
test "Mean property counts repeated occurrences and ignores zero-weight NULL" {
  let number = @contract.primitive(NumberType, nullable=true)
  let six = union_property_test_value(number, "6")
  let zero = union_property_test_value(number, "0")
  let null = union_property_test_value(number, "null")
  let strategy = @graph_type.WeightedMean(
    @graph_type.ExcludeMissing,
    @graph_type.FailNull,
  )
  for quantum in [1, 7, 64] {
    let cursor = mean_property_test_cursor(strategy, number, 4)
    let (result, _) = mean_property_test_finish(
      cursor,
      [(1.0, Some(six)), (1.0, Some(six)), (1.0, Some(zero)), (0.0, Some(null))],
      quantum,
    ).unwrap()
    assert_eq(union_property_test_wire(result), "4")
  }
  assert_true(
    mean_property_test_finish(
      mean_property_test_cursor(strategy, number, 1),
      [(1.0, Some(null))],
      1,
    )
    is Err(MeanPropertyNull),
  )
  let (result, _) = mean_property_test_finish(
    mean_property_test_cursor(
      @graph_type.WeightedMean(
        @graph_type.ExcludeMissing,
        @graph_type.ExcludeNull,
      ),
      number,
      2,
    ),
    [(1.0, Some(null)), (1.0, None)],
    1,
  ).unwrap()
  assert_eq(union_property_test_wire(result), "null")
}

///|
test "Mean property uses exact products and ties-to-even rather than pairwise means" {
  let number = @contract.primitive(NumberType, nullable=true)
  // Products overflow binary64; the exact mean is nevertheless the largest
  // finite value. The three-sample 0,0,6 mean is 2, not a pairwise fold's 3.
  let largest = union_property_test_value(number, "1.7976931348623157e308")
  let zero = union_property_test_value(number, "0")
  let six = union_property_test_value(number, "6")
  let strategy = @graph_type.WeightedMean(
    @graph_type.ExcludeMissing,
    @graph_type.ExcludeNull,
  )
  for quantum in [1, 7, 64] {
    let (result, _) = mean_property_test_finish(
      mean_property_test_cursor(strategy, number, 2),
      [(2.0, Some(largest)), (2.0, Some(largest))],
      quantum,
    ).unwrap()
    assert_true(
      result.value is @value.Number(value) &&
      value.reinterpret_as_uint64() == 0x7fefffffffffffffUL,
    )
    let (result, _) = mean_property_test_finish(
      mean_property_test_cursor(strategy, number, 3),
      [(1.0, Some(zero)), (1.0, Some(zero)), (1.0, Some(six))],
      quantum,
    ).unwrap()
    assert_eq(union_property_test_wire(result), "2")
  }
}

///|
test "Mean property cumulative control boundary does not reset between samples" {
  let number = @contract.primitive(NumberType, nullable=true)
  let six = union_property_test_value(number, "6")
  let strategy = @graph_type.WeightedMean(
    @graph_type.ExcludeMissing,
    @graph_type.ExcludeNull,
  )
  // Three sample folds, final conversion, one recheck node and its terminal
  // transition. This is the field control budget, not the whole Graph meter
  // or a claim that exact BigInt work/storage is one logical unit.
  for quantum in [1, 7, 64] {
    let (result, work) = mean_property_test_finish(
      mean_property_test_cursor(strategy, number, 3, work=6),
      [(1.0, Some(six)), (1.0, Some(six)), (1.0, Some(six))],
      quantum,
    ).unwrap()
    assert_eq(work, 6)
    assert_eq(union_property_test_wire(result), "6")
    assert_true(
      mean_property_test_finish(
        mean_property_test_cursor(strategy, number, 3, work=5),
        [(1.0, Some(six)), (1.0, Some(six)), (1.0, Some(six))],
        quantum,
      )
      is Err(MeanPropertyWorkLimit),
    )
  }
}

///|
test "Mean exact-equal keeps original Unicode and yields during a long value" {
  let text = @contract.primitive(StringType, nullable=false)
  let composed = union_property_test_value(text, "\"é\"")
  let decomposed = union_property_test_value(text, "\"é\"")
  assert_true(
    mean_property_test_finish(
      mean_property_test_cursor(@graph_type.EqualValues, text, 2),
      [(1.0, Some(composed)), (1.0, Some(decomposed))],
      1,
    )
    is Err(MeanPropertyConflict),
  )
  let wire = "\"" + "x".repeat(4096) + "\""
  let long = union_property_test_value(text, wire)
  let cursor = mean_property_test_cursor(@graph_type.EqualValues, text, 2)
  supply_mean_property_sample(cursor, 1.0, Some(long)).unwrap()
  assert_true(advance_mean_property(cursor, 1) is MeanPropertyContinue(1))
  supply_mean_property_sample(cursor, 1.0, Some(long)).unwrap()
  assert_true(advance_mean_property(cursor, 1) is MeanPropertyContinue(1))
  for _ in 0..<128 {
    assert_true(advance_mean_property(cursor, 1) is MeanPropertyContinue(1))
    assert_true(cursor.phase == CompareMeanValue)
  }
  cleanup_mean_property(cursor)
  cleanup_mean_property(cursor)
  assert_true(
    cursor.chosen is None &&
    cursor.candidate is None &&
    cursor.equality is None &&
    cursor.admission is None,
  )
  assert_true(
    advance_mean_property(cursor, 1)
    is MeanPropertyFailed(InvalidMeanProperty, 0),
  )
  assert_eq(union_property_test_wire(long), wire)
  let (result, _) = mean_property_test_finish(
    mean_property_test_cursor(@graph_type.EqualValues, text, 2),
    [(1.0, Some(long)), (1.0, Some(long))],
    7,
  ).unwrap()
  assert_eq(union_property_test_wire(result), wire)
}
