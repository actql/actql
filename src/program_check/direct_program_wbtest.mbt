///|
fn checked_direct_program_fixture(
  extra_derive? : Bool = false,
  unused_source? : Bool = false,
  filter? : String = "",
) -> CheckedProgram raise {
  let text =
    #|{"version":"actql/0.1","id":"direct","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"id":1,"tenant":null}}},"steps":[{"distinct":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let program = @syntax.parse(
    if extra_derive {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"derive\":{\"x\":\"id\"}},",
      )
    } else if filter != "" {
      let filtered = text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"filter\":" + filter + "},",
      )
      if filter.contains("$threshold") {
        filtered.replace(
          old="\"stages\":",
          new="\"params\":{\"threshold\":{\"type\":\"number\",\"default\":0}},\"stages\":",
        )
      } else {
        filtered
      }
    } else if unused_source {
      text
      .replace(
        old="\"inputs\":{\"remote\":",
        new="\"inputs\":{\"unused\":{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"id\":2,\"tenant\":null},\"minimum_classification\":\"restricted\"},\"remote\":",
      )
      .replace(old="{\"distinct\":", new="{\"from\":\"remote\",\"distinct\":")
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
test "filter publication retains its checked predicate and policy occurrence" {
  for predicate in ["\"id = id\"", "\"id > 0\"", "\"id > $threshold\""] {
    let program = checked_direct_program_fixture(filter=predicate)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(publication_policy_predicate_count(policy), 1)
    let occurrence = publication_policy_predicate_at(policy, 0).unwrap()
    assert_eq(occurrence.step, 0)
    guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("expected filter")
    }
    assert_true(
      physical_equal(
        occurrence.expression,
        @relation.binding_expression_at(operation, 0).unwrap(),
      ),
    )
    assert_eq(occurrence.unknown_provenance, predicate != "\"id = id\"")
    assert_eq(@typing.node_count(occurrence.expression), 3)
    assert_true(publication_policy_predicate_at(policy, -1) is None)
    assert_true(publication_policy_predicate_at(policy, 1) is None)
    let writer = @encode.writer(10000, 100, 10)
    emit_publication_source_policy(policy, writer)
    assert_eq(
      "sha256:" + @sha.text_hex(@encode.finish(writer)).unwrap(),
      policy.cid,
    )
    assert_true(policy.unknown_provenance)
    assert_true(source_execution_kind(policy.prerequisite) is CarrierResponse)
  }
}

///|
test "filter policy transfer charges predicates and nodes before completing publication" {
  let program = checked_direct_program_fixture(filter="\"id > $threshold\"")
  let unit = program.units[0]
  let publication = @context.publication_row_limit_result(
    unit.publication_rows[0],
  )
  let initial = 100000
  let measured = IdentityBudget::{
    work: initial,
    bytes: initial,
    nodes: initial,
    depth: 100,
  }
  let expected = prepare_publication_source_policy(unit, publication, measured).unwrap()
  let used = initial - measured.work
  let exact = IdentityBudget::{
    work: used,
    bytes: initial,
    nodes: initial,
    depth: 100,
  }
  let actual = prepare_publication_source_policy(unit, publication, exact).unwrap()
  assert_eq(actual.cid, expected.cid)
  assert_eq(exact.work, 0)
  let short = IdentityBudget::{
    work: used - 1,
    bytes: initial,
    nodes: initial,
    depth: 100,
  }
  try prepare_publication_source_policy(unit, publication, short) catch {
    BudgetExceeded | Encoding(_) => ()
    error => raise error
  } noraise {
    _ => fail("partial policy escaped preparation budget")
  }
}

///|
test "publication policy follows the selected input rather than unused source policies" {
  let baseline = checked_direct_program_fixture()
  let baseline_policy = publication_source_policy(
    unit_publication_at(baseline, 0, 0).unwrap(),
  ).unwrap()
  let program = checked_direct_program_fixture(unused_source=true)
  assert_eq(source_execution_count(program), 10)
  let published = publication_source_policy(
    unit_publication_at(program, 0, 0).unwrap(),
  ).unwrap()
  let selected = source_execution_subject(published.prerequisite)
  assert_eq(published.cid, baseline_policy.cid)
  assert_eq(published.policy.response_cid, baseline_policy.policy.response_cid)
  // Equal policy identities do not make independently checked owners equal.
  assert_false(
    physical_equal(published.prerequisite, baseline_policy.prerequisite),
  )
  assert_eq(@sourceviews.declaration(selected.source).input_name, "remote")
  assert_true(published.policy.response.minimum is None)
  let mut unused = 0
  for i in 0..<source_execution_count(program) {
    let check = source_execution_at(program, i).unwrap()
    let subject = source_execution_subject(check)
    if @sourceviews.declaration(subject.source).input_name == "unused" {
      unused += 1
      assert_true(subject.response_policy.minimum is Some("restricted"))
      assert_true(subject.response_policy_cid != published.policy.response_cid)
      assert_false(physical_equal(subject, selected))
    }
  }
  // Unused acquisition still has every mandatory check, but does not enter the
  // selected Result's effective policy or its response-admission prerequisite.
  assert_eq(unused, 5)
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
