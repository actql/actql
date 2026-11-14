///|
// The first and largest packed collection SQL, with no execution or Run store.
// Keep its original Task compiler/owner and the existing issuance metadata
// bounds. An explicit smaller inspection still refuses the complete map.
test "collection original Plan keeps the actual Task owner and metadata bounds" {
  let digits : Array[String] = []
  for n in 0..<10 {
    digits.push("SELECT " + n.to_string() + " AS n")
  }
  for count in [9999, 100000] {
    let sql = "WITH d AS (" +
      digits.join(" UNION ALL ") +
      ") SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < " +
      count.to_string()
    let owner = local_explicit_cast_original(text=sql)
    let limits = client_standard_pure_compilation_limits()
    let tasks = issue_prepared_client_task_compilation(
      owner,
      run_materials_manifests(),
      prepared_client_values_sequence_limits(owner),
      limits.max_facts,
      limits.max_witnesses,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ).unwrap()
    let run = match
      issue_client_task_compiled_run(
        owner,
        tasks,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ) {
      Ok(value) => value
      Err(Policy(Prepared(issue))) =>
        fail("Run issuance Policy.Prepared: " + @debug.to_string(issue))
      Err(Policy(Authorization(issue))) =>
        fail("Run issuance Policy.Authorization: " + @debug.to_string(issue))
      Err(Admission(issue)) =>
        fail("Run issuance Admission: " + @debug.to_string(issue))
      Err(_) => fail("Run issuance refused before Plan projection")
    }
    assert_true(client_compiled_run_matches_tasks(run, owner, tasks))
    assert_eq(
      client_compiled_run_static_plan_view(run, owner, 65536, 4096, 64),
      Err(Projection(Evidence(@publication.RunEvidenceInvalidWire))),
    )
    let wire = client_compiled_run_static_plan_view(
      run, owner, 1000000, 100000, 64,
    ).unwrap()
    assert_true(wire.length() > 65536)
    assert_eq(
      client_task_static_plan_view(owner, tasks, 1000000, 100000, 64),
      Ok(wire),
    )
    let view = parse_plan_identity_value(wire, 1000000, 100000, 64).unwrap()
    let map = @canonical.object_field(view, "logical_map").unwrap()
    let map_wire = @canonical.stringify_value(map, 1000000, 100000, 64)
    let admitted = @publication.admit_run_evidence_value(
      "logical_map", map_wire, 1000000, 100000, 64,
    ).unwrap()
    @publication.check_interactive_logical_map_binding(
      admitted,
      client_compiled_run_plan(run),
      1000000,
      100000,
      64,
    ).unwrap()
    for
      (bytes, nodes, depth) in [
        (65536, 100000, 64),
        (1000000, 1, 64),
        (1000000, 100000, 1),
      ] {
      assert_true(
        client_compiled_run_static_plan_view(run, owner, bytes, nodes, depth)
        is Err(_),
      )
    }
  }
}
