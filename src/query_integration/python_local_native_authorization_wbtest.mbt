///|
fn python_native_account(
  outcome : @authorization.ConfiguredOutcome,
) -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration({
    account_id: "python-native-source-account",
    entries: [
      {
        entry_id: "source-read",
        outcome,
        scope: {
          principal: AnyOf(["local-user"]),
          connection: AnyOf(["local-database"]),
          resource: AnyOf(["fixture.db"]),
          operation: AnyOf(["read"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
}

///|
fn python_native_plan(
  run_id : String,
  declarations? : Bool = true,
) -> (
  @local_run.LocalRunPlan,
  @local_run.LocalRunPhysicalStart,
  @authorization.DispatchAuthorization,
) {
  let catalog = if declarations {
    resident_native_source_evidence_catalog()
  } else {
    query_amount_nullable_catalog()
  }
  let wire = @environment.member_environment(
    @environment.source_request_member(
      @environment.source_request_at(catalog, 0).unwrap(),
    ),
  )
  let view_cid = if declarations {
    "sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f"
  } else {
    "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"
  }
  let schema_cid = if declarations {
    "sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e"
  } else {
    "sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"
  }
  let environment = @program_check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  // The independent Native SourceView/schema and declared receipt Capability
  // come from the existing real Native acceptance catalog, not a Client claim.
  let publication = "{\"environmentCid\":\"" +
    @environment.cid(wire) +
    "\",\"aliases\":[{\"name\":\"records\",\"sourceRef\":\"connector://crm/main/r#v\",\"sourceViewContractCid\":\"" +
    view_cid +
    "\",\"schemaContractCid\":\"" +
    schema_cid +
    "\"}],\"tableWrites\":[]}"
  let context = @local_input.bind_local_published_input_context(
    environment,
    publication,
    None,
  ).unwrap()
  let input = @local_input.prepare_local_input_material(
    Aql(
      "WITH acquired AS (SELECT id FROM records WHERE id > 2) FROM acquired |> EXTEND id + 1 AS value |> SELECT value |> RESULT answer",
    ),
    environment,
    None,
    Some(context),
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let account = @authorization.admit_account_configuration({
    account_id: "python-native-run-account",
    entries: [
      {
        entry_id: "run",
        outcome: Allow,
        scope: {
          principal: All,
          connection: All,
          resource: All,
          operation: All,
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  let tuple : @authorization.AccessTuple = {
    principal: "local-user",
    connection: "python.local",
    resource: "runs",
    operation: "submit",
  }
  let context_cid = "sha256:" + "a".repeat(64)
  let permit = @authorization.bind_dispatch_authorization(
    account,
    tuple,
    Activation,
    @publication_host.prepared_client_identity(
      @local_input.local_prepared_program(input),
    ).program_definition_cid,
    context_cid,
  ).unwrap()
  let plan = @local_run.prepare_captured_source_local_run(
    input,
    "sha256:" + "b".repeat(64),
    "submission-" + run_id,
    permit,
    account,
    tuple,
    context_cid,
    "sha256:" + "c".repeat(64),
    "local",
    run_id,
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  // Fixed common Owner facts only: this fixture does not perform durable I/O.
  let start = @local_run.confirm_local_run_physical_start(
    plan,
    @local_run.local_run_request(plan),
    @local_run.local_run_definition_cid(plan),
    true,
    true,
    false,
    false,
    permit,
    account,
    tuple,
    context_cid,
  ).unwrap()
  (plan, start, permit)
}

///|
fn python_native_installed_contracts() -> @client_local_host.ClientInstalledSequenceContracts raise {
  @client_local_host.prepare_installed_sequence_contracts(
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    None,
  ).unwrap()
}

///|
fn python_native_configuration(
  plan : @local_run.LocalRunPlan,
  tuple : @authorization.AccessTuple,
) -> Result[
  @local_run.LocalNativeSourceConfiguration,
  @local_run.LocalNativeSourceIssue,
] raise {
  let (query, evidence) = query_evidence_test_bodies()
  let result = @local_run.configure_local_native_source(
    plan,
    0,
    0,
    python_native_installed_contracts(),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    None,
    "main",
    "records",
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
    @identity.stringify_value(query_two_receipt_test_body(), 100000, 10000, 100),
    tuple,
    python_native_account(Allow),
    "sha256:" + "d".repeat(64),
  )
  result
}

///|
fn python_native_tuple() -> @authorization.AccessTuple {
  {
    principal: "local-user",
    connection: "local-database",
    resource: "fixture.db",
    operation: "read",
  }
}

///|
test "Local Native acquisition requires separate current subject-bound read authorization" {
  let (plan, start, run_permit) = python_native_plan("native-original")
  let read_tuple = python_native_tuple()
  let configuration = python_native_configuration(plan, read_tuple).unwrap()
  let requirement = @local_run.local_native_source_requirement(configuration)
  assert_eq(
    @planning.query_requirement_source(requirement).0,
    "connector://crm/main/r#v",
  )
  let account = python_native_account(Allow)
  let owner_read = @local_run.authorize_local_native_source(
    configuration, account,
  ).unwrap()
  assert_true(
    @local_run.authorize_local_native_source(
      configuration,
      python_native_account(Deny),
    )
    is Err(AuthorizationMismatch),
  )
  assert_true(
    @local_run.authorize_local_native_source(
      configuration,
      @authorization.admit_account_configuration({
        account_id: "another-account",
        entries: [],
        bootstrap: None,
      }).unwrap(),
    )
    is Err(AuthorizationMismatch),
  )
  let context = "sha256:" + "d".repeat(64)
  let read = @authorization.bind_dispatch_authorization(
    account,
    read_tuple,
    Acquisition,
    @planning.query_requirement_cid(requirement),
    context,
  ).unwrap()
  let observed : Array[@duckdb_query.DuckDBNativeAttempt] = []
  let host = @local_run.start_local_native_source(
    configuration,
    start,
    owner_read,
    account,
    "python-native-authorized",
    attempt => observed.any(value => physical_equal(value, attempt)),
  ).unwrap()
  // Issuance is not settlement, successful Source capture or read I/O.
  assert_true(
    @acquisition_host.complete_native_host(
      host,
      @acquisition_host.configured_native_host_limits(
        @local_run.local_native_source_configuration(configuration),
      ).completion,
    )
    is Err(_),
  )
  @acquisition_host.abort_native_host(host)
  @acquisition_host.close_native_host(host)
  assert_true(
    @local_run.start_local_native_source(
      configuration,
      start,
      run_permit,
      account,
      "activation-is-not-read",
      _ => false,
    )
    is Err(AuthorizationMismatch),
  )
  assert_true(
    @local_run.start_local_native_source(
      configuration,
      start,
      read,
      python_native_account(Deny),
      "revoked-read",
      _ => false,
    )
    is Err(AuthorizationMismatch),
  )
  for
    (tuple, subject, read_context) in [
      (
        { ..read_tuple, resource: "other.db", },
        @planning.query_requirement_cid(requirement),
        context,
      ),
      (read_tuple, "sha256:" + "e".repeat(64), context),
      (
        read_tuple,
        @planning.query_requirement_cid(requirement),
        "sha256:" + "f".repeat(64),
      ),
    ] {
    let broad = @authorization.admit_account_configuration({
      account_id: "python-native-source-account",
      entries: [
        {
          entry_id: "all",
          outcome: Allow,
          scope: {
            principal: All,
            connection: All,
            resource: All,
            operation: All,
          },
          exclusions: [],
        },
      ],
      bootstrap: None,
    }).unwrap()
    let foreign = @authorization.bind_dispatch_authorization(
      broad,
      tuple,
      Acquisition,
      subject,
      read_context,
    ).unwrap()
    assert_true(
      @local_run.start_local_native_source(
        configuration,
        start,
        foreign,
        broad,
        "foreign-read-binding",
        _ => false,
      )
      is Err(AuthorizationMismatch),
    )
  }
}

///|
test "Local single Source plans its retained suffix before physical acquisition" {
  let (plan, _, _) = python_native_plan("native-capacity-before-io")
  let configuration = python_native_configuration(plan, python_native_tuple()).unwrap()
  let selected = @local_run.local_native_source_configuration(configuration)
  let registry = @identity.stringify_value(
    registered_body(),
    100000,
    10000,
    100,
  )
  let values = @identity.stringify_value(
    registered_values(),
    100000,
    10000,
    100,
  )
  let fragment = Some(
    @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
  )
  let installed = @client_local_host.prepare_installed_sequence_contracts(
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let planned = @client_local_host.single_captured_local_ledger_limits(
    @local_run.local_run_prepared(plan),
    selected,
    installed,
    values,
    fragment,
    None,
  ).unwrap()
  assert_true(planned.retained_bytes > 200000000L)
  assert_true(planned.retained_bytes <= 536870912L)
  assert_eq(planned.execution_bytes, 536870912L)
  // Invalid installed contracts do not produce a fabricated fitting plan.
  assert_true(
    @client_local_host.prepare_installed_sequence_contracts(
      "{}",
      values,
      fragment,
      None,
    )
    is Err(_),
  )
  assert_true(
    @client_local_host.single_captured_local_ledger_limits(
      @local_run.local_run_prepared(plan),
      selected,
      installed,
      "{}",
      fragment,
      None,
    )
    is None,
  )
}

///|
test "Local Native Source configuration cannot substitute caller operation or original Run start" {
  let (plan, _, _) = python_native_plan("first-native-run")
  let (_, foreign_start, _) = python_native_plan("second-native-run")
  for
    tuple in [
      { ..python_native_tuple(), principal: "other-user", },
      { ..python_native_tuple(), operation: "submit", },
    ] {
    assert_true(
      python_native_configuration(plan, tuple) is Err(InvalidReadBinding),
    )
  }
  let configuration = python_native_configuration(plan, python_native_tuple()).unwrap()
  let account = python_native_account(Allow)
  let read = @authorization.bind_dispatch_authorization(
    account,
    python_native_tuple(),
    Acquisition,
    @planning.query_requirement_cid(
      @local_run.local_native_source_requirement(configuration),
    ),
    "sha256:" + "d".repeat(64),
  ).unwrap()
  assert_true(
    @local_run.start_local_native_source(
      configuration,
      foreign_start,
      read,
      account,
      "foreign-original-start",
      _ => false,
    )
    is Err(ForeignRunStart),
  )
}

///|
test "Local Native Source does not invent missing registered receipt Capabilities" {
  let (plan, _, _) = python_native_plan(
    "undeclared-native-source",
    declarations=false,
  )
  assert_true(
    python_native_configuration(plan, python_native_tuple())
    is Err(Configuration(Candidate)),
  )
}

///|
test "Native Source capability identifies the independently pinned current two-receipt contract" {
  let (plan, _, _) = python_native_plan("receipt-capability-control")
  let requirement = @client_local_host.prepare_local_query_requirement(
    @local_run.local_run_prepared(plan),
    0,
    0,
    python_native_installed_contracts(),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    None,
  ).unwrap()
  let context = @acquisition_host.prepare_native_source_evidence_context(
    requirement,
  ).unwrap()
  assert_true(
    @acquisition_host.source_evidence_context_supports(
      context, "sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929",
    ),
  )
  assert_false(
    @acquisition_host.source_evidence_context_supports(
      context, "sha256:db7ce19477afd82a8488a9f64fd75697c850eaaccdc738995483cc138a06361a",
    ),
  )
}
