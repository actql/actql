///|
fn graph_host_wire(
  policy : @policy.Policy,
  field : String,
) -> @wire.WireWitness raise {
  let host = @host.create(@policy.ceiling(policy, field).unwrap(), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let writer = @encode.writer(4096, 100, 10)
  @host.emit(host, writer)
  @wire.admit(@utf8.encode(@encode.finish(writer)), @host.cid(host), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
}

///|
test "traversal consumption binds separate search and output scopes including unused branches" {
  let policy = policy(false)
  let path_host = graph_host_wire(policy, "max_graph_paths")
  let row_host = graph_host_wire(policy, "max_graph_output_rows")
  let unrelated = graph_host_wire(policy, "max_relation_output_rows")
  for emission in ["nodes", "paths"] {
    for mode in 0..<7 {
      let body = "[{\"traverse\":{\"start\":{\"ids\":[\"a\"]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"" +
        emission +
        "\"" +
        (if mode == 6 { ",\"max_output_rows\":1" } else { "" }) +
        "},\"as\":\"unused\"},{\"node_rows\":true,\"from\":\"g\"}]"
      let p = input_bound_pipeline(body)
      let base_sources = sources(0, policy)
      let base_graph = @input.check(p, base_sources, policy, caps()).unwrap()
      let root = @input.input_bound(base_graph, 0, Nodes).unwrap()
      let proof = graph_proof(
        "actql.bound.traverse-nodes",
        1L,
        "{\"op\":\"source\"}",
        inputs=[@wire.cid(@input.bound_witness(root))],
      )
      let proofs = if emission == "nodes" { [proof] } else { [] }
      let row_candidates = [if mode == 2 { unrelated } else { row_host }]
      if emission == "nodes" && mode != 1 {
        row_candidates.push(@wire.program_proof_witness(proof))
      }
      let limits = if mode == 5 {
        []
      } else {
        [
          component_limit_artifact(
            [if mode == 3 { row_host } else { path_host }],
            if mode == 3 {
              "rows"
            } else {
              "paths"
            },
            ":paths",
            operation=if mode == 4 { "components" } else { "traverse" },
          ),
          component_limit_artifact(
            row_candidates,
            "rows",
            "",
            operation="traverse",
          ),
        ]
      }
      let sources = sources(
        0,
        policy,
        proofs~,
        extra_wires=[path_host, row_host, unrelated],
        extra_limits=limits,
      )
      let graph = @input.check(p, sources, policy, caps()).unwrap()
      let bound = @input.input_bound(graph, 0, Nodes).unwrap()
      let apps = if emission == "nodes" {
        [
          @program.check_with_sources(p, 0, proof, [@program.GraphInput(bound)]).unwrap(),
        ]
      } else {
        []
      }
      let program = @program.check_applications(
        @host.source_claims(sources),
        apps,
        max_work=100,
      ).unwrap()
      let result = @program.check_traversal_limits(
        p,
        0,
        sources,
        program,
        policy,
        2,
        3,
        max_work=100,
      )
      match mode {
        1 if emission == "nodes" => {
          assert_true(
            result is Err(Candidates(OutputRows, MissingProgramCandidate(_))),
          )
          continue
        }
        2 => {
          assert_true(
            result is Err(Candidates(OutputRows, CandidateScopeMismatch(_))),
          )
          continue
        }
        3 => {
          assert_true(result is Err(Candidates(SearchPaths, WrongUnit)))
          continue
        }
        4 => {
          assert_true(result is Err(SubjectMismatch(SearchPaths)))
          continue
        }
        5 => {
          assert_true(result is Err(MissingLimit(SearchPaths)))
          let sequence = @sequence.check_applications(
            p,
            sources,
            policy,
            [],
            max_work=100,
          ).unwrap()
          assert_true(
            @capacity_graph_preflight.check_application_coverage(
              graph,
              program,
              sequence,
              max_work=100,
            )
            is Err(MissingTraversalApplications(0)),
          )
          continue
        }
        6 => {
          assert_true(result is Err(UnresolvedAuthorSource))
          continue
        }
        _ => ()
      }
      let application = result.unwrap()
      let cost = @program.traversal_limit_work(application)
      assert_true(
        @program.check_traversal_limits(
          p,
          0,
          sources,
          program,
          policy,
          2,
          3,
          max_work=cost,
        )
        is Ok(_),
      )
      assert_true(
        @program.check_traversal_limits(
          p,
          0,
          sources,
          program,
          policy,
          2,
          3,
          max_work=cost - 1,
        )
        is Err(Candidates(OutputRows, WorkLimit)),
      )
      let applications = [application]
      let ledger = @program.check_traversal_applications(
        p,
        sources,
        program,
        policy,
        applications,
        max_work=100,
      ).unwrap()
      applications.clear()
      assert_true(
        physical_equal(
          @program.traversal_application_at(ledger, 0).unwrap(),
          application,
        ),
      )
      assert_eq(@program.traversal_unconsumed_limit_count(ledger), 2)
      let work = @program.traversal_application_work(ledger)
      assert_eq(work, 11)
      assert_true(
        @program.check_traversal_applications(
          p,
          sources,
          program,
          policy,
          [application],
          max_work=work - 1,
        )
        is Err(WorkLimit),
      )
      assert_true(
        @program.check_traversal_applications(
          p,
          sources,
          program,
          policy,
          [],
          max_work=100,
        )
        is Err(MissingApplication(0)),
      )
      assert_true(
        @program.check_traversal_applications(
          p,
          sources,
          program,
          policy,
          [application, application],
          max_work=100,
        )
        is Err(DuplicateApplication(1)),
      )
      let sequence = @sequence.check_applications(
        p,
        sources,
        policy,
        [],
        max_work=100,
      ).unwrap()
      let covered = @capacity_graph_preflight.check_application_coverage(
        graph,
        program,
        sequence,
        traversals=Some(ledger),
        max_work=100,
      ).unwrap()
      let exact = @capacity_graph_preflight.application_coverage_work(covered)
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          traversals=Some(ledger),
          max_work=exact,
        )
        is Ok(_),
      )
      assert_true(
        @capacity_graph_preflight.check_application_coverage(
          graph,
          program,
          sequence,
          traversals=Some(ledger),
          max_work=exact - 1,
        )
        is Err(Consumer(WorkLimit)),
      )
      assert_true(
        physical_equal(
          @capacity_graph_preflight.consumer_coverage_traversals(
            @capacity_graph_preflight.application_coverage_consumers(covered),
          ).unwrap(),
          ledger,
        ),
      )
    }
  }
}
