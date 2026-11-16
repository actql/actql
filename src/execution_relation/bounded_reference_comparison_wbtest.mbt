///|
fn reference_pair_cursor() -> BoundedRowComparison {
  {
    left: -1,
    right: -1,
    terms: 0,
    term: 0,
    phase: -1,
    offset: 0,
    charge: { offset: 0, next: 0, remaining: 0, },
    tree: NoRowComparison,
  }
}

///|
fn step_reference_pair(
  cursor : BoundedRowComparison,
  control : ControlBudget,
  left : Value,
  right : Value,
) -> Result[Int?, OrderingIssue] {
  bounded_row_comparison_step_with(
    cursor,
    [{ column: 0, descending: false, nulls_first: false, }],
    control,
    (row, _) => Some(if row == 0 { left } else { right }),
    0,
    1,
    1,
  )
}

///|
fn reference_pair_value(identity : String, live : Ref[Bool]) -> Value {
  capture(
    issued_resource_value(
      select_checked_contract(
        "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
      ),
      identity,
      live,
    ).value,
  )
}

///|
test "bounded reference comparison charges full canonical CID as one scalar operand" {
  let live = Ref(true)
  let left = reference_pair_value(
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", live,
  )
  for
    (identity, expected) in [
      (
        "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        0,
      ),
      (
        "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        -1,
      ),
    ] {
    let right = reference_pair_value(identity, live)
    let cursor = reference_pair_cursor()
    // One comparison plus the two independently fixed 71-byte CID operands.
    let control : ControlBudget = { remaining: 143, max_frames: 1, }
    let mut result = None
    for _ in 0..<5 {
      if result is None {
        result = step_reference_pair(cursor, control, left, right).unwrap()
      }
    }
    assert_eq(result, Some(expected))
    assert_eq(control.remaining, 0)
  }
}

///|
test "bounded reference comparison refuses a one-short CID work budget" {
  let live = Ref(true)
  let value = reference_pair_value(
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", live,
  )
  let cursor = reference_pair_cursor()
  let control : ControlBudget = { remaining: 142, max_frames: 1, }
  let mut result : Result[Int?, OrderingIssue] = Ok(None)
  for _ in 0..<200 {
    if result is Ok(None) {
      result = step_reference_pair(cursor, control, value, value)
    }
  }
  assert_true(result is Err(Limit))
}

///|
test "bounded reference comparison rechecks current at each operand and final comparison" {
  for phase in [1, 2, 3] {
    let live = Ref(true)
    let value = reference_pair_value(
      "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      live,
    )
    let cursor = reference_pair_cursor()
    let control : ControlBudget = { remaining: 1000, max_frames: 1, }
    for _ in 0..<200 {
      if cursor.phase != phase {
        assert_true(
          step_reference_pair(cursor, control, value, value) is Ok(None),
        )
      }
    }
    assert_eq(cursor.phase, phase)
    live.val = false
    assert_true(
      step_reference_pair(cursor, control, value, value)
      is Err(Scalar(InvalidOperand)),
    )
  }
}

///|
test "bounded reference comparison retains independent resource and content domains" {
  let live = Ref(true)
  let resource = reference_pair_value(
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", live,
  )
  let content = capture(
    issued_content_value(
      select_checked_contract(
        "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
      ),
      live,
    ).value,
  )
  let cursor = reference_pair_cursor()
  let control : ControlBudget = { remaining: 143, max_frames: 1, }
  let mut result : Result[Int?, OrderingIssue] = Ok(None)
  for _ in 0..<200 {
    if result is Ok(None) {
      result = step_reference_pair(cursor, control, resource, content)
    }
  }
  assert_true(result is Err(Scalar(ComparisonDomainNotImplemented)))
  assert_eq(control.remaining, 0)
}
