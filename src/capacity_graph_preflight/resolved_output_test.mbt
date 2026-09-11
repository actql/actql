///|
test "resolved output bounds construct downstream proofs before sealing the complete table" {
  let policy = policy(false)
  for family in ["components", "traverse"] {
    let operation = if family == "components" {
      "{\"components\":{\"kind\":\"weak\"}}"
    } else {
      "{\"traverse\":{\"start\":{\"ids\":[\"a\"]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"nodes\"}}"
    }
    let p = input_bound_pipeline("[" + operation + ",{\"take\":1}]")
    let base = sources(0, policy)
    let initial = @input.check(p, base, policy, caps()).unwrap()
    let input_id = @wire.cid(
      @input.bound_witness(@input.input_bound(initial, 0, Nodes).unwrap()),
    )
    let candidate = graph_proof(
      "actql.bound." +
      (if family == "components" {
        "components-nodes"
      } else {
        "traverse-nodes"
      }),
      1L,
      "{\"op\":\"source\"}",
      inputs=[input_id],
    )
    let nodes = graph_proof(
      "actql.bound.components-input-nodes",
      1L,
      "{\"op\":\"source\"}",
      unit="nodes",
      inputs=[input_id],
    )
    let host = graph_host_wire(policy, "max_graph_output_rows")
    let paths = graph_host_wire(policy, "max_graph_paths")
    let output = graph_proof(
      "actql.bound." + family + "-output",
      1L,
      "{\"op\":\"source\"}",
      inputs=[
        @wire.cid(@wire.program_proof_witness(candidate)),
        @wire.cid(host),
      ],
    )
    let output_id = @wire.cid(@wire.program_proof_witness(output))
    let downstream = graph_proof(
      "actql.bound.take",
      1L,
      "{\"input\":\"" + output_id + "\",\"maximum\":1,\"op\":\"clamp\"}",
      reference="checked-step:1",
      inputs=[output_id],
    )
    let proofs = [candidate, output, downstream]
    if family == "components" {
      proofs.push(nodes)
    }
    let artifacts = [
      if family == "components" {
        component_limit_artifact(
          [@wire.program_proof_witness(nodes)],
          "nodes",
          ":nodes",
        )
      } else {
        component_limit_artifact(
          [paths],
          "paths",
          ":paths",
          operation="traverse",
        )
      },
      component_limit_artifact(
        [host, @wire.program_proof_witness(candidate)],
        "rows",
        "",
        operation=family,
      ),
    ]
    let source = sources(
      0,
      policy,
      proofs~,
      extra_wires=if family == "components" { [host] } else { [host, paths] },
      extra_limits=artifacts,
    )
    let graph = @input.check(p, source, policy, caps()).unwrap()
    let root = @program.ExistingInput(
      @program.GraphInput(@input.input_bound(graph, 0, Nodes).unwrap()),
    )
    let requests : Array[@program.ResolutionRequest] = [
      @program.DeriveApplication(0, candidate, [root], None),
    ]
    if family == "components" {
      requests.push(@program.DeriveApplication(0, nodes, [root], None))
      requests.push(@program.ComponentsApplication(0, output, 2, 3))
    } else {
      requests.push(@program.TraversalApplication(0, output, 2, 3))
    }
    let output_position = requests.length() - 1
    requests.push(
      @program.DeriveApplication(
        1,
        downstream,
        [@program.PriorApplication(output_position)],
        None,
      ),
    )
    let resolved = @program.resolve_applications(
      p,
      source,
      policy,
      requests,
      max_work=1000,
    ).unwrap()
    let result = @program.resolved_application_at(
      resolved,
      requests.length() - 1,
    ).unwrap()
    let producer = @program.resolved_application_at(resolved, output_position).unwrap()
    assert_true(physical_equal(@program.input_at(result, 0).unwrap(), producer))
    let program = @program.resolved_program(resolved)
    let applications : Array[@program.StepBound] = []
    for i in 0..<requests.length() {
      applications.push(@program.resolved_application_at(resolved, i).unwrap())
    }
    let reconstructed = @program.check_applications(
      @host.source_claims(source),
      applications,
      max_work=1000,
    ).unwrap()
    assert_true(
      @capacity_graph_preflight.check_source_coverage(
        graph,
        reconstructed,
        max_work=1000,
      )
      is Err(ForeignOutputOwner(_)),
    )
    let sequence = @sequence.check_applications(
      p,
      source,
      policy,
      [],
      max_work=1000,
    ).unwrap()
    match @program.checked_enforcement(producer).unwrap() {
      @program.SequenceEnforcement(_) => fail("unexpected sequence output")
      @program.JoinEnforcement(_) => fail("unexpected join output")
      @program.ComponentsEnforcement(limit) => {
        assert_true(
          physical_equal(@program.components_limit_program(limit), program),
        )
        let ledger = @program.check_components_applications(
          p,
          source,
          program,
          policy,
          [limit],
          max_work=1000,
        ).unwrap()
        assert_true(
          @capacity_graph_preflight.check_application_coverage(
            graph,
            program,
            sequence,
            components=Some(ledger),
            max_work=1000,
          )
          is Ok(_),
        )
      }
      @program.TraversalEnforcement(limit) => {
        assert_true(
          physical_equal(@program.traversal_limit_program(limit), program),
        )
        let ledger = @program.check_traversal_applications(
          p,
          source,
          program,
          policy,
          [limit],
          max_work=1000,
        ).unwrap()
        assert_true(
          @capacity_graph_preflight.check_application_coverage(
            graph,
            program,
            sequence,
            traversals=Some(ledger),
            max_work=1000,
          )
          is Ok(_),
        )
      }
    }
    let exact = @program.resolution_work(resolved)
    let invalid_dependency = requests.copy()
    invalid_dependency[invalid_dependency.length() - 1] = @program.DeriveApplication(
      1,
      downstream,
      [@program.PriorApplication(requests.length())],
      None,
    )
    assert_true(
      @program.resolve_applications(
        p,
        source,
        policy,
        invalid_dependency,
        max_work=1000,
      )
      is Err(InvalidDependency(_, 0)),
    )
    let duplicate = requests.copy()
    duplicate.push(requests[0])
    assert_true(
      @program.resolve_applications(p, source, policy, duplicate, max_work=1000)
      is Err(DuplicateApplication(_)),
    )
    assert_true(
      @program.resolve_applications(p, source, policy, requests, max_work=exact)
      is Ok(_),
    )
    assert_true(
      @program.resolve_applications(
        p,
        source,
        policy,
        requests,
        max_work=exact - 1,
      )
      is Err(_),
    )
    // A host-only minimum initially passes, but a later candidate for the same
    // step must make the final revalidation fail even when its value is equal.
    let early_output = graph_proof(
      "actql.bound." + family + "-output",
      1L,
      "{\"op\":\"source\"}",
      inputs=[@wire.cid(host)],
    )
    let late_proofs = [early_output, candidate]
    if family == "components" {
      late_proofs.push(nodes)
    }
    let late_source = sources(
      0,
      policy,
      proofs=late_proofs,
      extra_wires=if family == "components" { [host] } else { [host, paths] },
      extra_limits=[
        artifacts[0],
        component_limit_artifact([host], "rows", "", operation=family),
      ],
    )
    let late_graph = @input.check(p, late_source, policy, caps()).unwrap()
    let late_root = @program.ExistingInput(
      @program.GraphInput(@input.input_bound(late_graph, 0, Nodes).unwrap()),
    )
    let late_requests : Array[@program.ResolutionRequest] = []
    if family == "components" {
      late_requests.push(
        @program.DeriveApplication(0, nodes, [late_root], None),
      )
      late_requests.push(@program.ComponentsApplication(0, early_output, 2, 3))
    } else {
      late_requests.push(@program.TraversalApplication(0, early_output, 2, 3))
    }
    late_requests.push(
      @program.DeriveApplication(0, candidate, [late_root], None),
    )
    let late_result = @program.resolve_applications(
      p,
      late_source,
      policy,
      late_requests,
      max_work=1000,
    )
    if family == "components" {
      assert_true(late_result is Err(Components(_, _)))
    } else {
      assert_true(late_result is Err(Traversal(_, _)))
    }
    requests.pop() |> ignore
    assert_true(
      @program.resolve_applications(p, source, policy, requests, max_work=1000)
      is Err(Collection(MissingApplication(_))),
    )
    requests.clear()
    assert_true(
      @program.resolved_application_at(resolved, output_position) is Some(_),
    )
  }
}
