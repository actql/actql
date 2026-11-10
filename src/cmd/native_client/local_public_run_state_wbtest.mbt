///|
let public_run_result_program : String =
  #|{"version":"actql/0.1","id":"public-run-result","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}

///|
fn public_run_state_status(run_id : String) -> @argparse.Matches raise {
  let parsed = command().parse(
    argv=["--mode", "local", "status", run_id, "--json"],
    env=Map([]),
  )
  normalize_native_status_arguments(parsed)
  parsed.subcommand.unwrap().1
}

///|
test "public run returns the original portable State and Result across Host reopen" {
  let (host, settings, crypto, _) = effect_finite_cli_host(
    "public-run-result",
    ttl_ms=86400000.0,
    observed_at=local_utc_now(),
    managed_root=true,
  )
  defer host.close() |> ignore
  let sqlite = effect_finite_cli_ok(
    @local_sqlite.load_library(settings.sqlite_library),
    "public.sqlite",
  )
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(settings.managed_root),
    "public.inputs",
  )
  result_fresh_host_write(files, "program.json", public_run_result_program)
  effect_finite_cli_ok(files.close(), "public.inputs.close")
  let assets = @run_host.client_local_product_assets()
  let environment = request_lookup_some(
    @run_host.admit_client_check_environment(
      assets.environment,
      run_text(
        effect_finite_cli_ok(
          @decode.open_object(local_input_cursor(assets.environment)),
          "public.environment",
        ),
        "evidence_bundle_cid",
      ),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ),
    "public.environment.admission",
  )
  let parsed = command().parse(
    argv=[
      "--mode", "local", "run", "program.json", "--format", "json", "--json",
    ],
    env=Map([]),
  )
  normalize_native_program_arguments(parsed)
  let child = parsed.subcommand.unwrap().1
  for field in ["submission-ref-file", "operation-attempt-id", "request-id"] {
    assert_eq(optional(child, field), None)
  }
  let state = local_submission_start(
    host,
    settings,
    crypto,
    sqlite,
    environment,
    settings.managed_root,
    local_run_original_operation(),
    child,
    public_run=true,
  ) catch {
    ClientStop(kind) => fail("public.run: " + kind)
  }
  assert_eq(local_run_reply(child, state), state)
  let body = effect_finite_cli_ok(
    @decode.open_object(local_input_cursor(state)),
    "public.state",
  )
  assert_eq(run_text(body, "version"), "actql-run-state/0.1")
  assert_eq(run_text(body, "status"), "succeeded")
  let run_id = run_text(body, "run_id")
  let revision = effect_finite_cli_ok(
    @decode.safe_integer(
      request_lookup_some(@decode.lookup(body, "revision"), "public.revision"),
    ),
    "public.revision.integer",
  )
  assert_true(revision >= 0L)
  // Rejoin the returned ID to this actual Journal's authenticated original.
  // The independent expected intent CID is fixed below before execution.
  let original = effect_finite_cli_ok(
    host.lookup_submitted_run_original_by_id(
      crypto,
      settings.principal,
      settings.connection,
      run_id,
    ),
    "public.original",
  )
  assert_eq(
    @local_host.native_client_submission_request_id(original.reference()),
    run_id,
  )
  let scope = effect_finite_cli_ok(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
    "public.scope",
  )
  let observed = effect_finite_cli_ok(
    effect_finite_cli_ok(host.run_journal(), "public.journal").lookup_submitted_intent(
      effect_finite_cli_ok(host.epoch_authority(), "public.epoch"),
      original.reference(),
      scope,
      local_submit_allowed(host, settings, crypto, scope),
      @env.now().to_double(),
    ),
    "public.intent",
  )
  guard observed is Submitted(retained) else { fail("public.intent.missing") }
  assert_eq(
    @run_host.client_submitted_intent_cid(
      @local_host.native_client_submitted_intent(retained),
    ),
    public_run_result_expected_intent,
  )
  let before = effect_finite_cli_ok(
    host.lookup_submitted_run_state_by_id(
      crypto,
      settings.principal,
      settings.connection,
      run_id,
      @env.now().to_double(),
    ),
    "public.before",
  )
  assert_eq(before.state().wire(), state)
  let status = public_run_state_status(run_id)
  let observed = local_saved_run_status(
    host,
    settings,
    crypto,
    "must-not-open",
    status,
    human_display=Some(_ => stop("JSONMustNotReadPrivatePreview")),
  ) catch {
    ClientStop(kind) => fail("public.status: " + kind)
  }
  assert_eq(observed, state)
  let watch = command().parse(
    argv=[
      "--mode", "local", "status", run_id, "--watch", "--until", "final", "--timeout",
      "30s", "--json",
    ],
    env=Map([]),
  )
  normalize_native_status_arguments(watch)
  let watched = local_saved_run_status_command(
    host,
    settings,
    crypto,
    "must-not-open",
    watch.subcommand.unwrap().1,
    human_display=Some(_ => stop("JSONWatchMustNotReadPrivatePreview")),
  ) catch {
    ClientStop(kind) => fail("public.watch: " + kind)
  }
  assert_eq(watched, state)
  let human_status = command().parse(
    argv=["--mode", "local", "status", run_id],
    env=Map([]),
  )
  normalize_native_status_arguments(human_status)
  let human = local_saved_run_status(
    host,
    settings,
    crypto,
    "must-not-open",
    human_status.subcommand.unwrap().1,
  ) catch {
    ClientStop(kind) => fail("public.human-status: " + kind)
  }
  assert_eq(human, local_run_state_display(state).unwrap())
  assert_true(human.contains("State: \"succeeded\"\n"))
  assert_true(human.contains("Result \"answer\": \"unknown\"\n"))
  assert_true(human.contains("Reason: \"verification_pending\"\n"))
  let legacy = command().parse(
      argv=["--mode", "local", "status", "--run-id", run_id, "--json"],
      env=Map([]),
    ).subcommand.unwrap().1
  let legacy_wire = local_saved_run_status(
    host, settings, crypto, "must-not-open", legacy,
  ) catch {
    ClientStop(kind) => fail("public.legacy-status: " + kind)
  }
  assert_eq(
    run_text(
      effect_finite_cli_ok(
        @decode.open_object(local_input_cursor(legacy_wire)),
        "public.legacy.body",
      ),
      "kind",
    ),
    "local_saved_run_state",
  )
  result_fresh_host_marker("ACTQL_PUBLIC_RUN_RESULT_BEGIN")
  let result_child = result_command_child(["result", run_id])
  let _ = local_public_result(host, settings, crypto, sqlite, result_child) catch {
    ClientStop(kind) => fail("public.result: " + kind)
  }
  result_fresh_host_marker("ACTQL_PUBLIC_RUN_RESULT_END")
  effect_finite_cli_ok(host.close(), "public.host.close")
  let reopened = effect_finite_cli_ok(
    effect_finite_cli_ok(
      @local_host.begin_native_local_host_adoption(
        settings.state_parent,
        settings.state_name,
        settings.managed_root,
        settings.account_file,
        settings.account_id,
        crypto,
        existing_only=true,
        configuration_files=settings.installation_files,
        managed_root_path=Some(settings.managed_root),
      ),
      "public.reopen.adoption",
    ).open_journal(
      sqlite,
      crypto,
      settings.ttl_ms,
      settings.record_limit,
      settings.snapshot_bytes,
    ),
    "public.reopen",
  )
  defer reopened.close() |> ignore
  let restored = effect_finite_cli_ok(
    reopened.lookup_submitted_run_state_by_id(
      crypto,
      settings.principal,
      settings.connection,
      run_id,
      @env.now().to_double(),
    ),
    "public.restored",
  )
  assert_eq(restored.state().wire(), state)
  assert_eq(
    restored.state().control_revision(),
    before.state().control_revision(),
  )
  assert_eq(
    local_saved_run_status(reopened, settings, crypto, "must-not-open", status) catch {
      ClientStop(kind) => fail("public.reopen.status: " + kind)
    },
    state,
  )
  effect_finite_cli_ok(reopened.close(), "public.reopen.close")
}

