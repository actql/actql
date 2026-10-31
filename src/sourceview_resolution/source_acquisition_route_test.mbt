///|
test "original Source route preserves exclusive Query and selects whole input without error fallback" {
  let select = "[{\"select\":[\"id\"],\"as\":\"selected\"}]"
  let filter_select = "[{\"filter\":{\"literal\":true},\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"selected\"}]"
  for
    (steps, result, shared, expected_query) in [
      (select, "selected", false, false),
      ("[]", "remote", false, false),
      (filter_select, "selected", false, true),
      (filter_select, "selected", true, false),
    ] {
    let requests = source_acquisition_fixture(
      steps,
      result,
      "{\"p\":7}",
      branch=shared,
    )
    let original = derive_source_acquisition(requests, 0, 1000000).unwrap()
    match select_source_acquisition_route(requests, 0, 1000000).unwrap() {
      QueryRoute(query) => {
        assert_true(expected_query)
        assert_true(physical_equal(query_acquisition_owner(query), requests))
        assert_eq(query_acquisition_capture(query), @pipeline.Step(1))
      }
      WholeInputRoute(actual) => {
        assert_false(expected_query)
        assert_true(physical_equal(source_acquisition_owner(actual), requests))
        assert_eq(source_acquisition_input(actual), @pipeline.Input(0))
      }
    }
    assert_true(source_acquisition_route(original, 0) is Err(WorkLimit))
    assert_true(source_acquisition_route(original, -1) is Err(InvalidLimits))
    assert_true(
      select_source_acquisition_route(requests, 0, 0)
      is Err(QueryShape(WorkLimit)),
    )
    assert_true(
      select_source_acquisition_route(requests, 0, -1)
      is Err(QueryShape(InvalidLimits)),
    )
  }
}
