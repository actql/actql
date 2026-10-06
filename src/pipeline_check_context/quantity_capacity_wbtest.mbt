///|
test "capacity demand keeps node and edge premises separate at the same graph target" {
  for reverse in [false, true] {
    let nodes = "{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]},\"from\":\"g\",\"as\":\"nodes\"}"
    let edges = "{\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]},\"from\":\"g\",\"as\":\"edges\"}"
    let text = (
        #|{"version":"actql/0.1","id":"quantity-demand","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"n"},{"values":{"schema":{"id":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"id":10,"src":1,"dst":2}]},"as":"e"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["id"]}],"edges":[{"name":"E","from":"e","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}]},"as":"g"},
      ) +
      (if reverse { edges + "," + nodes } else { nodes + "," + edges }) +
      (
        #|],"results":{"nodes":{"from":"nodes","fields":["key"]},"edges":{"from":"edges","fields":["key"]}}}],"results":{"out":{"from":{"stage":"s","result":"nodes"}}}}
      )
    let program = @syntax.parse(
      text,
      {
        source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
        tree: {
          max_nodes: 1000,
          max_depth: 100,
          max_string_bytes: 10000,
          max_total_string_bytes: 10000,
        },
        max_stages: 1,
      },
      format=Json,
    ).unwrap()
    let prepared = @stage_results.prepare_local_source(
      program,
      None,
      max_parameters=0,
      {
        max_stages: 1,
        max_steps: 5,
        max_results: 2,
        max_work: 1000000,
        max_nodes: 100000,
        max_tokens: 10000,
        max_text_bytes: 1000000,
        max_depth: 100,
      },
    ).unwrap()
    let inputs = bind_capacity_inputs(program, [], 1000).unwrap()
    let result = derive_program_capacity(
      prepared,
      inputs,
      1000000,
      { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      100000,
      100000,
      capacity_count_bindings(@stage_results.local_source_values(prepared)),
      1000000,
      None,
      sequence_limit_policy(false),
    ).unwrap()
    let claims = @host.source_claims(result.inputs.materials[0].sources)
    let mut node_count = 0
    let mut edge_count = 0
    let mut node_rows = 0
    let mut edge_rows = 0
    for i in 0..<@wire.claim_count(@wire.program_claim_arithmetic(claims)) {
      guard @wire.program_claim_proof_at(claims, i) is Some(proof) else {
        continue
      }
      let witness = @wire.program_proof_witness(proof)
      match @law.name(@wire.law(witness)) {
        "actql.bound.graph-construction-nodes" => {
          assert_eq(@wire.value(witness), 2L)
          node_count += 1
        }
        "actql.bound.graph-construction-edges" => {
          assert_eq(@wire.value(witness), 1L)
          edge_count += 1
        }
        "actql.bound.match-nodes" => {
          assert_eq(@wire.value(witness), 2L)
          node_rows += 1
        }
        "actql.bound.match-edges" => {
          assert_eq(@wire.value(witness), 1L)
          edge_rows += 1
        }
        _ => ()
      }
    }
    assert_eq((node_count, edge_count, node_rows, edge_rows), (1, 1, 1, 1))
    // Re-admit the generated graph through the ordinary owned capacity path;
    // inspecting the generated wire alone would not check operand ownership.
    assert_true(
      prepare_local_stage_contexts_from_inputs(
        prepared,
        result.inputs,
        sequence_limit_policy(false),
        {
          max_work: 1000000,
          max_text_bytes: 1000000,
          max_name_bytes: 100000,
          max_input_work: 100000,
          max_operand_work: 100000,
        },
      )
      is Ok(_),
    )
    for allowance in [result.work, result.work - 1] {
      let checked = derive_program_capacity(
        prepared,
        inputs,
        allowance,
        { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
        100000,
        100000,
        capacity_count_bindings(@stage_results.local_source_values(prepared)),
        1000000,
        None,
        sequence_limit_policy(false),
      )
      assert_eq(checked is Ok(_), allowance == result.work)
    }
  }
}
