///|
fn executable_plan_emission_value(wire : String) -> @canonical.CanonicalValue {
  parse_plan_identity_value(wire, 65536, 8192, 64).unwrap()
}

///|
fn checked_executable_plan_emission(
  parts : ClientExecutablePlanBody[@canonical.CanonicalValue, String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, String), String] {
  Ok(
    finish_client_executable_plan_body(
      parts, max_wire_bytes, max_nodes, max_depth,
    ),
  ) catch {
    _ => Err("Encoding")
  }
}

///|
// Complete prior emission/parse/hash/finalization path, retained as a reference.
fn reference_executable_plan_emission(
  parts : ClientExecutablePlanBody[@canonical.CanonicalValue, String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, String), String] {
  let fact_values = parts.fact_values
  let limit_values = parts.limit_values
  let binding_values = parts.binding_values
  let witness_values = parts.witness_values
  let nodes = parts.nodes
  let edges = parts.edges
  let roots = parts.roots
  let material_value = parts.material_value
  let required_profiles = parts.required_profiles
  let manifest : PlanFactManifestIdentity = {
    wire: "",
    cid: parts.manifest_cid,
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err("Encoding")
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "bound_witnesses")
    client_plan_emit_array(writer, witness_values, @canonical.emit_value)
    @encode.key(writer, "data_edges")
    @canonical.emit_value(edges, writer)
    @encode.key(writer, "execution_material")
    @canonical.emit_value(material_value, writer)
    @encode.key(writer, "limit_bindings")
    client_plan_emit_array(writer, binding_values, @canonical.emit_value)
    @encode.key(writer, "nodes")
    @canonical.emit_value(nodes, writer)
    @encode.key(writer, "plan_fact_manifest_cid")
    @encode.string_value(writer, manifest.cid)
    @encode.key(writer, "plan_facts")
    client_plan_emit_array(writer, fact_values, @canonical.emit_value)
    @encode.key(writer, "required_profiles")
    @encode.begin_array(writer)
    for (profile_id, contract_cid) in required_profiles {
      @encode.begin_object(writer)
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, contract_cid)
      @encode.key(writer, "profile_id")
      @encode.string_value(writer, profile_id)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "resolved_limits")
    client_plan_emit_array(writer, limit_values, @canonical.emit_value)
    @encode.key(writer, "root_refs")
    @canonical.emit_value(roots, writer)
    @encode.key(writer, "source_state_requirements")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-executable-plan/0.1")
    @encode.end_object(writer)
    let raw = @encode.finish(writer)
    guard parse_plan_identity_value(raw, max_wire_bytes, max_nodes, max_depth)
      is Some(body) else {
      return Err("Encoding")
    }
    let cid = @canonical.cid_value(body, max_wire_bytes, max_nodes, max_depth)
    guard @canonical.object_with_string_field(body, "executable_plan_cid", cid)
      is Some(complete) else {
      return Err("Encoding")
    }
    let wire = @canonical.stringify_value(
      complete, max_wire_bytes, max_nodes, max_depth,
    )
    Ok((wire, cid))
  } catch {
    _ => Err("Encoding")
  }
}

///|
fn executable_plan_emission_fixture_0() -> ClientExecutablePlanBody[
  @canonical.CanonicalValue,
  String,
] {
  {
    fact_values: [],
    limit_values: [],
    binding_values: [],
    witness_values: [],
    nodes: executable_plan_emission_value("[]"),
    edges: executable_plan_emission_value("[]"),
    roots: executable_plan_emission_value("[]"),
    material_value: executable_plan_emission_value("{}"),
    manifest_cid: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    required_profiles: [],
  }
}

