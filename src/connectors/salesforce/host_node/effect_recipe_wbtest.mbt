///|
// Actual provider-to-Core typed composition with the installed metadata/body/
// response ceilings and one concrete Mapping geometry. This executes neither
// a Run nor HTTP/Store/Account, and supplies no physical backing evidence.
test "installed Salesforce native profiles compose directly into the original capture extent" {
  let original = salesforce_effect_construction_profile(
    100000, 10000, 16, 2048, 1024, 100000, 100000, 10000, 16, 4096, 100000, 1000,
    16, 4000000, 400000, 32, 1000, 200000, 8000000, 1024, 100, 6400, 5, 255,
  )
  assert_true(original is Some(_))
  let capture = salesforce_effect_capture_construction_profile(
    original, 1000000, 100000, 64, 4000000, 100000, 32, 2000, 200, 100000, 4000000,
    400000, 32, 1000, 200000, 8000000, 8000000, 10000000, 1024, 100, 6400, 5, 255,
  )
  assert_true(capture is Some(_))
  for targeted in [false, true] {
    let composed = @local.installed_described_effect_recipe_capacities(
      original,
      capture,
      1000000,
      100000,
      64,
      1000000,
      100000,
      64,
      100000,
      100000,
      targeted,
      1048576,
      100000,
      1048576,
      4000000,
      65536,
      7,
      16384,
      1000000,
      512,
      16,
      8000L,
      response_read_quantum=16384,
    ).unwrap()
    assert_eq(composed.length(), 8)
    assert_true(@execution.execution_capacity_retained_bytes(composed[0]) > 0L)
    assert_true(
      @execution.execution_capacity_execution_bytes(composed[4]) >
      @execution.execution_capacity_retained_bytes(composed[4]),
    )
    if targeted {
      assert_true(
        @execution.execution_capacity_execution_bytes(composed[6]) > 0L,
      )
    } else {
      assert_eq(@execution.execution_capacity_execution_bytes(composed[6]), 0L)
    }
    // The original capture constructor consumes exactly its documented six
    // entries. No JS Option/tuple or new operation-demand issuer is involved.
    let selected = Array::makei(6, index => composed[index])
    assert_true(
      @local.prepare_installed_effect_capture_recipe_extent(
        if targeted {
          "salesforce:record:update"
        } else {
          "salesforce:record:create"
        },
        selected,
      )
      is Ok(_),
    )
  }
}
