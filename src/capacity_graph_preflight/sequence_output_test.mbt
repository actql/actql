///|
test "sequence output bounds preserve both enforcement scopes through downstream take" {
  let p = consumer_pipeline(true, tail=",{\"take\":4}")
  let selected = policy(false)
  let host = graph_host_wire(selected, "max_temporal_output_rows")
  let matches = graph_host_wire(selected, "max_temporal_matches_per_key")
  let output = graph_proof(
    "actql.bound.sequence-output",
    1L,
    "{\"op\":\"source\"}",
    inputs=[@wire.cid(host)],
  )
  let output_id = @wire.cid(@wire.program_proof_witness(output))
  let downstream = graph_proof(
    "actql.bound.take",
    1L,
    "{\"input\":\"" + output_id + "\",\"maximum\":4,\"op\":\"clamp\"}",
    reference="checked-step:1",
    inputs=[output_id],
  )
  let source = combined_sources(false, proofs=[output, downstream])
  let requests : Array[@program.ResolutionRequest] = [
    @program.SequenceApplication(0, output, 2, 3),
    @program.DeriveApplication(
      1,
      downstream,
      [@program.PriorApplication(0)],
      None,
    ),
  ]
  let resolved = @program.resolve_applications(
    p,
    source,
    selected,
    requests,
    max_work=1000,
  ).unwrap()
  let app = @program.resolved_application_at(resolved, 0).unwrap()
  let last = @program.resolved_application_at(resolved, 1).unwrap()
  assert_true(physical_equal(@program.input_at(last, 0).unwrap(), app))
  guard @program.checked_enforcement(app)
    is Some(@program.SequenceEnforcement(limit)) else {
    fail("missing sequence enforcement")
  }
  assert_eq(@sequence.limit_index(limit, @sequence.MatchesPerKey), 2)
  assert_eq(@sequence.limit_index(limit, @sequence.OutputRows), 3)
  assert_true(physical_equal(@sequence.checked_sources(limit), source))
  let graph = @capacity_graph_preflight.check(p, source, selected, caps()).unwrap()
  let sequence = @sequence.check_applications(
    p,
    source,
    selected,
    [limit],
    max_work=1000,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      @program.resolved_program(resolved),
      sequence,
      max_work=1000,
    )
    is Ok(_),
  )
  let exact = @program.resolution_work(resolved)
  assert_true(
    @program.resolve_applications(p, source, selected, requests, max_work=exact)
    is Ok(_),
  )
  assert_true(
    @program.resolve_applications(
      p,
      source,
      selected,
      requests,
      max_work=exact - 1,
    )
    is Err(_),
  )
  let swapped = requests.copy()
  swapped[0] = @program.SequenceApplication(0, output, 3, 2)
  assert_true(
    @program.resolve_applications(p, source, selected, swapped, max_work=1000)
    is Err(Sequence(0, SubjectMismatch(MatchesPerKey))),
  )
  let wrong_scope = graph_proof(
    "actql.bound.sequence-output",
    1L,
    "{\"op\":\"source\"}",
    inputs=[@wire.cid(matches)],
  )
  swapped[0] = @program.SequenceApplication(0, wrong_scope, 2, 3)
  assert_true(
    @program.resolve_applications(p, source, selected, swapped, max_work=1000)
    is Err(InvalidOutputProof(0)),
  )
  let foreign = combined_sources(false, proofs=[output, downstream])
  let foreign_graph = @capacity_graph_preflight.check(
    p,
    foreign,
    selected,
    caps(),
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_source_coverage(
      foreign_graph,
      @program.resolved_program(resolved),
      max_work=1000,
    )
    is Err(ForeignClaims),
  )
}
