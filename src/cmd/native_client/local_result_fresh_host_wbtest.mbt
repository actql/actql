///|
// Explicit independent Program and row order. No Source, Model or Effect.
let result_fresh_host_program : String =
  #|{"version":"actql/0.1","id":"result-fresh-host","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}

///|
fn result_fresh_host_write(
  root : @local_filesystem.Root,
  name : String,
  wire : String,
) -> Unit raise {
  let writer = effect_finite_cli_ok(
    root.create_writer(name + ".stage", 65536L),
    "fresh.input.writer",
  )
  effect_finite_cli_ok(writer.append(@utf8.encode(wire)), "fresh.input.append")
  effect_finite_cli_ok(writer.seal(name), "fresh.input.seal") |> ignore
}

///|
fn result_fresh_host_marker(value : String) -> Unit raise {
  let bytes = @utf8.encode(value + "\n")
  assert_true(write_stdout_ffi(bytes, bytes.length()))
}

///|
test "public Result reads actual published Values from a fresh Host and preserves the original after reopen" {
  // Real-clock execution selects the existing normal 24-hour TTL only for this
  // fresh installation. Controlled-time historical fixtures retain 100ms.
  let (host, settings, crypto, _) = effect_finite_cli_host(
    "public-result-fresh-host",
    ttl_ms=86400000.0,
    observed_at=local_utc_now(),
  )
  defer host.close() |> ignore
  let sqlite = effect_finite_cli_ok(
    @local_sqlite.load_library(settings.sqlite_library),
    "fresh.sqlite",
  )
  let scope = effect_finite_cli_ok(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
    "fresh.scope",
  )
  let epoch = effect_finite_cli_ok(host.epoch_authority(), "fresh.epoch")
  let reference = effect_finite_cli_ok(
    @local_host.prepare_native_client_submission_reference(
      effect_finite_cli_ok(
        epoch.issue_epoch(
          scope,
          local_submit_allowed(host, settings, crypto, scope),
          @env.now().to_double(),
        ),
        "fresh.epoch.issue",
      ),
      "public-result-fresh",
    ),
    "fresh.reference",
  )
  // The expected Run identity is selected from the original reference before
  // start. It is never inferred from a returned payload or an index flag.
  let run_id = @local_host.native_client_submission_request_id(reference)
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(settings.managed_root),
    "fresh.inputs",
  )
  result_fresh_host_write(files, "program.json", result_fresh_host_program)
  result_fresh_host_write(
    files,
    "submission.json",
    @local_host.native_client_submission_reference_wire(reference),
  )
  effect_finite_cli_ok(files.close(), "fresh.inputs.close")
  let assets = @run_host.client_local_product_assets()
  let environment_object = effect_finite_cli_ok(
    @decode.open_object(local_input_cursor(assets.environment)),
    "fresh.environment.object",
  )
  let evidence = run_text(environment_object, "evidence_bundle_cid")
  let environment = request_lookup_some(
    @run_host.admit_client_check_environment(
      assets.environment,
      evidence,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ),
    "fresh.environment.admission",
  )
  guard command().parse(
      argv=[
        "--mode", "local", "start", "--program-file", "program.json", "--submission-ref-file",
        "submission.json", "--operation-attempt-id", "public-result-first-start",
        "--request-id", "public-result-fresh",
      ],
      env=Map([]),
    ).subcommand
    is Some(("start", start)) else {
    fail("fresh.start.grammar")
  }
  let reply = local_submission_start(
    host,
    settings,
    crypto,
    sqlite,
    environment,
    settings.managed_root,
    "start",
    start,
  ) catch {
    ClientStop(kind) => fail("fresh.start: " + kind)
  }
  let reply = effect_finite_cli_ok(
    @decode.open_object(local_input_cursor(reply)),
    "fresh.start.reply",
  )
  assert_eq(run_text(reply, "kind"), "local_run_published")
  let original = effect_finite_cli_ok(
    host.lookup_submitted_run_original_by_id(
      crypto,
      settings.principal,
      settings.connection,
      run_id,
    ),
    "fresh.original",
  )
  let saved = effect_finite_cli_ok(
    host.lookup_submitted_run_state(
      crypto,
      settings.principal,
      settings.connection,
      original.reference(),
      original.request(),
      @env.now().to_double(),
    ),
    "fresh.saved",
  )
  let saved_wire = saved.wire()
  let result = result_command_child(["--mode", "local", "result", run_id])
  result_fresh_host_marker("ACTQL_PUBLIC_RESULT_BEGIN")
  let _ = local_public_result(host, settings, crypto, sqlite, result) catch {
    ClientStop(kind) => fail("fresh.result: " + kind)
  }
  result_fresh_host_marker("ACTQL_PUBLIC_RESULT_END")
  effect_finite_cli_ok(host.close(), "fresh.host.close")
  // Read only the same saved original after an actual close/reopen; never
  // resubmit, prepare, dispatch or repeat the payload read to heal Unknown.
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
      ),
      "fresh.reopen.adoption",
    ).open_journal(
      sqlite,
      crypto,
      settings.ttl_ms,
      settings.record_limit,
      settings.snapshot_bytes,
    ),
    "fresh.reopen.journal",
  )
  defer reopened.close() |> ignore
  let restored = effect_finite_cli_ok(
    reopened.lookup_submitted_run_state(
      crypto,
      settings.principal,
      settings.connection,
      original.reference(),
      original.request(),
      @env.now().to_double(),
    ),
    "fresh.reopen.saved",
  )
  assert_eq(restored.wire(), saved_wire)
  effect_finite_cli_ok(reopened.close(), "fresh.reopen.close")
}
