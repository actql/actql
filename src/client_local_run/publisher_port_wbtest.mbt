///|
fn publisher_account(
  publish : @authorization.ConfiguredOutcome,
  principal? : String = "local-user",
  connection? : String = "python.local",
  account_id? : String = "local-account",
  publish_entry_id? : String = "publication",
) -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration({
    account_id,
    entries: [
      {
        entry_id: "submission",
        outcome: Allow,
        scope: {
          principal: All,
          connection: AnyOf(["python.local"]),
          resource: AnyOf(["runs"]),
          operation: AnyOf(["submit"]),
        },
        exclusions: [],
      },
      {
        entry_id: publish_entry_id,
        outcome: publish,
        scope: {
          principal: AnyOf([principal]),
          connection: AnyOf([connection]),
          resource: AnyOf(["run"]),
          operation: AnyOf(["publish"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
}

///|
fn account_publisher_preflight(
  original : @authorization.AdmittedAccountConfiguration,
  policy? : String = original.configuration_cid(),
  target? : String = "sha256:" + "4".repeat(64),
  namespace_id? : String = "local-results",
) -> (LocalComputeHost, LocalPublicationPreflight) raise {
  let input = prepared(@input.Aql("SELECT 1 AS n"))
  let plan = prepare_source_free_local_publication_run(
    input,
    "sha256:" + "b".repeat(64),
    "original-submission",
    permit(input, original),
    original,
    tuple(),
    context_cid(),
    "sha256:" + "c".repeat(64),
    "local",
    "original-policy-run",
    "2026-10-12T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
    (source_free_original_policy_cid, source_free_original_policy),
  ).unwrap()
  let host = source_free_shared_host(plan, source_free_root()).unwrap()
  let invocation = issue_local_source_free_invocation(
    host,
    compute_start(host),
    original,
  ).unwrap()
  let intent = prepare_local_publication_intent(
    plan,
    namespace_id,
    policy,
    target,
    "2026-10-12T00:00:00.000Z",
    "original-attempt",
    "sha256:" + "5".repeat(64),
    None,
    "2026-10-12T00:00:01.000Z",
    {
      max_results: 2,
      max_wire_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    },
  ).unwrap()
  (
    host,
    check_local_publication_preflight(intent, invocation, original, [
      source_free_retention(),
    ]).unwrap(),
  )
}

///|
fn close_account_publisher_fixture(host : LocalComputeHost) -> Unit {
  @strategy.stop_captured_dag(local_compute_run(host))
  @strategy.refresh_captured_retention(local_compute_run(host))
}

///|
test "Account publisher binds original policy and private Store without execution or ACK" {
  let original = publisher_account(Allow)
  let (host, preflight) = account_publisher_preflight(original)
  let facts : Array[@publication.PublicationPublisherAuthorization] = []
  let store = "sha256:" + "4".repeat(64)
  let port = install_local_preflight_publisher_port(
    preflight,
    store,
    original,
    () => original,
    () => true,
    fact => {
      facts.push(fact)
      true
    },
  ).unwrap()
  assert_eq(facts.length(), 0)
  let (request, attempt) = local_publication_preflight_contracts(preflight)
  let before = @publication.publication_contract_json(request)
  port.check(request, attempt, store, @publication.Request, None).unwrap()
  assert_eq(facts, [
    {
      stage: "request",
      namespace_id: "local-results",
      authority_scope_cid: "sha256:" + "b".repeat(64),
      run_definition_cid: local_run_definition_cid(preflight.intent.plan),
      publication_request_cid: @publication.publication_contract_identity(
        request,
      ),
      public_index_entry_cid: None,
    },
  ])
  assert_eq(@publication.publication_contract_json(request), before)
  assert_false(@strategy.captured_task_completed(local_compute_run(host), 0))
  assert_false(
    @strategy.captured_task_activation_granted(local_compute_run(host), 0),
  )
  assert_eq(
    @resources.ledger_usage(
      @strategy.captured_dag_ledger(local_compute_run(host)),
    ).attempts,
    0,
  )
  close_account_publisher_fixture(host)
}

///|
test "Run submit Allow never supplies publication permission" {
  for original in [account(Allow), publisher_account(Deny)] {
    let (host, preflight) = account_publisher_preflight(original)
    let callbacks = Ref(0)
    assert_true(
      install_local_preflight_publisher_port(
        preflight,
        "sha256:" + "4".repeat(64),
        original,
        () => publisher_account(Allow),
        () => true,
        _ => {
          callbacks.val += 1
          true
        },
      )
      is Err(@publication.AccessDenied),
    )
    assert_eq(callbacks.val, 0)
    close_account_publisher_fixture(host)
  }
}

///|
test "Publisher original CID and Store target cannot be repaired by current config" {
  let original = publisher_account(Allow)
  let callbacks = Ref(0)
  for
    (policy, target, other, expected) in [
      (
        "sha256:" + "3".repeat(64),
        "sha256:" + "4".repeat(64),
        original,
        @publication.ReferenceMismatch,
      ),
      (
        original.configuration_cid(),
        "sha256:" + "6".repeat(64),
        original,
        @publication.InvalidStore,
      ),
      (
        original.configuration_cid(),
        "sha256:" + "4".repeat(64),
        publisher_account(Allow, account_id="foreign-account"),
        @publication.ReferenceMismatch,
      ),
    ] {
    let (host, preflight) = account_publisher_preflight(
      original,
      policy~,
      target~,
    )
    assert_true(
      install_local_preflight_publisher_port(
        preflight,
        "sha256:" + "4".repeat(64),
        other,
        () => original,
        () => true,
        _ => {
          callbacks.val += 1
          true
        },
      )
      is Err(issue) &&
      issue == expected,
    )
    close_account_publisher_fixture(host)
  }
  assert_eq(callbacks.val, 0)
}

///|
test "Publisher tuple preserves original principal and connection" {
  for
    original in [
      publisher_account(Allow, principal="foreign-user"),
      publisher_account(Allow, connection="foreign-connection"),
    ] {
    let (host, preflight) = account_publisher_preflight(original)
    assert_true(
      install_local_preflight_publisher_port(
        preflight,
        "sha256:" + "4".repeat(64),
        original,
        () => original,
        () => true,
        _ => true,
      )
      is Err(@publication.AccessDenied),
    )
    close_account_publisher_fixture(host)
  }
}

///|
test "Current publish is checked before and after callback without rewriting original" {
  let original = publisher_account(Allow)
  let (host, preflight) = account_publisher_preflight(original)
  let current = Ref(original)
  let revoke = Ref(false)
  let callbacks = Ref(0)
  let store = "sha256:" + "4".repeat(64)
  let port = install_local_preflight_publisher_port(
    preflight,
    store,
    original,
    () => current.val,
    () => true,
    _ => {
      callbacks.val += 1
      if revoke.val {
        current.val = publisher_account(Deny)
      }
      true
    },
  ).unwrap()
  let (request, attempt) = local_publication_preflight_contracts(preflight)
  let wire = @publication.publication_contract_json(request)
  for
    replacement in [
      account(Allow),
      publisher_account(Deny),
      publisher_account(Allow, principal="foreign-user"),
      publisher_account(Allow, connection="foreign-connection"),
      publisher_account(Allow, account_id="foreign-account"),
    ] {
    current.val = replacement
    assert_true(
      port.check(request, attempt, store, @publication.Request, None)
      is Err(@publication.NotCurrent),
    )
  }
  assert_eq(callbacks.val, 0)
  current.val = publisher_account(Allow, publish_entry_id="current-publication")
  assert_true(current.val.configuration_cid() != original.configuration_cid())
  port.check(request, attempt, store, @publication.Request, None).unwrap()
  assert_eq(@publication.publication_contract_json(request), wire)
  revoke.val = true
  assert_true(
    port.check(request, attempt, store, @publication.Request, None)
    is Err(@publication.NotCurrent),
  )
  assert_eq(callbacks.val, 2)
  assert_eq(@publication.publication_contract_json(request), wire)
  close_account_publisher_fixture(host)
}

///|
test "Account publisher keeps independent denial and Host fence failure distinct" {
  let original = publisher_account(Allow)
  let (host, preflight) = account_publisher_preflight(original)
  let live = Ref(true)
  let store = "sha256:" + "4".repeat(64)
  let port = install_local_preflight_publisher_port(
    preflight,
    store,
    original,
    () => original,
    () => live.val,
    _ => false,
  ).unwrap()
  let (request, attempt) = local_publication_preflight_contracts(preflight)
  assert_true(
    port.check(request, attempt, store, @publication.Request, None)
    is Err(@publication.AccessDenied),
  )
  live.val = false
  assert_true(
    port.check(request, attempt, store, @publication.Request, None)
    is Err(@publication.NotCurrent),
  )
  close_account_publisher_fixture(host)
}
