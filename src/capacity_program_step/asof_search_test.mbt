///|
test "asof pair bounds preserve both roles independently of kind and direction" {
  let (left, l) = join_operand(2)
  let (right, r) = join_operand(3)
  for kind in ["left", "inner"] {
    for direction in ["backward", "forward", "nearest"] {
      let p = join_pipeline(left, right, "asof_join", kind, direction~)
      let lb = @capacity_program_step.check_target_rows(p, Input(0), l, 10).unwrap()
      let rb = @capacity_program_step.check_target_rows(p, Input(1), r, 10).unwrap()
      let product = @capacity_program_step.check_asof_search_product(
        p,
        0,
        Some(lb),
        Some(rb),
        3,
      ).unwrap()
      assert_eq(@capacity_program_step.asof_search_upper(product), 6L)
      assert_eq(@capacity_program_step.asof_search_work(product), 3)
      assert_eq(@capacity_program_step.asof_search_step(product), 0)
      assert_true(
        physical_equal(@capacity_program_step.asof_search_pipeline(product), p),
      )
      for (i, b) in [(0, lb), (1, rb)] {
        assert_eq(
          @capacity_program_step.asof_search_input_at(product, i),
          Some(@pipeline.Input(i)),
        )
        assert_true(
          physical_equal(
            @capacity_program_step.asof_search_bound_at(product, i).unwrap(),
            b,
          ),
        )
      }
      assert_true(
        @capacity_program_step.asof_search_bound_at(product, 2) is None,
      )
      assert_eq(@capacity_program_step.asof_search_input_at(product, -1), None)
      for
        (budget, expected) in [
          (-1, @capacity_program_step.AsOfSearchIssue::InvalidLimits),
          (2, @capacity_program_step.AsOfSearchIssue::WorkLimit),
        ] {
        assert_eq(
          @capacity_program_step.check_asof_search_product(
            p,
            0,
            Some(lb),
            Some(rb),
            budget,
          ).unwrap_err(),
          expected,
        )
      }
      assert_true(
        @capacity_program_step.check_asof_search_product(
          p,
          1,
          Some(lb),
          Some(rb),
          3,
        )
        is Err(InvalidOperation),
      )
      assert_true(
        @capacity_program_step.check_asof_search_product(
          p,
          0,
          Some(rb),
          Some(lb),
          3,
        )
        is Err(ForeignOperand(0)),
      )
      let foreign = join_pipeline(left, right, "asof_join", kind, direction~)
      assert_true(
        @capacity_program_step.check_asof_search_product(
          foreign,
          0,
          Some(lb),
          Some(rb),
          3,
        )
        is Err(ForeignOperand(0)),
      )
      assert_true(
        @capacity_program_step.check_asof_search_product(
          p,
          0,
          None,
          Some(rb),
          3,
        )
        is Err(MissingOperandBound),
      )
      // A numeric product does not permit substituting a different operation's contract.
      assert_true(
        @capacity_program_step.check_interval_search_product(
          p,
          0,
          Some(lb),
          Some(rb),
          3,
        )
        is Err(InvalidOperation),
      )
    }
  }
}

///|
test "asof pair bounds validate zero shortcuts repeated producers and overflow" {
  for
    (l, r, expected) in [
      (0L, 3L, Some(0L)),
      (3L, 0L, Some(0L)),
      (9007199254740991L, 1L, Some(9007199254740991L)),
      (9007199254740991L, 2L, None),
    ] {
    let (left, lp) = join_operand(l)
    let (right, rp) = join_operand(r)
    let p = join_pipeline(left, right, "asof_join", "left")
    let lb = @capacity_program_step.check_target_rows(p, Input(0), lp, 10).unwrap()
    let rb = @capacity_program_step.check_target_rows(p, Input(1), rp, 10).unwrap()
    let result = @capacity_program_step.check_asof_search_product(
      p,
      0,
      Some(lb),
      Some(rb),
      3,
    )
    match expected {
      Some(n) =>
        assert_eq(@capacity_program_step.asof_search_upper(result.unwrap()), n)
      None => assert_true(result is Err(Overflow))
    }
    if l == 0L || r == 0L {
      let zero = @capacity_program_step.check_asof_search_product(
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
      assert_eq(@capacity_program_step.asof_search_upper(zero), 0L)
      assert_true(
        @capacity_program_step.check_asof_search_product(
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
  let (producer, proof) = join_operand(2)
  let p = join_pipeline(producer, producer, "asof_join", "inner")
  let lb = @capacity_program_step.check_target_rows(p, Input(0), proof, 10).unwrap()
  let rb = @capacity_program_step.check_target_rows(p, Input(1), proof, 10).unwrap()
  let product = @capacity_program_step.check_asof_search_product(
    p,
    0,
    Some(lb),
    Some(rb),
    3,
  ).unwrap()
  assert_eq(@capacity_program_step.asof_search_upper(product), 4L)
  for i in 0..<2 {
    let b = @capacity_program_step.asof_search_bound_at(product, i).unwrap()
    assert_true(
      physical_equal(@capacity_program_step.target_rows_bound(b), proof),
    )
    assert_eq(@capacity_program_step.target_rows_target(b), @pipeline.Input(i))
  }
  for family in ["join", "interval_join", "cross_join"] {
    let other = join_pipeline(producer, producer, family, "inner")
    assert_true(
      @capacity_program_step.check_asof_search_product(other, 0, None, None, 3)
      is Err(InvalidOperation),
    )
  }
}
