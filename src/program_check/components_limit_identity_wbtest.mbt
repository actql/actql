///|
// Synthetic Unit namespaces test preimages only, not admission of those Unit IDs.
test "component limit conversion matches independent Unit and dependency vectors" {
  for
    (unit_cid, rows, cap, nodes_cid, output_cid, host_cid) in [
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        0, 1, "sha256:3111671a589725a605e9d803b0dbb037f1c3a06e82e883404f3ce40c13b8e66f",
        "sha256:40aba2365bf238ec9b9a956b730762aecf85e43dd808eb8fe28784f73b0937e4",
        "sha256:ef65674a4c96c56f5592161863ebd85d56ec0748af68609eb28d215a7e45a5ef",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        0, 1000, "sha256:3111671a589725a605e9d803b0dbb037f1c3a06e82e883404f3ce40c13b8e66f",
        "sha256:5dfc304ebaa674f7c11ca81105647b247147581bfbf36df0eeb2a0817ad82555",
        "sha256:f9830b072670c8058d5ed18c6b35bc106652a895444188a6f78158d4c58455cc",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        3, 1, "sha256:0c9b40b75c0ca711a51a27e9db007083b3a84cee530e42a65ffdd354b89e8ec0",
        "sha256:83ffab3e436d6b95509169dae641b6428df454050c2c8590c17cd1e3ef448bb7",
        "sha256:ef65674a4c96c56f5592161863ebd85d56ec0748af68609eb28d215a7e45a5ef",
      ),
      (
        "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        3, 1000, "sha256:0c9b40b75c0ca711a51a27e9db007083b3a84cee530e42a65ffdd354b89e8ec0",
        "sha256:808b74e470be44a54e4f613ca67c31edbaca4d304c83f667b4e8c7971abe8f02",
        "sha256:f9830b072670c8058d5ed18c6b35bc106652a895444188a6f78158d4c58455cc",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        0, 1, "sha256:eea4a8408bba1688b87e33631b0749107879a2ce23b1aa5f77cb8e0a35b274eb",
        "sha256:7a0246cb0df5d49c07e4749b612e2c87e8c84641d34ef105f603a2b37ffbd902",
        "sha256:ef65674a4c96c56f5592161863ebd85d56ec0748af68609eb28d215a7e45a5ef",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        0, 1000, "sha256:eea4a8408bba1688b87e33631b0749107879a2ce23b1aa5f77cb8e0a35b274eb",
        "sha256:a4677e82629e2872a29fbf1bd528996d7eeffc865665dd42ec8c90ec26f0fd33",
        "sha256:f9830b072670c8058d5ed18c6b35bc106652a895444188a6f78158d4c58455cc",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        3, 1, "sha256:215eea3341689944427b956dcabec7f134816325507d30e4744201f8eba028cc",
        "sha256:df1d3a8c29929841b3caa1f4181a7a2e822e5352aedc1b01e6e7ecd25cbc760e",
        "sha256:ef65674a4c96c56f5592161863ebd85d56ec0748af68609eb28d215a7e45a5ef",
      ),
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        3, 1000, "sha256:215eea3341689944427b956dcabec7f134816325507d30e4744201f8eba028cc",
        "sha256:4e4ebf1ca17ac7b31666dfb4249a57890f642256dd8c1f0a3619631095871025",
        "sha256:f9830b072670c8058d5ed18c6b35bc106652a895444188a6f78158d4c58455cc",
      ),
    ] {
    let programs : Array[CheckedProgram] = []
    let (_, _, _, _, units) = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      sga=true,
      graph_construction_limit=Some(1000),
      components_capacity_rows=Some(rows),
      graph_output_limit=Some(cap),
      generated_rows=Some(
        if rows == 0 {
          "[]"
        } else {
          "[{\"id\":1},{\"id\":2},{\"id\":3}]"
        },
      ),
      producer_suffix=",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[]}},\"as\":\"g\"},{\"components\":{\"kind\":\"weak\"}},{\"select\":[{\"id\":\"node_id\"},{\"value\":\"component_size\"}],\"as\":\"projected\"}",
      producer_result_from="projected",
      extra_step_budget=3,
    )
    assert_eq(unit_components_limit_count(programs[0], 0), Some(1))
    assert_true(unit_components_limit_at(programs[0], 0, -1) is None)
    assert_true(unit_components_limit_at(programs[0], 0, 1) is None)
    let original = unit_components_limit_at(programs[0], 0, 0).unwrap()
    let synthetic = { ..units[0], definition_cid: unit_cid, }
    let source = unit_operation_source(synthetic, synthetic.pipeline, 3).unwrap()
    let converted = assemble_components_limit(
      [synthetic],
      source,
      components_limit_selection(original),
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    )
    for
      (scope, suffix, expected) in [
        (@step_bounds.InputNodes, "nodes", nodes_cid),
        (OutputRows, "output", output_cid),
      ] {
      let claim = components_limit_claim(converted, scope)
      assert_eq(@wire.limit_cid(claim), expected)
      assert_eq(
        @wire.limit_subject(claim),
        "unit:" + unit_cid + "#/steps/3/components/" + suffix,
      )
      assert_true(
        @wire.limit_cid(claim) !=
        @wire.limit_cid(
          @step_bounds.components_limit_claim(
            components_limit_selection(original).limits,
            scope,
          ),
        ),
      )
    }
    let claim = components_limit_claim(converted, @step_bounds.OutputRows)
    let minimum = @wire.limit_minimum(claim)
    let mut hosts = 0
    for i in 0..<@derivation.minimum_candidate_count(minimum) {
      let node = @derivation.minimum_candidate_at(minimum, i).unwrap().node
      let witness = @wire.claim_at(@wire.limit_claims(claim), node).unwrap()
      if @wire.source(witness) is HostPolicy(_, _) {
        hosts += 1
        assert_eq(@wire.cid(witness), host_cid)
      }
    }
    assert_eq(hosts, 1)
    assert_eq(components_limit_proof_count(converted), 2)
    // Candidate repetition changes the preimage, not the minimum or dependency truth.
    let nodes = components_limit_claim(converted, @step_bounds.InputNodes)
    let first = @derivation.minimum_candidate_at(@wire.limit_minimum(nodes), 0).unwrap().node
    let witness = @wire.claim_at(@wire.limit_claims(nodes), first).unwrap()
    let repeated = assemble_aggregate_limit_claim(
      @wire.limit_subject(nodes),
      [(@wire.cid(witness), witness), (@wire.cid(witness), witness)],
      converted.proofs,
      None,
      Some(rows.to_int64()),
      rows.to_int64(),
      "nodes",
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      preserve_candidate_occurrences=true,
    )
    assert_eq(
      @derivation.minimum_candidate_count(@wire.limit_minimum(repeated)),
      2,
    )
    assert_eq(
      @derivation.minimum_value(@wire.limit_minimum(repeated)),
      rows.to_int64(),
    )
    assert_true(@wire.limit_cid(repeated) != @wire.limit_cid(nodes))
    try
      assemble_components_limit(
        [synthetic],
        source,
        components_limit_selection(original),
        { work: 0, bytes: 10000000, nodes: 1000000, depth: 100, },
      )
    catch {
      BudgetExceeded => ()
      other => raise other
    } noraise {
      _ => fail("short conversion budget accepted")
    }
    try
      assemble_components_limit(
        [synthetic],
        { ..source, source_ordinal: 2, },
        components_limit_selection(original),
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      )
    catch {
      ForeignOwner => ()
      other => raise other
    } noraise {
      _ => fail("foreign operation subject accepted")
    }
    for i in 0..<components_limit_proof_count(converted) {
      let proof = components_limit_proof_at(converted, i).unwrap()
      assert_true(
        @wire.source(@wire.program_proof_witness(proof_claim(proof)))
        is Program(reference, _) &&
        reference == "unit:" + unit_cid + "#/steps/3",
      )
      assert_eq(proof_input_count(proof), 1)
      let parent = proof_input_at(proof, 0).unwrap()
      assert_true(
        @wire.source(@wire.program_proof_witness(proof_claim(parent)))
        is Program(reference, _) &&
        reference == "unit:" + unit_cid + "#/steps/2",
      )
    }
  }
}
