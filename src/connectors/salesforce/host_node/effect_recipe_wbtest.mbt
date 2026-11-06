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

///|
test "Salesforce staged metadata and warm capture keep maxima as bounds until original input exists" {
  let original = salesforce_effect_construction_profile(
    100000, 10000, 16, 2048, 1024, 100000, 100000, 10000, 16, 4096, 100000, 1000,
    16, 4000000, 400000, 32, 1000, 200000, 8000000, 1024, 3, 22, 5, 15,
  )
  let profile = bytes => {
    salesforce_effect_metadata_input_construction_profile(
      original, 4000000, 400000, 32, 1000, 200000, 8000000, 1024, 15, bytes,
    )
  }
  let capture = bytes => {
    salesforce_effect_input_capture_construction_profile(
      original, 1000000, 100000, 64, 4000000, 100000, 32, 2000, 200, 100000, 4000000,
      400000, 32, 1000, 200000, 8000000, 8000000, 10000000, 1024, 3, 22, 5, 15, bytes,
    )
  }
  let compose = (profile, capture) => {
    @local.installed_described_effect_recipe_capacities(
      profile,
      capture,
      1000000,
      100000,
      64,
      1000000,
      100000,
      64,
      100000,
      100000,
      true,
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
      metadata_on_child=true,
      control_wire_bytes=Some(
        @local.installed_effect_control_wire_bound(100000, 1000000).unwrap(),
      ),
    ).unwrap()
  }
  let target = bytes => {
    salesforce_effect_target_input_construction_profile(
      profile(0),
      100000,
      10000,
      16,
      4096,
      3,
      bytes,
    )
  }
  let initial = compose(target(0), capture(0))
  let response = compose(profile(2048), capture(0))
  let target_response = compose(target(2048), capture(0))
  assert_true(
    @execution.execution_capacity_execution_bytes(target_response[6]) >
    @execution.execution_capacity_execution_bytes(initial[6]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(target_response[6]) <
    @execution.execution_capacity_execution_bytes(
      compose(original, capture(0))[6],
    ),
  )
  assert_true(target(100001) is None)
  let recovered = compose(profile(0), capture(8192))
  let maximum = compose(original, capture(-1))
  // Actual two-row caller geometry, not the configured1000-field ceiling.
  let retention = @execution.execution_capacity_retained_bytes(initial[0]) +
    2L * @execution.execution_capacity_retained_bytes(initial[1]) +
    3L * @execution.execution_capacity_retained_bytes(initial[7])
  assert_true(retention < 536870912L)
  for index in [0, 1, 7] {
    assert_true(
      @execution.execution_capacity_retained_bytes(initial[index]) <=
      @execution.execution_capacity_retained_bytes(maximum[index]),
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(initial[index]) <=
      @execution.execution_capacity_execution_bytes(maximum[index]),
    )
  }
  assert_true(
    @execution.execution_capacity_execution_bytes(response[7]) >
    @execution.execution_capacity_execution_bytes(initial[7]),
  )
  // Cold reconstruction still owns a complete private phase. Its peak need
  // not exceed a warm profile's full generated capability-writer envelope;
  // the later Preview constructor does not overlap completed Catalog work.
  assert_true(
    @execution.execution_capacity_execution_bytes(recovered[0]) >
    @execution.execution_capacity_retained_bytes(recovered[0]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(recovered[0]) <=
    @execution.execution_capacity_execution_bytes(maximum[0]),
  )
  // The typed native profile changes only metadata. Logical decode limits
  // still belong to the actual original caller, not this quantity.
  let before = original.unwrap()
  let after = profile(2048).unwrap()
  for index in 0..<3 {
    assert_true(physical_equal(before[index].0, after[index].0))
  }
  assert_eq(before[3].2, after[3].2)
  assert_true(profile(4000001) is None)
  assert_true(capture(-2) is None)
}

///|
test "Salesforce warm capture does not reconstruct its already-owned row requests" {
  let original = salesforce_effect_construction_profile(
    100000, 10000, 16, 2048, 1024, 100000, 100000, 10000, 16, 4096, 100000, 1000,
    16, 4000000, 400000, 32, 1000, 200000, 8000000, 1024, 3, 22, 5, 15,
  )
  let entries = original.unwrap()
  let larger = entries.copy()
  let (request, input, output) = entries[0]
  larger[0] = (
    @execution.add_execution_capacity(
      request,
      @execution.execution_capacity(64L, 128L).unwrap(),
    ).unwrap(),
    input,
    output,
  )
  let capture = salesforce_effect_input_capture_construction_profile(
    original, 1000000, 100000, 64, 4000000, 100000, 32, 2000, 200, 100000, 4000000,
    400000, 32, 1000, 200000, 8000000, 8000000, 10000000, 1024, 3, 22, 5, 15, 0,
  )
  let compose = (profile, host_input_bytes) => {
    @local.installed_described_effect_recipe_capacities(
      profile,
      capture,
      1000000,
      100000,
      64,
      1000000,
      100000,
      64,
      100000,
      100000,
      true,
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
      metadata_on_child=true,
      control_wire_bytes=Some(
        @local.installed_effect_control_wire_bound(100000, 1000000).unwrap(),
      ),
      host_input_bytes=if host_input_bytes < 0 {
        None
      } else {
        Some(host_input_bytes)
      },
    ).unwrap()
  }
  let warm = compose(original, 0)
  let larger_warm = compose(Some(larger), 0)
  // The row constructor owns the change before capture; capture only borrows
  // those SAME requests. Its retained material cannot grow a second copy.
  assert_eq(
    @execution.execution_capacity_retained_bytes(warm[1]),
    @execution.execution_capacity_retained_bytes(larger_warm[1]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(warm[1]),
    @execution.execution_capacity_execution_bytes(larger_warm[1]),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(larger_warm[2]) >
    @execution.execution_capacity_retained_bytes(warm[2]),
  )
  // Authenticated cold input still reconstructs requests inside its capture
  // child. Its original extent must retain the complete constructor instead.
  let cold = compose(original, 8192)
  let larger_cold = compose(Some(larger), 8192)
  assert_true(
    @execution.execution_capacity_retained_bytes(larger_cold[1]) >
    @execution.execution_capacity_retained_bytes(cold[1]),
  )
  let maximum = compose(Some(larger), -1)
  assert_true(
    @execution.execution_capacity_retained_bytes(maximum[1]) >=
    @execution.execution_capacity_retained_bytes(larger_cold[1]),
  )
}

///|
test "Salesforce cold capture bounds nested observation and saved wire by the original input" {
  let original = salesforce_effect_construction_profile(
    100000, 10000, 16, 2048, 1024, 100000, 100000, 10000, 16, 4096, 100000, 1000,
    16, 4000000, 400000, 32, 1000, 200000, 8000000, 1024, 3, 22, 5, 15,
  )
  let capture = (observation_bytes, describe_bytes, input_bytes) => {
    salesforce_effect_input_capture_construction_profile(
      original, 1000000, 100000, 64, 4000000, 100000, 32, 2000, 200, 100000, describe_bytes,
      400000, 32, 1000, 200000, observation_bytes, 8000000, 10000000, 1024, 3, 22,
      5, 15, input_bytes,
    )
  }
  let cold = capture(8000000, 4000000, 8192).unwrap()
  let larger_limits = capture(16000000, 8000000, 8192).unwrap()
  let larger_input = capture(8000000, 4000000, 16384).unwrap()
  let maximum = capture(8000000, 4000000, -1).unwrap()
  let larger_maximum = capture(16000000, 8000000, -1).unwrap()
  for index in 0..<3 {
    assert_eq(
      @execution.execution_capacity_retained_bytes(cold[index]),
      @execution.execution_capacity_retained_bytes(larger_limits[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(cold[index]),
      @execution.execution_capacity_execution_bytes(larger_limits[index]),
    )
  }
  assert_true(
    @execution.execution_capacity_retained_bytes(larger_input[0]) >
    @execution.execution_capacity_retained_bytes(cold[0]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(larger_input[0]) >
    @execution.execution_capacity_execution_bytes(cold[0]),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(larger_maximum[0]) >
    @execution.execution_capacity_retained_bytes(maximum[0]),
  )
  assert_true(capture(0, 4000000, 8192) is None)
  assert_true(capture(8000000, 0, 8192) is None)
}

///|
fn current_metadata_profile_fixture() -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  salesforce_effect_construction_profile(
    100000, 10000, 16, 2048, 1024, 100000, 100000, 10000, 16, 4096, 100000, 1000,
    16, 4000000, 400000, 32, 1000, 200000, 8000000, 306, 3, 22, 5, 14,
  )
}

///|
test "current Effect metadata uses original Source geometry within the unchanged normal parent" {
  let original = current_metadata_profile_fixture()
  let body = @utf8.encode(
    "{\"name\":\"Account\",\"queryable\":true,\"description\":\"" +
    "a".repeat(250000) +
    "\",\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false}]}",
  )
  let legacy = salesforce_effect_metadata_input_construction_profile(
      original,
      4000000,
      400000,
      32,
      1000,
      200000,
      8000000,
      306,
      14,
      body.length(),
    ).unwrap()[3].0
  let current = salesforce_effect_current_metadata_construction_profile(
      original, 4000000, 400000, 32, 1000, 200000, 8000000, 306, 14, body,
    ).unwrap()[3].0
  assert_eq(
    @execution.execution_capacity_retained_bytes(current),
    @execution.execution_capacity_retained_bytes(legacy),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(legacy) > 536870912L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(current) < 536870912L,
  )
  let initial = salesforce_effect_metadata_input_construction_profile(
      original, 4000000, 400000, 32, 1000, 200000, 8000000, 306, 14, 0,
    ).unwrap()[3].0
  // This SAME initial occurrence funds a full bounded decoded Source String
  // before the current-body quantity callback, not after its construction.
  let controls = @source.json_source_preflight_control_extent()
  let preflight = @execution.preparation_execution_capacity({
    retained: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: controls.record_headers + 4L,
      reference_slots: controls.reference_slots + 10L,
      scalar_words: controls.scalar_words + 4L,
      owned_utf16_units: 4000000L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  }).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(initial) >=
    @execution.execution_capacity_retained_bytes(initial) +
    @execution.execution_capacity_execution_bytes(preflight),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(initial) <=
    @execution.execution_capacity_execution_bytes(current),
  )
}

///|
test "current Effect metadata preserves original parser refusal and lexical fallback" {
  let original = current_metadata_profile_fixture()
  let body = @utf8.encode("{\"description\":\"" + "a".repeat(250000) + "\"}")
  let before = @utf8.encode("{\"description\":\"" + "a".repeat(250000) + "\"}")
  for nodes in [1, 400000] {
    let current = salesforce_effect_current_metadata_construction_profile(
        original, 4000000, nodes, 32, 1000, 200000, 8000000, 306, 14, body,
      ).unwrap()[3].0
    let legacy = salesforce_effect_metadata_input_construction_profile(
        original,
        4000000,
        nodes,
        32,
        1000,
        200000,
        8000000,
        306,
        14,
        body.length(),
      ).unwrap()[3].0
    assert_eq(
      @execution.execution_capacity_retained_bytes(current),
      @execution.execution_capacity_retained_bytes(legacy),
    )
    if nodes == 1 {
      assert_eq(
        @execution.execution_capacity_execution_bytes(current),
        @execution.execution_capacity_execution_bytes(legacy),
      )
    }
  }
  assert_eq(body, before)
  // No Describe name/queryable/fields were supplied. Quantity does not admit
  // that grammar: the original metadata consumer still rejects it.
  assert_true(
    @catalog.project_describe(body, "Account", {
      max_bytes: 4000000,
      max_nodes: 400000,
      max_depth: 32,
      max_fields: 1000,
      max_name_units: 200000,
    })
    is Err(_),
  )
}
