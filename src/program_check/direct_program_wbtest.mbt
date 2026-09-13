///|
fn checked_direct_program_fixture(
  extra_derive? : Bool = false,
) -> CheckedProgram raise {
  let text =
    #|{"version":"actql/0.1","id":"direct","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"id":1,"tenant":null}}},"steps":[{"distinct":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let program = @syntax.parse(
    if extra_derive {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"derive\":{\"x\":\"id\"}},",
      )
    } else {
      text
    },
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let environment = remote_environment_fixture()
  // No Program arithmetic assertion is needed: publication retains the Host
  // bound and distinct establishes its own key. Actual acquisition is not run.
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  check(
    program,
    environment,
    None,
    [[@context.CapacityMaterial::{ sources, consumers: [], }]],
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    source_limits_fixture(2),
    max_work=100000000,
    max_bytes=10000000,
    max_nodes=1000000,
    max_depth=100,
  )
}

///|
test "direct SourceView closes through the public check entry" {
  let program = checked_direct_program_fixture()
  assert_eq(unit_count(program), 1)
  assert_eq(source_execution_count(program), 5)
  assert_eq(unit_publication_count(program, 0), Some(1))
  let publication = unit_publication_at(program, 0, 0).unwrap()
  let policy = publication_source_policy(publication).unwrap()
  assert_eq(policy.target, @pipeline.Step(0))
  assert_true(source_execution_kind(policy.prerequisite) is CarrierResponse)
  let writer = @encode.hashing_writer(10000, 100, 10)
  emit_direct_source_policy(policy.policy, writer)
  assert_eq(policy.cid, "sha256:" + @encode.finish_hash(writer))
  assert_true(
    physical_equal(
      policy.policy,
      source_execution_subject(policy.prerequisite).direct_policy.unwrap(),
    ),
  )
  for index in 0..<source_execution_count(program) {
    let check = source_execution_at(program, index).unwrap()
    let subject = source_execution_subject(check)
    assert_true(physical_equal(subject.owner, source_identity(program)))
    assert_true(subject.direct_policy is Some(_))
    assert_eq(subject.stage, 0)
    assert_eq(subject.input, 0)
    for dependency in 0..<source_execution_prerequisite_count(check) {
      let prior = source_execution_prerequisite_at(check, dependency).unwrap()
      assert_true(physical_equal(source_execution_subject(prior), subject))
    }
  }
}

///|
test "unsupported publication policy composition remains a static rejection" {
  try checked_direct_program_fixture(extra_derive=true) catch {
    Units(UnclosedPublicationPolicy(0, 0)) => ()
    error => raise error
  } noraise {
    _ => fail("unresolved policy transfer admitted")
  }
}

///|
test "direct source audit rejects missing foreign and disconnected checks atomically" {
  let program = checked_direct_program_fixture()
  let checks = program.units[0].source_execution
  let exact = IdentityBudget::{ work: 16, bytes: 0, nodes: 0, depth: 0, }
  audit_source_execution(program.contracts, checks, exact)
  assert_eq(exact.work, 0)
  let short = IdentityBudget::{ work: 15, bytes: 0, nodes: 0, depth: 0, }
  try audit_source_execution(program.contracts, checks, short) catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("source audit escaped work budget")
  }
  let foreign = checked_direct_program_fixture().units[0].source_execution
  let missing = checks[:4].to_owned()
  let substituted = checks.copy()
  substituted[4] = foreign[4]
  let disconnected = checks.copy()
  disconnected[3] = { ..checks[3], prerequisites: [], }
  let duplicated = checks.copy()
  duplicated[2] = checks[1]
  for invalid in [missing, foreign, substituted, disconnected, duplicated] {
    try
      audit_source_execution(program.contracts, invalid, {
        work: 1000,
        bytes: 0,
        nodes: 0,
        depth: 0,
      })
    catch {
      ForeignOwner | UnclosedSourceExecution(_, _) => ()
      error => raise error
    } noraise {
      _ => fail("invalid source closure admitted")
    }
  }
}
