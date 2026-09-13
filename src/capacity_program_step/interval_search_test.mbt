///|
test "interval search product retains exact imported operands independently of join output" {
  for kind in ["inner", "left", "semi", "anti"] {
    let (left, l) = join_operand(2)
    let (right, r) = join_operand(3)
    let p = join_pipeline(left, right, "interval_join", kind)
    let lb = @capacity_program_step.check_target_rows(p, Input(0), l, 10).unwrap()
    let rb = @capacity_program_step.check_target_rows(p, Input(1), r, 10).unwrap()
    let product = @capacity_program_step.check_interval_search_product(
      p,
      0,
      Some(lb),
      Some(rb),
      3,
    ).unwrap()
    assert_eq(@capacity_program_step.interval_search_upper(product), 6L)
    assert_eq(@capacity_program_step.interval_search_step(product), 0)
    assert_eq(@capacity_program_step.interval_search_work(product), 3)
    assert_true(
      physical_equal(
        @capacity_program_step.interval_search_pipeline(product),
        p,
      ),
    )
    for (index, bound) in [(0, lb), (1, rb)] {
      assert_eq(
        @capacity_program_step.interval_search_input_at(product, index),
        Some(@pipeline.Input(index)),
      )
      assert_true(
        physical_equal(
          @capacity_program_step.interval_search_bound_at(product, index).unwrap(),
          bound,
        ),
      )
    }
    assert_eq(@capacity_program_step.interval_search_input_at(product, 2), None)
    assert_true(
      @capacity_program_step.interval_search_bound_at(product, -1) is None,
    )
    assert_true(
      @capacity_program_step.check_interval_search_product(
        p,
        0,
        Some(lb),
        Some(rb),
        2,
      )
      is Err(WorkLimit),
    )
    assert_true(
      @capacity_program_step.check_interval_search_product(
        p,
        0,
        Some(lb),
        Some(rb),
        -1,
      )
      is Err(InvalidLimits),
    )
    assert_true(
      @capacity_program_step.check_interval_search_product(
        p,
        0,
        Some(rb),
        Some(lb),
        3,
      )
      is Err(ForeignOperand(0)),
    )
    let foreign = join_pipeline(left, right, "interval_join", kind)
    assert_true(
      @capacity_program_step.check_interval_search_product(
        foreign,
        0,
        Some(lb),
        Some(rb),
        3,
      )
      is Err(ForeignOperand(0)),
    )
    assert_true(
      @capacity_program_step.check_interval_search_product(
        p,
        1,
        Some(lb),
        Some(rb),
        3,
      )
      is Err(InvalidOperation),
    )
    assert_true(
      @capacity_program_step.check_interval_search_product(
        p,
        0,
        None,
        Some(rb),
        3,
      )
      is Err(MissingOperandBound),
    )
  }
}

///|
test "interval search product handles empty unknown and overflow without replacing evidence" {
  for
    (l, r, expected) in [
      (0L, 3L, Some(0L)),
      (3L, 0L, Some(0L)),
      (9007199254740991L, 1L, Some(9007199254740991L)),
      (9007199254740991L, 2L, None),
    ] {
    let (left, left_proof) = join_operand(l)
    let (right, right_proof) = join_operand(r)
    // Semi output is bounded by the left input even when the search product
    // overflows. The two quantities must not be interchanged.
    let p = join_pipeline(left, right, "interval_join", "semi")
    let lb = @capacity_program_step.check_target_rows(
      p,
      Input(0),
      left_proof,
      10,
    ).unwrap()
    let rb = @capacity_program_step.check_target_rows(
      p,
      Input(1),
      right_proof,
      10,
    ).unwrap()
    let result = @capacity_program_step.check_interval_search_product(
      p,
      0,
      Some(lb),
      Some(rb),
      3,
    )
    match expected {
      Some(n) =>
        assert_eq(
          @capacity_program_step.interval_search_upper(result.unwrap()),
          n,
        )
      None => assert_true(result is Err(Overflow))
    }
    if l == 0L || r == 0L {
      let zero = @capacity_program_step.check_interval_search_product(
        p,
        0,
        if l == 0L {
          Some(lb)
        } else {
          None
        },
        if r == 0L {
          Some(rb)
        } else {
          None
        },
        3,
      ).unwrap()
      assert_eq(@capacity_program_step.interval_search_upper(zero), 0L)
      assert_true(
        @capacity_program_step.interval_search_bound_at(
          zero,
          if l == 0L {
            1
          } else {
            0
          },
        )
        is None,
      )
      assert_true(
        @capacity_program_step.check_interval_search_product(
          p,
          0,
          Some(lb),
          Some(lb),
          3,
        )
        is Err(ForeignOperand(1)),
      )
    }
  }
}

///|
test "interval search preserves repeated producer roles and rejects other operation families" {
  let (producer, proof) = join_operand(2)
  let p = join_pipeline(producer, producer, "interval_join", "anti")
  let left = @capacity_program_step.check_target_rows(p, Input(0), proof, 10).unwrap()
  let right = @capacity_program_step.check_target_rows(p, Input(1), proof, 10).unwrap()
  let v = @capacity_program_step.check_interval_search_product(
    p,
    0,
    Some(left),
    Some(right),
    3,
  ).unwrap()
  assert_eq(@capacity_program_step.interval_search_upper(v), 4L)
  for i in 0..<2 {
    let bound = @capacity_program_step.interval_search_bound_at(v, i).unwrap()
    assert_true(
      physical_equal(@capacity_program_step.target_rows_bound(bound), proof),
    )
    assert_eq(
      @capacity_program_step.target_rows_target(bound),
      @pipeline.Input(i),
    )
  }
  for family in ["join", "cross_join"] {
    let other = join_pipeline(producer, producer, family, "inner")
    assert_true(
      @capacity_program_step.check_interval_search_product(
        other,
        0,
        None,
        None,
        3,
      )
      is Err(InvalidOperation),
    )
  }
}
