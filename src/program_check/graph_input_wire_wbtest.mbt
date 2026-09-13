///|
test "persistent Graph preflight matches independent node and edge identities" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(budget)
  let selected = units[0].publication_rows[0]
  let context = @context.publication_row_limit_result(selected).context
  let policy = @capacity.application_closure_policy(
    @context.checked_capacity(context),
  )
  let reference = "unit:sha256:" + "0".repeat(64) + "#/inputs/g"
  for
    (measure, expected_limit, expected_witness) in [
      (
        "nodes", "sha256:2d58f1dea7e6164f5b9b6e81dc5a83cb31e0c4381f2ab6028dc00411d208821d",
        "sha256:cf5b42833459da49cc5d3068d3aa1446066b490d71b0c323ed1e4562411b85dd",
      ),
      (
        "edges", "sha256:7eca3cc1679ff8ca7f273fba2dfe9c56269ec6b7886b39149fa201b64ec474d2",
        "sha256:56551001534522ef2e6ad6f25e82f52fa58f711b05ec4f3166922e2e5eed6c6c",
      ),
    ] {
    let host = publication_host(
      @policy.ceiling(policy, "max_graph_input_" + measure).unwrap(),
      budget,
    )
    let writer = identity_writer(budget)
    emit_graph_input_limit(reference, measure, host, writer, None)
    assert_eq(identity_finish(budget, writer), expected_limit)
    let writer = identity_writer(budget)
    emit_graph_input_witness(
      reference,
      measure,
      1000L,
      expected_limit,
      writer,
      None,
    )
    assert_eq(identity_finish(budget, writer), expected_witness)
    let limits : @wire.Limits = {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }
    let host_bytes = publication_metadata(
      w => @host.emit(host, w) catch { e => raise Encoding(e) },
      budget,
    )
    let host_wire = @wire.admit(host_bytes, @host.cid(host), limits).unwrap()
    let bytes = publication_metadata(
      w => {
        emit_graph_input_witness(
          reference,
          measure,
          1000L,
          expected_limit,
          w,
          Some(expected_witness),
        )
      },
      budget,
    )
    let witness = @wire.admit(bytes, expected_witness, limits).unwrap()
    let bytes = publication_metadata(
      w => {
        emit_graph_input_limit(
          reference,
          measure,
          host,
          w,
          Some(expected_limit),
        )
      },
      budget,
    )
    let claims = @wire.check_mixed_claims(
      [host_wire, witness],
      [(bytes, expected_limit)],
      {
        max_entities: 3,
        max_references: 10,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 100,
      },
    ).unwrap()
    assert_eq(@wire.mixed_limit_count(claims), 1)
    assert_true(
      @wire.limit_enforcement(@wire.mixed_limit_at(claims, 0).unwrap())
      is UnitPreflight,
    )
  }
}
