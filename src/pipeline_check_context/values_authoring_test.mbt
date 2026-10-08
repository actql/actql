///|
fn authoring_capacity(
  rows? : Int = 3,
  bytes? : Int = 100,
  depth? : Int = 10,
) -> @environment.Capacity {
  let profile = capacity_profile(false)
    .replace(
      old="\"max_relation_output_rows\":1",
      new="\"max_relation_output_rows\":" + rows.to_string(),
    )
    .replace(
      old="\"max_nested_value_bytes\":1",
      new="\"max_nested_value_bytes\":" + bytes.to_string(),
    )
    .replace(
      old="\"max_nested_value_depth\":1",
      new="\"max_nested_value_depth\":" + depth.to_string(),
    )
  @environment.read_capacity(prepared_environment_fixture(profile), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
}

///|
fn authoring_values_pipeline(
  schema : String,
  rows : String,
) -> @pipeline.CheckedPipeline {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"x\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":" +
      schema +
      ",\"rows\":" +
      rows +
      "},\"as\":\"r\"}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_nodes: 10000,
      max_tokens: 1000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "authoring Values use the existing wire and row selectors without bound cells" {
  let pipeline = authoring_values_pipeline(
    "{\"x\":{\"type\":\"number\",\"nullable\":false}}", "[{\"x\":7},{\"x\":1},{\"x\":7}]",
  )
  let profiles = authoring_profile_proof(pipeline)
  let capacity = authoring_capacity()
  let limits = values_publication_limits()
  let checked = resolve_authoring_values_resources(
    profiles, 0, capacity, limits,
  ).unwrap()
  assert_true(physical_equal(authoring_values_profiles(checked), profiles))
  assert_true(physical_equal(authoring_values_capacity(checked), capacity))
  assert_true(
    physical_equal(
      values_wire_bound_pipeline(
        authoring_values_recursive(checked).rows.wire.bound,
      ),
      pipeline,
    ),
  )
  assert_eq(authoring_values_step(checked), 0)
  assert_true(
    values_wire_bound_cells(authoring_values_recursive(checked).rows.wire.bound)
    is None,
  )
  assert_true(
    values_wire_bound_site(authoring_values_recursive(checked).rows.wire.bound)
    is None,
  )
  assert_eq(authoring_values_recursive(checked).rows.wire.bound.bytes, 25)
  assert_eq(authoring_values_recursive(checked).bytes, 0)
  assert_eq(authoring_values_recursive(checked).type_depth, 0)
  assert_true(authoring_values_recursive_limit(checked) is None)
  // The fixed independent bound fixture has exactly this same /rows payload.
  // Its byte law and wire-limit vectors stay valid without a binding owner.
  assert_eq(
    @wire.cid(
      @wire.program_proof_witness(
        authoring_values_recursive(checked).rows.wire.bound.proof,
      ),
    ),
    "sha256:15622500b68d7891fc269aca0d7cb37561307a912578cd88f3d2dadcc54fb56e",
  )
  assert_eq(
    @wire.limit_cid(authoring_values_recursive(checked).rows.wire.limit),
    "sha256:0e8b43abe5a8df37e7afe6b1dea944021d4db74a9d17fec465fb05c7671b56c2",
  )
  assert_eq(
    @derivation.minimum_value(
      @wire.limit_minimum(authoring_values_recursive(checked).rows.limit),
    ),
    3L,
  )
  let exact : ValuesPublicationLimits = {
    ..limits,
    max_work: authoring_values_work(checked),
    max_payload_bytes: authoring_values_payload_usage(checked).0,
    max_payload_nodes: authoring_values_payload_usage(checked).1,
  }
  assert_true(
    resolve_authoring_values_resources(profiles, 0, capacity, exact) is Ok(_),
  )
  for
    short in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_payload_bytes: exact.max_payload_bytes - 1, },
      { ..exact, max_payload_nodes: exact.max_payload_nodes - 1, },
      { ..exact, max_values: 0, },
      { ..exact, max_work: -1, },
    ] {
    assert_true(
      resolve_authoring_values_resources(profiles, 0, capacity, short) is Err(_),
    )
  }
  let (payload_bytes, payload_nodes) = authoring_values_payload_usage(checked)
  let (metadata_bytes, metadata_nodes) = authoring_values_metadata_usage(
    checked,
  )
  let total : @wire.Limits = {
    max_bytes: payload_bytes + metadata_bytes,
    max_nodes: payload_nodes + metadata_nodes,
    max_depth: 20,
  }
  assert_true(
    resolve_authoring_values_resources(
      profiles,
      0,
      capacity,
      exact,
      total_limits=Some(total),
    )
    is Ok(_),
  )
  for
    short in [
      { ..total, max_bytes: total.max_bytes - 1, },
      { ..total, max_nodes: total.max_nodes - 1, },
    ] {
    assert_true(
      resolve_authoring_values_resources(
        profiles,
        0,
        capacity,
        exact,
        total_limits=Some(short),
      )
      is Err(_),
    )
  }
  assert_true(
    resolve_authoring_values_resources(
      profiles,
      0,
      authoring_capacity(rows=2),
      limits,
    )
    is Err(RowsExceeded(0)),
  )
  for step in [-1, 1] {
    assert_true(
      resolve_authoring_values_resources(profiles, step, capacity, limits)
      is Err(Wire(_, Measurement(InvalidRequirement))),
    )
  }
}

///|
test "authoring Values retain static depth and byte admission instead of deferring raw resources" {
  let schema = "{\"a\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"b\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}}"
  for (rows, bytes) in [("[]", 0), ("[{\"a\":[],\"b\":{\"x\":\"é\"}}]", 12)] {
    let profiles = authoring_profile_proof(
      authoring_values_pipeline(schema, rows),
    )
    let capacity = authoring_capacity(bytes=bytes.max(1), depth=2)
    let checked = resolve_authoring_values_resources(
      profiles,
      0,
      capacity,
      values_publication_limits(),
    ).unwrap()
    assert_eq(
      (
        authoring_values_recursive(checked).bytes,
        authoring_values_recursive(checked).type_depth,
        authoring_values_recursive(checked).selected_fields,
      ),
      (bytes, 2, 2),
    )
    assert_true(authoring_values_recursive_limit(checked) is Some(_))
    assert_true(
      physical_equal(
        @policy.ceiling_policy(authoring_values_recursive(checked).byte_ceiling),
        @environment.capacity_policy(capacity),
      ),
    )
    assert_true(
      resolve_authoring_values_resources(
        profiles,
        0,
        authoring_capacity(depth=1),
        values_publication_limits(),
      )
      is Err(Recursive(0, DepthExceeded)),
    )
    if bytes > 0 {
      assert_true(
        resolve_authoring_values_resources(
          profiles,
          0,
          authoring_capacity(bytes=bytes - 1),
          values_publication_limits(),
        )
        is Err(Recursive(0, BytesExceeded)),
      )
    }
  }
  let parameter = authoring_profile_proof(
    authoring_values_pipeline(
      "{\"x\":{\"type\":\"number\",\"nullable\":false}}", "[{\"x\":{\"$param\":\"x\"}}]",
    ),
  )
  assert_true(
    resolve_authoring_values_resources(
      parameter,
      0,
      authoring_capacity(),
      values_publication_limits(),
    )
    is Err(Wire(0, Measurement(NeedsBinding(0, 0)))),
  )
}
