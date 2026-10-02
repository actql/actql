///|
test "Property Graph TRAIL output bounds retain ownership through downstream resolution" {
  let policy = policy(false)
  let operation = "{\"traverse\":{\"start\":{\"ids\":[{\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"definition\":\"N\",\"key\":[\"a\"]}]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"path_mode\":\"trail\",\"emit\":\"paths\"}}"
  let p = input_bound_pipeline("[" + operation + ",{\"take\":1}]")
  let host = graph_host_wire(policy, "max_graph_output_rows")
  let paths = graph_host_wire(policy, "max_graph_paths")
  let output = graph_proof(
    "actql.bound.traverse-output",
    1L,
    "{\"op\":\"source\"}",
    inputs=[@wire.cid(host)],
  )
  let output_id = @wire.cid(@wire.program_proof_witness(output))
  let downstream = graph_proof(
    "actql.bound.take",
    1L,
    "{\"input\":\"" + output_id + "\",\"maximum\":1,\"op\":\"clamp\"}",
    reference="checked-step:1",
    inputs=[output_id],
  )
  let source = sources(
    0,
    policy,
    proofs=[output, downstream],
    extra_wires=[host, paths],
    extra_limits=[
      component_limit_artifact([paths], "paths", ":paths", operation="traverse"),
      component_limit_artifact([host], "rows", "", operation="traverse"),
    ],
  )
  let graph = @input.check(p, source, policy, caps()).unwrap()
  let requests : Array[@program.ResolutionRequest] = [
    @program.TraversalApplication(0, output, 2, 3),
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
    policy,
    requests,
    max_work=1000,
  ).unwrap()
  let producer = @program.resolved_application_at(resolved, 0).unwrap()
  let result = @program.resolved_application_at(resolved, 1).unwrap()
  assert_true(physical_equal(@program.input_at(result, 0).unwrap(), producer))
  let program = @program.resolved_program(resolved)
  let reconstructed = @program.check_applications(
    @host.source_claims(source),
    [producer, result],
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
  guard @program.checked_enforcement(producer)
    is Some(@program.TraversalEnforcement(limit)) else {
    fail("missing TRAIL output enforcement")
  }
  assert_true(physical_equal(@program.traversal_limit_program(limit), program))
  let ledger = @program.check_traversal_applications(
    p,
    source,
    program,
    policy,
    [limit],
    max_work=1000,
  ).unwrap()
  let sequence = @sequence.check_applications(
    p,
    source,
    policy,
    [],
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
  let invalid_dependency = requests.copy()
  invalid_dependency[1] = @program.DeriveApplication(
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
  let exact = @program.resolution_work(resolved)
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
  requests.pop() |> ignore
  assert_true(
    @program.resolve_applications(p, source, policy, requests, max_work=1000)
    is Err(Collection(MissingApplication(_))),
  )
  requests.clear()
  assert_true(@program.resolved_application_at(resolved, 0) is Some(_))
  // TRAIL path output has no node-count candidate. The late-candidate final
  // revalidation obligation remains exercised by the supported JOIN resolver
  // in capacity_program_step/join_resolution_test.mbt, not by admitting the
  // retired traverse-nodes proof against a path result.
}
