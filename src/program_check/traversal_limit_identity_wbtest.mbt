///|
// Synthetic Unit names test canonical conversion, not Unit definition admission.
test "current TRAIL limit conversion matches independent namespaces and aggregate boundaries" {
  for
    (unit_cid, cap, paths_cid, rows_cid) in [
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        1, "sha256:3798dee2bbdc5348f1056e8be96dea141c62ec4984cfce1ae1656990d7258c66",
        "sha256:b833599012c856c149441cd862873226986351a11fbec2014a2a51429a534431",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        1000, "sha256:cbea458b621e07a2cdea43eed4ac8378835fbc0678b839fc158de7b58d820afe",
        "sha256:a29f396d633c0db4661cf811040a8e0e64088387e34163f4575ed5cb366a70cd",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        1, "sha256:b01e28c017f57692f8f6efde8b3b333b999b78b78690a09909dbe4d3f9aef0e0",
        "sha256:85e4af5d9d2fdb86ce2c97aa2e948f52e65f2ca08bc0d2e07adaf2c63874ded6",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        1000, "sha256:06f7ba1d6c58cff5688b2a574f032711c27c92858ec901700eb0fc99e9883dd4",
        "sha256:78ccc86b5496a1cd28420883e84a51596979ea8658ea470ad6d085bf9510ec9b",
      ),
    ] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      property_graph=true,
      graph_output_limit=Some(cap),
      graph_construction_limit=Some(1000),
      traversal_capacity=true,
      generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
      producer_expression="id",
      producer_suffix=current_trail_resources_suffix("out", "1"),
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
