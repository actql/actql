///|
// Synthetic Unit identities isolate canonical conversion from Unit admission.
test "shortest limit conversion matches independent guarded preimages and aggregate boundaries" {
  for
    (unit_cid, guard_value, paths_cid, output_cid) in [
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        None,
        "sha256:8847fc22b481078f624402a63f851c6236ca8565a3e73279e87756d255b95157",
        "sha256:16b0d0f2101ded44b0549595040dd825ca95030e84725d432569d41622ce0a07",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        Some(1),
        "sha256:8847fc22b481078f624402a63f851c6236ca8565a3e73279e87756d255b95157",
        "sha256:e7d6afc8ac653c078ab7e6215cba3d88ecc6ec570d3ea54c28ecdcb4a2a3663c",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        Some(1000),
        "sha256:8847fc22b481078f624402a63f851c6236ca8565a3e73279e87756d255b95157",
        "sha256:e8c0143a44c57946e666923899c161be6f671528bb4e5670b4a33ba4f73b0a95",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        Some(2000),
        "sha256:8847fc22b481078f624402a63f851c6236ca8565a3e73279e87756d255b95157",
        "sha256:c086e012d7f9f45302075f80a760e7ec6e3e8edbcfbf37aef5561d7b95bb59db",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        None,
        "sha256:adfaeabc18900a39d65cb0d288cd35e8f4aa6c472b7557a51526023fdc82296c",
        "sha256:67c29b9767fbeaa545a037f5bd136c27353d2548093bfa73a233284031f2aef6",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        Some(1),
        "sha256:adfaeabc18900a39d65cb0d288cd35e8f4aa6c472b7557a51526023fdc82296c",
        "sha256:6798eb17a7c4e51fc8654a2d0fdc04f2c23e4d3de7b1dd0c4c2042e405f23dd5",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        Some(1000),
        "sha256:adfaeabc18900a39d65cb0d288cd35e8f4aa6c472b7557a51526023fdc82296c",
        "sha256:8947335cccc0785d896ebfd444abb237277d1ec6075f9cc6d060c84cdc6f92a1",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        Some(2000),
        "sha256:adfaeabc18900a39d65cb0d288cd35e8f4aa6c472b7557a51526023fdc82296c",
        "sha256:bc36d5ae7895ff96f13ada239eda905bd4de973572806123d375c25b30c1f2b8",
      ),
    ] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      sga=true,
      graph_construction_limit=Some(1000),
      traversal_capacity=true,
      traversal_kind="shortest_path",
      generated_rows=Some("[]"),
      producer_expression="id",
      producer_suffix=shortest_program_suffix(
        "{\"where\":{\"literal\":false}}",
        "{\"where\":{\"literal\":false}}",
        "nearest_pair",
        false,
        match guard_value {
          None => ""
          Some(value) => ",\"max_output_rows\":" + value.to_string()
        },
      ),
      producer_result_from="projected",
      extra_step_budget=3,
    )
    let program = programs[0]
    let original = unit_traversal_limit_at(program, 0, 0).unwrap()
    let synthetic = { ..program.units[0], definition_cid: unit_cid, }
    let source = unit_operation_source(synthetic, synthetic.pipeline, 3).unwrap()
    let selected = traversal_limit_selection(original)
    let budget : IdentityBudget = {
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    }
    let converted = assemble_traversal_limit(
      [synthetic],
      source,
      selected,
      budget,
    )
    assert_eq(
      @wire.limit_cid(traversal_limit_claim(converted, SearchPaths)),
      paths_cid,
    )
    assert_eq(
      @wire.limit_cid(traversal_limit_claim(converted, OutputRows)),
      output_cid,
    )
    let work = 100000000 - budget.work
    let bytes = 10000000 - budget.bytes
    let nodes = 1000000 - budget.nodes
    let exact : IdentityBudget = { work, bytes, nodes, depth: 100, }
    let _ = assemble_traversal_limit([synthetic], source, selected, exact)
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    for
      short in [
        IdentityBudget::{ work: work - 1, bytes, nodes, depth: 100, },
        IdentityBudget::{ work, bytes: bytes - 1, nodes, depth: 100, },
        IdentityBudget::{ work, bytes, nodes: nodes - 1, depth: 100, },
      ] {
      try assemble_traversal_limit([synthetic], source, selected, short) catch {
        _ => ()
      } noraise {
        _ => fail("partial conversion")
      }
    }
    let wrong = unit_operation_source(synthetic, synthetic.pipeline, 2).unwrap()
    try
      assemble_traversal_limit([synthetic], wrong, selected, {
        work: 100000,
        bytes: 100000,
        nodes: 10000,
        depth: 100,
      })
    catch {
      UnitBuildFailure::ForeignOwner => ()
      _ => fail("reject the foreign occurrence before conversion")
    } noraise {
      _ => fail("foreign operation")
    }
  }
}
