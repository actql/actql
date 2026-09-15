///|
fn keyed_capacity_request_fixture(empty : Bool) -> CheckOutcome raise {
  let environment = remote_environment_fixture()
  let sources = local_join_capacity_fixture(environment, 1, 2)
  let mixed = @wire.program_claim_mixed(@host.source_claims(sources)).unwrap()
  let text =
    #|{"version":"actql/0.1","id":"keyed-demand","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"tenant":null}}},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"append":{"with":"seed"},"as":"left_rows"},{"join":{"left":"left_rows","with":"remote","on":"id","kind":"left","select":{"id":"left.id"}}}],"results":{"out":{"from":"seed","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let defaults = distinct_compile_limits()
  let text = if empty {
    text.replace(old="\"rows\":[{\"id\":1}]", new="\"rows\":[]")
  } else {
    text
  }
  let outcome = check_document_with_evidence(
    text,
    checking_environment(environment, { text_time: false, veca: false, }, {
      rela: true,
      sga: false,
      tea: false,
      calendar: false,
      text_rank: false,
    }),
    None,
    [
      {
        stage: "s",
        sources,
        uses: [
          @context.Join(step=2, output=@wire.mixed_limit_at(mixed, 0).unwrap()),
        ],
      },
    ],
    {
      input: {
        source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
        tree: {
          max_nodes: 1000,
          max_depth: 100,
          max_string_bytes: 10000,
          max_total_string_bytes: 10000,
        },
        max_stages: 10,
      },
      compilation: {
        ..defaults,
        work: 100000000,
        artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
        traversal: {
          nodes: 1000000,
          depth: 100,
          text_bytes: 10000000,
          string_bytes: 1000000,
          name_bytes: 1000000,
          pointer_units: 100000,
          comparison_pairs: 100000,
        },
        values: { nodes: 1000000, depth: 100, text_bytes: 10000000, },
        policy: { bytes: 1000000, nodes: 100000, depth: 100, },
      },
    },
    format=Json,
    source_path="keyed.actql",
  )
  outcome
}

///|
test "standard keyed acquisition derives unpublished left input bounds" {
  let outcome = keyed_capacity_request_fixture(false)
  let program = match outcome {
    Checked(program) => program
    Rejected(diagnostic) => raise diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("unexpected missing inputs")
  }
  assert_eq(keyed_input_proof_count(program), 1)
  let proof = keyed_input_proof_at(program, 0).unwrap()
  assert_eq(
    @wire.value(
      @wire.program_proof_witness(proof_claim(keyed_input_proof_bound(proof))),
    ),
    2L,
  )
}

///|
test "keyed acquisition shortage retains the join and does not substitute an output ceiling" {
  guard keyed_capacity_request_fixture(true) is NeedsInputs(requests) else {
    fail("expected positive keyed input bound request")
  }
  assert_eq(input_request_count(requests), 1)
  let request = input_request_at(requests, 0).unwrap()
  guard request.kind is KeyedAcquisitionInputRows(source) else {
    fail("wrong keyed request kind")
  }
  assert_true(physical_equal(input_request_source(request).unwrap(), source))
  assert_eq(input_request_origin(request), ProgramDocument)
  assert_eq(
    diagnostic_location_source_path(
      diagnostic_location(input_requests_diagnostic(requests)).unwrap(),
    ),
    "keyed.actql",
  )
  assert_eq(input_request_path(request), [
    @source.Key("stages"),
    @source.Index(0),
    @source.Key("steps"),
    @source.Index(2),
  ])
  assert_true(keyed_capacity_request_fixture(false) is Checked(_))
  assert_true(input_request_at(requests, 1) is None)
}
