///|
fn agent_test_cid(character : String) -> String {
  "sha256:" + character
}

///|
fn agent_required_env(name : String) -> String? {
  @env.get_env_var(name)
}

///|
test "outbound agent observes durable acceptance before one execution" {
  guard agent_required_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard agent_required_env("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY")
    is Some(crypto_path) else {
    return
  }
  guard agent_required_env("ACTQL_TEST_NATIVE_REMOTE_AGENT_ROOT")
    is Some(root_path) else {
    return
  }
  guard agent_required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET")
    is Some(target) else {
    return
  }
  guard agent_required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY")
    is Some(public_key) else {
    return
  }
  guard agent_required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY")
    is Some(bundle_body) else {
    return
  }
  guard agent_required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID")
    is Some(bundle_cid) else {
    return
  }
  guard agent_required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE")
    is Some(signature) else {
    return
  }
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let crypto = @signature.load_library(crypto_path).unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let component = b"native-runtime"
  let writer = root
    .create_writer("agent-stage", component.length().to_int64())
    .unwrap()
  writer.append(component).unwrap()
  let generation = writer.seal("agent-component").unwrap()
  let bundles = @bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    root_path,
    [
      {
        issuer_authority: "bundle-authority-a",
        key_id: "key-a",
        public_key_pem: public_key,
      },
    ],
    target,
    component.length().to_int64(),
    4,
    8,
    262144L,
  ).unwrap()
  bundles
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1", "key-a", bundle_cid, bundle_body,
    signature, "agent-component", generation,
  )
  .unwrap()
  |> ignore
  bundles.activate(bundle_cid).unwrap() |> ignore
  let active_runtime = bundles
    .acquire_active_component(
      "sha256:" + @sha.hex(component),
      target,
      "runtime-process:native-agent-test",
    )
    .unwrap()
  let site = @site.create_site(
    "native-agent-site", 1, bundle_cid, 2, 2, 1024L, 1024L,
  ).unwrap()
  let journal = @journal.open_journal(
    sqlite,
    root_path + "/agent-journal.sqlite3",
    262144L,
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let operation_capability = agent_test_cid(
    "4444444444444444444444444444444444444444444444444444444444444444",
  )
  let issuer_capability = agent_test_cid(
    "5555555555555555555555555555555555555555555555555555555555555555",
  )
  let executions = [0]
  let executor = @runtime.install_native_remote_task_executor(
    agent_test_cid(
      "0000000000000000000000000000000000000000000000000000000000000000",
    ),
    "task-agent",
    (_request, _binding, _budget) => {
      executions[0] += 1
      let measurement = @remote.prepare_remote_managed_output_measurement(
        1,
        1,
        1,
        1,
        [1],
        [1],
        [1],
        [1],
        [0],
        [1],
      ).unwrap()
      let schema_cid = agent_test_cid(
        "8888888888888888888888888888888888888888888888888888888888888888",
      )
      let view_cid = agent_test_cid(
        "9999999999999999999999999999999999999999999999999999999999999999",
      )
      let codec_cid = agent_test_cid(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      )
      let physical_manifest = @manifest.admit(
        "actql-managed-physical-manifest/0.1",
        schema_cid,
        view_cid,
        codec_cid,
        1,
        ["sha256:" + @sha.hex(b"x")],
        [1L],
        [1],
        1,
        1024,
        1L,
      ).unwrap()
      @runtime.prepare_native_remote_output(
        {
          material_generation: "native-agent-material",
          managed_profile_cid: agent_test_cid(
            "7777777777777777777777777777777777777777777777777777777777777777",
          ),
          result_schema_cid: schema_cid,
          logical_view_cid: view_cid,
          representation_codec_cid: codec_cid,
          physical_manifest,
          row_count: 1,
          retained_bytes: 1L,
          measurement,
        },
        () => {
          let emitted = [false]
          Ok(
            @runtime.prepare_native_remote_physical_reader(
              _max_bytes => {
                if emitted[0] {
                  Ok({ bytes: b"", eof: true, })
                } else {
                  emitted[0] = true
                  Ok({ bytes: b"x", eof: true, })
                }
              },
              () => Ok(()),
              () => Ok(()),
            ),
          )
        },
        () => {
          let emitted = [false]
          Ok(
            @runtime.prepare_native_remote_physical_manifest_reader(
              index => {
                if index != 0 || emitted[0] {
                  Err("invalid-manifest-read")
                } else {
                  emitted[0] = true
                  Ok(b"x")
                }
              },
              () => if emitted[0] { Ok(()) } else { Err("incomplete") },
              () => Ok(()),
            ),
          )
        },
        () => true,
      ).unwrap()
    },
  ).unwrap()
  let registration = @runtime.install_native_remote_runtime_registry_registration(
    site,
    active_runtime,
    operation_capability,
    issuer_capability,
    [executor],
  ).unwrap()
  let runtime = @runtime.open_native_remote_runtime(
    journal,
    bundles,
    [registration],
    [budget],
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let request = @remote.prepare_dispatch_request(
    "native-coordinator",
    agent_test_cid(
      "0000000000000000000000000000000000000000000000000000000000000000",
    ),
    "task-agent",
    1,
    "dispatch-agent",
    "native-agent-site",
    1,
    bundle_cid,
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_input_binding_cid(binding),
    agent_test_cid(
      "2222222222222222222222222222222222222222222222222222222222222222",
    ),
    @remote.remote_dispatch_budget_cid(budget),
    issuer_capability,
    operation_capability,
  ).unwrap()
  let dispatch = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_dispatch_json(request, binding).unwrap(),
  ).unwrap()
  let acceptance_attempts = [0]
  let status_attempts = [0]
  let reject_acceptance = fn(request) {
    acceptance_attempts[0] += 1
    journal.accept(request).unwrap() |> ignore
    Err(@client.Closed)
  }
  let report_status = fn(request) {
    status_attempts[0] += 1
    match journal.observation(request) {
      Ok(observation) =>
        Ok(Some(@journal.recovered_site_dispatch_record(observation)))
      Err(@journal.MissingDispatch) => Ok(None)
      Err(issue) => Err(@client.Journal(issue))
    }
  }
  assert_true(
    @agent.advance_native_outbound_operation(
      runtime,
      Some(dispatch),
      reject_acceptance,
      report_status,
    )
    is Err(@agent.Client(@client.Closed)),
  )
  assert_eq(executions[0], 0)
  assert_eq(status_attempts[0], 0)
  let foreign = @remote.prepare_dispatch_request(
    "native-coordinator",
    agent_test_cid(
      "0000000000000000000000000000000000000000000000000000000000000000",
    ),
    "task-agent-foreign",
    2,
    "dispatch-agent-foreign",
    "native-agent-site",
    1,
    bundle_cid,
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_input_binding_cid(binding),
    agent_test_cid(
      "2222222222222222222222222222222222222222222222222222222222222222",
    ),
    @remote.remote_dispatch_budget_cid(budget),
    issuer_capability,
    operation_capability,
  ).unwrap()
  let accept_foreign = fn(_request) {
    acceptance_attempts[0] += 1
    let (_, record) = journal.accept(foreign).unwrap()
    Ok(record)
  }
  assert_true(
    @agent.advance_native_outbound_operation(
      runtime,
      Some(dispatch),
      accept_foreign,
      report_status,
    )
    is Err(@agent.ObservationMismatch),
  )
  assert_eq(executions[0], 0)
  assert_eq(status_attempts[0], 0)
  let accept = fn(request) {
    acceptance_attempts[0] += 1
    let (_, record) = journal.accept(request).unwrap()
    Ok(record)
  }
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(dispatch),
      accept,
      report_status,
    )
    is Ok(@agent.DispatchObserved(observed_request, completion, revision)) else {
    fail("dispatch was not observed")
  }
  assert_eq(
    @remote.dispatch_request_identity(observed_request),
    @remote.dispatch_request_identity(request),
  )
  assert_eq(
    completion.dispatch_request_cid,
    @remote.dispatch_request_identity(request),
  )
  assert_true(revision > 0)
  assert_eq(executions[0], 1)
  assert_eq(status_attempts[0], 1)
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(dispatch),
      accept,
      report_status,
    )
    is Ok(@agent.DispatchObserved(_, _, _)) else {
    fail("exact resend was not reconciled")
  }
  assert_eq(executions[0], 1)
  assert_eq(acceptance_attempts[0], 4)
  assert_eq(status_attempts[0], 2)
  let query = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_query_json(request).unwrap(),
  ).unwrap()
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(query),
      accept,
      report_status,
    )
    is Ok(@agent.QueryObserved(_, _)) else {
    fail("query was not reconciled")
  }
  assert_eq(executions[0], 1)
  assert_eq(acceptance_attempts[0], 4)
  assert_eq(status_attempts[0], 3)
  let report_foreign = fn(_request) {
    let observation = journal.observation(foreign).unwrap()
    Ok(Some(@journal.recovered_site_dispatch_record(observation)))
  }
  assert_true(
    @agent.advance_native_outbound_operation(
      runtime,
      Some(query),
      accept,
      report_foreign,
    )
    is Err(@agent.ObservationMismatch),
  )
  assert_eq(executions[0], 1)
  let lose_status = fn(_request) { Err(@client.Closed) }
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(dispatch),
      accept,
      lose_status,
    )
    is Err(@agent.CompletionObservationUnknown(completion, @client.Closed)) else {
    fail("lost terminal observation was not preserved")
  }
  assert_eq(
    completion.dispatch_request_cid,
    @remote.dispatch_request_identity(request),
  )
  assert_eq(executions[0], 1)
  let output_intent = @remote.prepare_remote_output_intent(request, {
    store_authority_cid: agent_test_cid(
      "6666666666666666666666666666666666666666666666666666666666666666",
    ),
    publication_attempt_cid: agent_test_cid(
      "7777777777777777777777777777777777777777777777777777777777777777",
    ),
    result_definition_cid: agent_test_cid(
      "8888888888888888888888888888888888888888888888888888888888888888",
    ),
    ordering_evidence_cid: agent_test_cid(
      "9999999999999999999999999999999999999999999999999999999999999999",
    ),
    coordinator_authority: "native-coordinator",
    transfer_attempt: "transfer-agent-output",
    transfer_route: @transfer.DirectStream,
    destination_site_key: "native-destination-site",
    destination_site_generation: 3,
    transfer_max_bytes: 128L,
    transfer_expires_unix_ms: 2000000000000L,
    source_grant_cid: agent_test_cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    destination_grant_cid: agent_test_cid(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
    route_capability_cid: agent_test_cid(
      "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    ),
    transfer_origin: "https://destination.example.invalid/transfer",
  }).unwrap()
  let output_plan = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_output_plan_json(request, output_intent).unwrap(),
  ).unwrap()
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(output_plan),
      accept,
      report_status,
    )
    is Ok(@agent.OutputPlanRequested(plan_request)) else {
    fail("output planning was not returned to the application owner")
  }
  assert_eq(
    @remote.remote_output_intent_identity(
      @remote.remote_poll_output_intent(plan_request),
    ),
    @remote.remote_output_intent_identity(output_intent),
  )
  let output = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_output_json(request, output_intent).unwrap(),
  ).unwrap()
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(output),
      accept,
      report_status,
    )
    is Ok(@agent.OutputRequested(output_request)) else {
    fail("output operation was not returned to the application owner")
  }
  assert_eq(
    @remote.remote_output_intent_identity(
      @remote.remote_poll_output_intent(output_request),
    ),
    @remote.remote_output_intent_identity(output_intent),
  )
  assert_eq(acceptance_attempts[0], 5)
  assert_eq(status_attempts[0], 3)
  let release = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_release_json(request).unwrap(),
  ).unwrap()
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(release),
      accept,
      report_status,
    )
    is Ok(@agent.ReleaseObserved(release_identity, release_revision)) else {
    fail("release was not observed")
  }
  assert_eq(release_identity, @remote.dispatch_request_identity(request))
  assert_true(release_revision > revision)
  guard @agent.advance_native_outbound_operation(
      runtime,
      Some(release),
      accept,
      report_status,
    )
    is Ok(@agent.ReleaseObserved(_, exact_retry_revision)) else {
    fail("released output was not reconciled")
  }
  assert_eq(exact_retry_revision, release_revision)
  assert_eq(executions[0], 1)
  assert_true(runtime.close().unwrap())
  assert_false(bundles.release("runtime-process:native-agent-test").unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}
