///|
test "owned construction links window count limits but does not waive publication resources" {
  for
    kind in [
      "\"kind\":\"fixed\",\"size\":10", "\"kind\":\"sliding\",\"size\":10,\"step\":3",
    ] {
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        tea=true,
        second_steps="[{\"row_window\":{\"time\":\"id\"," +
          kind +
          "},\"as\":\"selected\"}]",
        second_result_from="selected",
      )
    catch {
      Closure(UnresolvedOperation(site)) => {
        assert_eq(site.stage, 1)
        assert_eq(site.step, 0)
        guard site.requirement
          is @pipeline.WindowRequirement(ResolvePublicationResources) else {
          fail(
            "window membership was not resolved, or a different requirement failed",
          )
        }
      }
      error => raise error
    } noraise {
      _ => fail("window publication resources were silently discharged")
    }
  }
}
