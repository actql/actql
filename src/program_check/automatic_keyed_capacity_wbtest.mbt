///|
test "standard keyed acquisition derives unpublished left input bounds" {
  let environment = remote_environment_fixture()
  let sources = local_join_capacity_fixture(environment, 1, 2)
  let mixed = @wire.program_claim_mixed(@host.source_claims(sources)).unwrap()
  let text =
    #|{"version":"actql/0.1","id":"keyed-demand","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"tenant":null}}},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"append":{"with":"seed"},"as":"left_rows"},{"join":{"left":"left_rows","with":"remote","on":"id","kind":"left","select":{"id":"left.id"}}}],"results":{"out":{"from":"seed","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let defaults = distinct_compile_limits()
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
  )
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