///|
test "executable Plan emitted identity preserves independent empty bytes and prior reader" {
  let parts = executable_plan_emission_fixture_0()
  let actual = checked_executable_plan_emission(parts, 65536, 8192, 64)
  assert_eq(actual, reference_executable_plan_emission(parts, 65536, 8192, 64))
  let (wire, cid) = actual.unwrap()
  let expected =
    #|{"bound_witnesses":[],"data_edges":[],"executable_plan_cid":"sha256:90d77c241f2466abc9327c998486a36aba02d63dda9aecf86e395c140795437c","execution_material":{},"limit_bindings":[],"nodes":[],"plan_fact_manifest_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","plan_facts":[],"required_profiles":[],"resolved_limits":[],"root_refs":[],"source_state_requirements":[],"version":"actql-executable-plan/0.1"}
  assert_eq(wire, expected)
  assert_eq(
    cid, "sha256:90d77c241f2466abc9327c998486a36aba02d63dda9aecf86e395c140795437c",
  )
  let external = parse_plan_identity_value(wire, 65536, 8192, 64).unwrap()
  assert_eq(@canonical.stringify_value(external, 65536, 8192, 64), wire)
  assert_eq(
    @canonical.cid_value(
      @canonical.object_without_field(external, "executable_plan_cid").unwrap(),
      65536,
      8192,
      64,
    ),
    cid,
  )
}

///|
test "executable Plan complete empty extent retains exact byte node and depth refusals" {
  let parts = executable_plan_emission_fixture_0()
  let bytes = 432
  let nodes = 14
  let depth = 2
  assert_true(
    checked_executable_plan_emission(parts, bytes, nodes, depth) is Ok(_),
  )
  for
    (b, n, d) in [
      (bytes, nodes, depth),
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
      (0, nodes, depth),
    ] {
    assert_eq(
      checked_executable_plan_emission(parts, b, n, d),
      reference_executable_plan_emission(parts, b, n, d),
    )
  }
  assert_true(
    checked_executable_plan_emission(parts, bytes - 1, nodes, depth) is Err(_),
  )
  assert_true(
    checked_executable_plan_emission(parts, bytes, nodes - 1, depth) is Err(_),
  )
  assert_true(
    checked_executable_plan_emission(parts, bytes, nodes, depth - 1) is Err(_),
  )
}

///|
fn executable_plan_emission_fixture_1() -> ClientExecutablePlanBody[
  @canonical.CanonicalValue,
  String,
] {
  {
    fact_values: [executable_plan_emission_value("{\"fact\":\"a\"}")],
    limit_values: [executable_plan_emission_value("{\"count\":1}")],
    binding_values: [executable_plan_emission_value("{\"slot\":0}")],
    witness_values: [executable_plan_emission_value("{\"bytes\":1}")],
    nodes: executable_plan_emission_value(
      "[{\"id\":\"n1\",\"text\":\"\\\"\\\\\\n\"}]",
    ),
    edges: executable_plan_emission_value("[]"),
    roots: executable_plan_emission_value("[\"n1\"]"),
    material_value: executable_plan_emission_value(
      "{\"cell\":{\"a\":null,\"z\":\"é\\r\\n𝄞\"},\"n\":1.25}",
    ),
    manifest_cid: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    required_profiles: [
      (
        "π", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ),
    ],
  }
}

///|
test "executable Plan emitted identity preserves independent mixed Unicode bytes and prior reader" {
  let parts = executable_plan_emission_fixture_1()
  let actual = checked_executable_plan_emission(parts, 65536, 8192, 64)
  assert_eq(actual, reference_executable_plan_emission(parts, 65536, 8192, 64))
  let (wire, cid) = actual.unwrap()
  let expected =
    #|{"bound_witnesses":[{"bytes":1}],"data_edges":[],"executable_plan_cid":"sha256:7ebb55480ef3ed2e3e7c3c99a6c46f25162dfdc45e1bd6c881bc213733bf39cf","execution_material":{"cell":{"a":null,"z":"é\r\n𝄞"},"n":1.25},"limit_bindings":[{"slot":0}],"nodes":[{"id":"n1","text":"\"\\\n"}],"plan_fact_manifest_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","plan_facts":[{"fact":"a"}],"required_profiles":[{"contract_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","profile_id":"π"}],"resolved_limits":[{"count":1}],"root_refs":["n1"],"source_state_requirements":[],"version":"actql-executable-plan/0.1"}
  assert_eq(wire, expected)
  assert_eq(
    cid, "sha256:7ebb55480ef3ed2e3e7c3c99a6c46f25162dfdc45e1bd6c881bc213733bf39cf",
  )
  let external = parse_plan_identity_value(wire, 65536, 8192, 64).unwrap()
  assert_eq(@canonical.stringify_value(external, 65536, 8192, 64), wire)
  assert_eq(
    @canonical.cid_value(
      @canonical.object_without_field(external, "executable_plan_cid").unwrap(),
      65536,
      8192,
      64,
    ),
    cid,
  )
}