///|
test "public run cannot turn a legacy success-shaped reply into a missing original State" {
  let (host, settings, crypto) = request_lookup_fixture(
    "public-run-state-missing",
  )
  defer host.close() |> ignore
  let (reference, _, _, _) = request_lookup_original(
    host, settings, crypto, "missing",
  )
  let invented = "{\"status\":\"succeeded\",\"revision\":0}"
  let refusal = local_public_run_state_reply(
    host, settings, crypto, reference, true, invented,
  ) catch {
    ClientStop(kind) => kind
  }
  effect_finite_cli_ok(host.close(), "missing.close")
  assert_eq(refusal, "LocalOriginalRunStateUnavailable")
  assert_eq(
    local_public_run_state_reply(
      host, settings, crypto, reference, false, invented,
    ),
    invented,
  )
}

///|
test "public run response requires current RunRead independently of submit" {
  let (host, settings, crypto) = request_lookup_fixture(
    "public-run-state-denied",
    read=false,
  )
  defer host.close() |> ignore
  let (reference, _, _, _) = request_lookup_original(
    host, settings, crypto, "denied",
  )
  let refusal = local_public_run_state_reply(
    host, settings, crypto, reference, true, "old-reply",
  ) catch {
    ClientStop(kind) => kind
  }
  effect_finite_cli_ok(host.close(), "denied.close")
  assert_eq(refusal, "LocalRunStateReadAuthorizationDenied")
}

///|
// Independent Python hashlib vector for the documented original intent preimage.
let public_run_result_expected_intent : String = "sha256:bda82aa214741da903ca2fca5147a37dbd86040fdaef725dc651afdfaacd6892"
