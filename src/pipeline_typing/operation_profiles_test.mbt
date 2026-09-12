///|
fn assert_operation_profiles(
  p : @pipeline_typing.CheckedPipeline,
  expected : Array[Array[@pipeline_typing.OperationProfile]],
) -> Unit raise {
  assert_eq(@pipeline_typing.step_count(p), expected.length())
  for i in 0..<expected.length() {
    let operation = @pipeline_typing.step_at(p, i).unwrap().operation
    assert_eq(
      @pipeline_typing.operation_profile_count(operation),
      expected[i].length(),
    )
    for j in 0..<expected[i].length() {
      assert_eq(
        @pipeline_typing.operation_profile_at(operation, j),
        Some(expected[i][j]),
      )
      let profile = @pipeline_typing.operation_profile_at(operation, j).unwrap()
      let count = @pipeline_typing.operation_profile_adopted_law_count(profile)
      let expected_count = match expected[i][j] {
        RelA | SGA => 2
        VecA => 1
        TEA | CalendarProfile | TextRankProfile => 0
      }
      assert_eq(count, expected_count)
      for k in 0..<count {
        assert_true(
          @pipeline_typing.operation_profile_adopted_law_at(profile, k)
          is Some(_),
        )
      }
    }
    for j in [-1, expected[i].length(), 2147483647] {
      assert_true(@pipeline_typing.operation_profile_at(operation, j) is None)
    }
  }
}

///|
test "operation profiles distinguish event bridges and relation windows" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"window_events":{"kind":"fixed","size":10}},{"events":true},{"window_group":{"by":[],"aggregates":{}}}]
      ),
    ),
    [("events", event_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_operation_profiles(p, [[TEA], [TEA], [RelA]])
  let rows = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"row_window":{"kind":"fixed","time":"at","size":10}},{"sort":[]},{"drop":[]}]
      ),
    ),
    [("rows", window_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_operation_profiles(rows, [[RelA], [RelA], [RelA]])
}

///|
test "VecA requirements survive relation output without infecting following RelA operations" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"normalize_vectors":true,"as":"v"},{"nearest":{"queries":"v","k":3,"metric":"cosine"}},{"select":["query_id","candidate_id","rank"]}]
      ),
    ),
    [("v0", vector_input())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_operation_profiles(p, [[VecA], [VecA], [RelA]])
}

///|
test "Calendar carries its TEA dependency even with relation outputs" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"calendar_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-02T00:00:00.000Z","unit":"day","timezone":"UTC"},"as":"days"},{"calendar_bucket":{"time":"start","into":"bucket","unit":"month","timezone":"UTC"}}]
      ),
    ),
    [],
    None,
    None,
    limits(),
    calendar_profile=Some(calendar_profile()),
  ).unwrap()
  assert_operation_profiles(p, [[CalendarProfile, TEA], [CalendarProfile, TEA]])
  for
    (profile, id) in [
      (@pipeline_typing.RelA, "actql-rela/0.1"),
      (SGA, "actql-sga/0.1"),
      (TEA, "actql-tea/0.1"),
      (VecA, "actql-veca/0.1"),
      (CalendarProfile, "actql-calendar/0.1"),
      (TextRankProfile, "actql-text-rank/0.1"),
    ] {
    assert_eq(@pipeline_typing.operation_profile_id(profile), id)
  }
}