///|
test "executable Plan complete mixed extent retains exact byte node and depth refusals" {
  let parts = executable_plan_emission_fixture_1()
  let bytes = 658
  let nodes = 33
  let depth = 3
  assert_true(
    checked_executable_plan_emission(parts, bytes, nodes, depth) is Ok(_),
  )
  for
    (b, n, d) in [
      (bytes, nodes, depth),
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
      (0, nodes, depth),
    ] {
    assert_eq(
      checked_executable_plan_emission(parts, b, n, d),
      reference_executable_plan_emission(parts, b, n, d),
    )
  }
  assert_true(
    checked_executable_plan_emission(parts, bytes - 1, nodes, depth) is Err(_),
  )
  assert_true(
    checked_executable_plan_emission(parts, bytes, nodes - 1, depth) is Err(_),
  )
  assert_true(
    checked_executable_plan_emission(parts, bytes, nodes, depth - 1) is Err(_),
  )
}

///|
fn executable_plan_child_measurement(
  value : @canonical.CanonicalValue,
) -> (Int, Int, Int) raise @encode.EncodeFailure {
  let writer = @encode.measuring_writer(65536, 8192, 64)
  @canonical.emit_value(value, writer)
  @encode.finish_measurement_usage(writer)
}

///|
fn executable_plan_array_measurements(
  values : Array[@canonical.CanonicalValue],
) -> Array[(Int, Int, Int)] raise @encode.EncodeFailure {
  let measurements = []
  for value in values {
    measurements.push(executable_plan_child_measurement(value))
  }
  measurements
}

///|
test "executable Plan construction geometry composes original children without an identity" {
  for
    parts in [
      executable_plan_emission_fixture_0(),
      executable_plan_emission_fixture_1(),
    ] {
    let profiles = []
    for (profile, _) in parts.required_profiles {
      profiles.push((profile, ()))
    }
    let measured : ClientExecutablePlanBody[(Int, Int, Int), Unit] = {
      fact_values: executable_plan_array_measurements(parts.fact_values),
      limit_values: executable_plan_array_measurements(parts.limit_values),
      binding_values: executable_plan_array_measurements(parts.binding_values),
      witness_values: executable_plan_array_measurements(parts.witness_values),
      nodes: executable_plan_child_measurement(parts.nodes),
      edges: executable_plan_child_measurement(parts.edges),
      roots: executable_plan_child_measurement(parts.roots),
      material_value: executable_plan_child_measurement(parts.material_value),
      manifest_cid: (),
      required_profiles: profiles,
    }
    let writer = @encode.measuring_writer(65536, 8192, 64)
    emit_client_executable_plan_body(
      writer,
      measured,
      Some(()),
      (extent, out) => @encode.emit_measurement(out, extent),
      measure_client_fragment_cid,
    )
    let measurement = @encode.finish_measurement_usage(writer)
    let (wire, _) = finish_client_executable_plan_body(parts, 65536, 8192, 64)
    assert_eq(measurement.0, @utf8.encode(wire).length())
    let actual = executable_plan_child_measurement(
      parse_plan_identity_value(wire, 65536, 8192, 64).unwrap(),
    )
    assert_eq(measurement, actual)
    let (bytes, nodes, depth) = measurement
    for
      (b, n, d) in [
        (bytes - 1, nodes, depth),
        (bytes, nodes - 1, depth),
        (bytes, nodes, depth - 1),
      ] {
      let short = @encode.measuring_writer(b, n, d)
      try
        emit_client_executable_plan_body(
          short,
          measured,
          Some(()),
          (extent, out) => @encode.emit_measurement(out, extent),
          measure_client_fragment_cid,
        )
      catch {
        @encode.OutputLimit => ()
        _ => assert_true(false)
      } noraise {
        _ => assert_true(false)
      }
    }
  }
}
