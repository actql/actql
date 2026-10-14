///|
fn resolve_fixture(
  table : Table,
  local_ms : Int64,
  quantum : Int,
) -> (Result[Int64, LocalResolutionIssue], Int) raise {
  let cursor = start_local_resolution(table, local_ms, max_work=100).unwrap()
  let mut total = 0
  for _ in 0..<100 {
    match advance_local_resolution(cursor, quantum).unwrap() {
      ResolutionContinue(work~) => total += work
      ResolutionReady(utc_ms~, work~) => return (Ok(utc_ms), total + work)
      ResolutionFailed(issue, work~) => return (Err(issue), total + work)
    }
  }
  fail("finite original table must terminate")
}

///|
test "local inverse preserves UTC coverage without extrapolation" {
  let table = admit(0L, 10000L, 0, [], max_transitions=0).unwrap()
  assert_eq(resolve_fixture(table, 2000L, 1), (Ok(2000L), 2))
  assert_eq(resolve_fixture(table, -1L, 2), (Err(OutsideResolutionCoverage), 2))
  assert_eq(
    resolve_fixture(table, 10000L, 2),
    (Err(OutsideResolutionCoverage), 2),
  )
}

///|
test "fold chooses the earliest exact occurrence for every quantum" {
  let table = admit(
    0L,
    10000L,
    2,
    [{ at_ms: 5000L, offset_seconds: 0, }],
    max_transitions=1,
  ).unwrap()
  for quantum in [1, 2, 3, 17] {
    assert_eq(resolve_fixture(table, 6000L, quantum), (Ok(4000L), 3))
  }
}

///|
test "gap advances and coincident local boundaries collapse" {
  let table = admit(
    0L,
    10000L,
    0,
    [{ at_ms: 5000L, offset_seconds: 2, }],
    max_transitions=1,
  ).unwrap()
  for local in [5000L, 6000L, 7000L] {
    assert_eq(resolve_fixture(table, local, 1), (Ok(5000L), 3))
  }
  assert_eq(resolve_fixture(table, 8000L, 1), (Ok(6000L), 3))
}

///|
test "backward transition does not imply monotone local conversion" {
  let table = admit(
    0L,
    20000L,
    10,
    [{ at_ms: 5000L, offset_seconds: 0, }],
    max_transitions=1,
  ).unwrap()
  assert_eq(resolve_fixture(table, 6000L, 1), (Ok(6000L), 3))
  assert_eq(resolve_fixture(table, 12000L, 1), (Ok(2000L), 3))
}

///|
test "resolution work is retained and exhausted cursors cannot advance" {
  let table = admit(0L, 10000L, 0, [], max_transitions=0).unwrap()
  let cursor = start_local_resolution(table, 2000L, max_work=1).unwrap()
  assert_eq(advance_local_resolution(cursor, 1), Ok(ResolutionContinue(work=1)))
  assert_eq(
    advance_local_resolution(cursor, 1),
    Ok(ResolutionFailed(ResolutionWorkLimit, work=0)),
  )
  assert_eq(advance_local_resolution(cursor, 1), Err(ResolutionTerminal))
  assert_true(
    start_local_resolution(table, 0L, max_work=-1)
    is Err(InvalidResolutionLimits),
  )
  assert_true(
    start_local_resolution(table, 9223372036854775807L, max_work=1)
    is Err(InvalidLocalInstant),
  )
}

///|
test "skipped civil day boundaries resolve to one UTC instant" {
  let table = admit(
    0L,
    259200000L,
    0,
    [{ at_ms: 86400000L, offset_seconds: 86400, }],
    max_transitions=1,
  ).unwrap()
  assert_eq(resolve_fixture(table, 86400000L, 1), (Ok(86400000L), 3))
  assert_eq(resolve_fixture(table, 172800000L, 8), (Ok(86400000L), 3))
  assert_eq(resolve_fixture(table, 259200000L, 1), (Ok(172800000L), 3))
}

///|
test "original table custody and exact integer offsets survive polls" {
  let transitions = [{ at_ms: 5000L, offset_seconds: 0, }]
  let table = admit(0L, 10000L, 2, transitions, max_transitions=1).unwrap()
  let cursor = start_local_resolution(table, 6000L, max_work=3).unwrap()
  transitions[0] = { at_ms: 3000L, offset_seconds: 3, }
  assert_eq(
    advance_local_resolution(cursor, 3),
    Ok(ResolutionReady(utc_ms=4000L, work=3)),
  )
  assert_eq(advance_local_resolution(cursor, 1), Err(ResolutionTerminal))
  let large = admit(
    9000000000000000L,
    9000000000000100L,
    2147483647,
    [],
    max_transitions=0,
  ).unwrap()
  assert_eq(
    resolve_fixture(large, 9002147483647037L, 1),
    (Ok(9000000000000037L), 2),
  )
}
