///|
test "bound operation ranges reject reversed endpoints as input" {
  try {
    ignore(
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        second_stage=true,
        tea=true,
        root_extra="\"params\":{\"n\":{\"type\":\"timestamp\"}},",
        supplied=Some(supplied_fixture("{\"n\":\"2000-01-02T00:00:00.000Z\"}")),
        second_steps="[{\"time_series\":{\"start\":{\"$param\":\"n\"},\"end\":\"2000-01-01T00:00:00.000Z\",\"step\":1},\"as\":\"grid\"},{\"select\":[{\"id\":\"time\"},{\"value\":\"time\"}],\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=2,
      ),
    )
    fail("reversed range produced a checked Program")
  } catch {
    Closure(Operations(Ranges(ReversedRange(_)))) as cause => {
      guard rejected(cause) is Rejected(diagnostic) else {
        fail("known input rejection became a request")
      }
      assert_eq(diagnostic_category(diagnostic), InvalidInput)
      assert_true(
        diagnostic_cause(diagnostic)
        is Closure(Operations(Ranges(ReversedRange(_)))),
      )
      assert_true(diagnostic_location(diagnostic) is None)
    }
    error => raise error
  }
}

///|
test "bound vector query shape violations remain input errors" {
  for query in ["[]", "[1]", "[1,2,3]"] {
    try {
      ignore(
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          through_check=true,
          veca=true,
          root_extra="\"params\":{\"n\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}},",
          supplied=Some(supplied_fixture("{\"n\":" + query + "}")),
          local_schema=Some(
            "{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}",
          ),
          producer_suffix=",{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"score_vectors\":{\"query\":{\"$param\":\"n\"},\"metric\":\"dot\"}}",
          extra_step_budget=2,
        ),
      )
      fail("invalid bound query produced a checked Program")
    } catch {
      Closure(Operations(Queries(InvalidQuery(_) | DimensionMismatch(_, _, _)))) as cause => {
        guard rejected(cause) is Rejected(diagnostic) else {
          fail("known query rejection became a request")
        }
        assert_eq(diagnostic_category(diagnostic), InvalidInput)
        assert_true(diagnostic_location(diagnostic) is None)
      }
      error => raise error
    }
  }
}
