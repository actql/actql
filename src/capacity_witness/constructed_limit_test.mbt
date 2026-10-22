///|
test "typed limit constructor preserves independent prior identities and candidate occurrences" {
  let claims = limit_graph()
  for
    (indices, mode, cid, count) in [
      (
        [0],
        Enforcement::Static,
        "sha256:2ad0db850eeb11db2b6312420de6d985065dd6dcb028d43209726910e27db6df",
        1,
      ),
      (
        [0, 1],
        Enforcement::UnitPreflight,
        "sha256:806e2c34f91793d12507aab0b8a23e0380180f262f69b96fdc8bace65aabcae0",
        2,
      ),
      (
        [2, 0],
        Enforcement::BeforeProviderDispatch,
        "sha256:6a4ebfebbb80ffb92b4ad3ead9779af7416b585914d31fb14b9f954f915b6e68",
        2,
      ),
      (
        [0, 0],
        Enforcement::StreamingAtomic,
        "sha256:d0268b1717560d64d79fe4c1c63ff5de40692438fa7e90fee637bdd3c36ff0f1",
        2,
      ),
    ] {
    let typed = create_limit(
      claims,
      indices,
      @arithmetic.Rows,
      "stage.s.output",
      mode,
      limit_caps(),
    ).unwrap()
    assert_eq(limit_cid(typed), cid)
    assert_true(physical_equal(limit_claims(typed), claims))
    assert_eq(@arithmetic.minimum_candidate_count(limit_minimum(typed)), count)
    let out = @encode.writer(10000, 200, 10)
    emit_limit(typed, out)
    let text = @encode.finish(out)
    let parsed = admit_limit(@utf8.encode(text), cid, claims, limit_caps()).unwrap()
    assert_eq(
      @arithmetic.minimum_value(limit_minimum(typed)),
      @arithmetic.minimum_value(limit_minimum(parsed)),
    )
    assert_eq(
      @arithmetic.minimum_guard_binding(limit_minimum(typed)),
      @arithmetic.minimum_guard_binding(limit_minimum(parsed)),
    )
    let exact = @encode.measuring_writer(10000, 200, 10)
    emit_limit(typed, exact)
    let extent = @encode.finish_measurement_usage(exact)
    assert_eq(measure_limit(typed, extent.0, extent.1, extent.2), extent)
    let usage = limit_creation_usage(typed).unwrap()
    assert_eq(extent.0, usage.0 + 95)
    assert_eq(extent.1, usage.1 + 1)
    for
      caps in [
        (extent.0 - 1, extent.1, extent.2),
        (extent.0, extent.1 - 1, extent.2),
        (extent.0, extent.1, extent.2 - 1),
      ] {
      try measure_limit(typed, caps.0, caps.1, caps.2) catch {
        @encode.OutputLimit => ()
        e => raise e
      } noraise {
        _ => fail("complete typed wire exceeded its output bound")
      }
    }
  }
}

///|
test "typed limit selection refuses wrong original coordinates units ordering and bounds" {
  let claims = limit_graph()
  for indices in [[], [-1], [4], [1, 0], [3]] {
    assert_true(
      create_limit(
        claims,
        indices,
        @arithmetic.Rows,
        "stage.s.output",
        Static,
        limit_caps(),
      )
      is Err(_),
    )
  }
  assert_eq(
    create_limit(claims, [0], @arithmetic.Rows, "", Static, limit_caps()).unwrap_err(),
    InvalidWitness,
  )
  assert_eq(
    create_limit(claims, [0], @arithmetic.Rows, "stage.s.output", Static, {
      ..limit_caps(),
      max_candidates: 0,
    }).unwrap_err(),
    BudgetExceeded,
  )
  let original = [0]
  let value = create_limit(
    claims,
    original,
    @arithmetic.Rows,
    "stage.s.output",
    Static,
    limit_caps(),
  ).unwrap()
  original[0] = 1
  assert_eq(@arithmetic.minimum_value(limit_minimum(value)), 10L)
  assert_eq(
    limit_cid(value),
    "sha256:2ad0db850eeb11db2b6312420de6d985065dd6dcb028d43209726910e27db6df",
  )
  let usage = limit_creation_usage(value).unwrap()
  assert_eq(
    create_limit(claims, [0], @arithmetic.Rows, "stage.s.output", Static, {
      ..limit_caps(),
      max_bytes: usage.0 - 1,
    }).unwrap_err(),
    BudgetExceeded,
  )
}
