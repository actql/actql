///|
// Synthetic Unit names test canonical conversion, not Unit definition admission.
test "reach limit conversion matches independent namespaces and aggregate boundaries" {
  for
    (unit_cid, cap, paths_cid, rows_cid) in [
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        1, "sha256:62ed88c8898baa5988c396ff01ec47d7ee70d59542a2fdc2087e78baa42bbba6",
        "sha256:7e18092b8393ba73247eb5349535402ab8245a6fa48d9b517ba089f454e5d444",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        1000, "sha256:4ab482325862a16a8926f59b361d6ae24362b505667e22c5eff5c46c31cc1caf",
        "sha256:63f38bbb64ce8e036cba04d80f7a598719f45ae5d1dd386e581e142c84573cc5",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        1, "sha256:2d639705be96813ee3ed37281a9f1c1ce580b1db750b32273c4179318339e4a6",
        "sha256:998c92446079a49641e7f5763fc498ddd01a615eeba90d7785e1810d03747b5e",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        1000, "sha256:249288df7a6d859aee03afdc14b859ccc86b399d789fba003eaecaa0b7327eaf",
        "sha256:9388530c0bd8184d3942ad1768a0b57d319b9127c9821d4cbfee78d2910fbf9b",
      ),
    ] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      sga=true,
      graph_output_limit=Some(cap),
      graph_construction_limit=Some(1000),
      traversal_capacity=true,
      traversal_kind="reach",
      generated_rows=Some("[{\"id\":1}]"),
      producer_expression="id",
      producer_suffix=",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[]}},\"as\":\"g\"},{\"reach\":{\"start\":1,\"direction\":\"out\",\"max_depth\":1}},{\"select\":[{\"id\":\"start_id\"},{\"value\":\"depth\"}],\"as\":\"projected\"}",
      producer_result_from="projected",
      extra_step_budget=3,
    )
    let program = programs[0]
    let original = unit_traversal_limit_at(program, 0, 0).unwrap()
    let synthetic = { ..program.units[0], definition_cid: unit_cid, }
    let source = unit_operation_source(synthetic, synthetic.pipeline, 3).unwrap()
    let budget : IdentityBudget = {
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    }
    let converted = assemble_traversal_limit(
      [synthetic],
      source,
      traversal_limit_selection(original),
      budget,
    )
    assert_eq(
      @wire.limit_cid(
        traversal_limit_claim(converted, @step_bounds.SearchPaths),
      ),
      paths_cid,
    )
    assert_eq(
      @wire.limit_cid(
        traversal_limit_claim(
          converted,
          @step_bounds.TraversalScope::OutputRows,
        ),
      ),
      rows_cid,
    )
    let work = 100000000 - budget.work
    let bytes = 10000000 - budget.bytes
    let nodes = 1000000 - budget.nodes
    let exact : IdentityBudget = { work, bytes, nodes, depth: 100, }
    let _ = assemble_traversal_limit(
      [synthetic],
      source,
      traversal_limit_selection(original),
      exact,
    )
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    for
      short in [
        IdentityBudget::{ work: work - 1, bytes, nodes, depth: 100, },
        IdentityBudget::{ work, bytes: bytes - 1, nodes, depth: 100, },
        IdentityBudget::{ work, bytes, nodes: nodes - 1, depth: 100, },
      ] {
      try
        assemble_traversal_limit(
          [synthetic],
          source,
          traversal_limit_selection(original),
          short,
        )
      catch {
        _ => ()
      } noraise {
        _ => fail("incomplete conversion must not escape")
      }
    }
    let wrong = unit_operation_source(synthetic, synthetic.pipeline, 2).unwrap()
    try
      assemble_traversal_limit(
        [synthetic],
        wrong,
        traversal_limit_selection(original),
        { work: 100000, bytes: 100000, nodes: 10000, depth: 100, },
      )
    catch {
      UnitBuildFailure::ForeignOwner => ()
      _ => fail("wrong occurrence must be rejected before conversion")
    } noraise {
      _ => fail("foreign operation")
    }
  }
}
