///|
test "stepped numeric members preserve independent values and work" {
  let profile = builtin_profile()
  for member_index in 0..<2 {
    let reduction = select(
      profile,
      member_cid_at(profile, member_index).unwrap(),
    ).unwrap()
    for operation in [Sum, Average] {
      let expected_work = (if member_index == 0 { 8 } else { 7 }) +
        (if operation is Average { 1 } else { 0 })
      for allowance in [expected_work - 1, expected_work] {
        let state = start_reduction(
          reduction,
          operation,
          [10000000000000000.0, 1.0, -10000000000000000.0, 1.0],
          4,
          allowance,
        ).unwrap()
        let mut terminal = false
        for _ in 0..<40 {
          if !terminal {
            let before = state.work
            match advance_reduction(state) {
              Ok(None) => ()
              Err(WorkLimit) => {
                assert_eq(allowance, expected_work - 1)
                terminal = true
              }
              Ok(Some(outcome)) => {
                assert_eq(allowance, expected_work)
                assert_eq(outcome_work(outcome), expected_work)
                assert_eq(
                  outcome_value(outcome),
                  Some(
                    if member_index == 1 {
                      0.0
                    } else if operation is Average {
                      0.25
                    } else {
                      1.0
                    },
                  ),
                )
                terminal = true
              }
              Err(_) => fail("unexpected numeric failure")
            }
            assert_true(state.work - before <= 1)
          }
        }
        assert_true(terminal)
        assert_eq(state.current.length(), 0)
        assert_eq(state.next.length(), 0)
      }
    }
  }
}

///|
test "stepped numeric cleanup preserves borrowed contributors and work" {
  let profile = builtin_profile()
  let reduction = select(profile, member_cid_at(profile, 1).unwrap()).unwrap()
  let contributors = [1.0, 2.0, 3.0, 4.0]
  for target in [0, 2, 3, 4] {
    let state = start_reduction(reduction, Average, contributors, 4, 20).unwrap()
    let mut reached = false
    for _ in 0..<40 {
      if !reached {
        reached = state.phase == target
        if !reached {
          assert_true(advance_reduction(state) is Ok(None))
        }
      }
    }
    assert_true(reached)
    let work = state.work
    close_reduction(state)
    close_reduction(state)
    assert_eq(state.work, work)
    assert_eq(state.current.length(), 0)
    assert_eq(state.next.length(), 0)
    assert_eq(contributors, [1.0, 2.0, 3.0, 4.0])
    assert_true(advance_reduction(state) is Err(InvalidLimits))
  }
}

///|
test "stepped numeric admission precedes arithmetic failure" {
  let profile = builtin_profile()
  let reduction = select(profile, member_cid_at(profile, 0).unwrap()).unwrap()
  let state = start_reduction(
    reduction,
    Sum,
    [1.7976931348623157e308, 1.7976931348623157e308, 1.0 / 0.0],
    3,
    10,
  ).unwrap()
  assert_true(advance_reduction(state) is Ok(None))
  assert_true(advance_reduction(state) is Ok(None))
  assert_true(advance_reduction(state) is Err(NonfiniteContributor(2)))
  assert_eq(state.work, 3)
}
