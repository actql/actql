///|
fn requested_stop_arguments(
  operation : String,
  boundary : String?,
) -> @argparse.Matches raise {
  let args = [operation, "--program-file", "literal.sql"]
  if operation != "start" {
    args.push("--format")
    args.push("sql")
  }
  if operation != "run" {
    for
      value in [
        "--submission-ref-file", "original-submission.json", "--operation-attempt-id",
        "original-attempt",
      ] {
      args.push(value)
    }
  }
  if boundary is Some(value) {
    args.push("--stop-before")
    args.push(value)
  }
  let matches = command().parse(argv=args[:], env=Map([]))
  normalize_native_program_arguments(matches)
  matches
}

///|
test "Native requested stop is an explicit closed option without a default" {
  for operation in ["run", "aql", "start"] {
    let absent = requested_stop_arguments(operation, None).subcommand.unwrap().1
    let selected = requested_stop_arguments(operation, Some("commit")).subcommand.unwrap().1
    assert_eq(native_requested_stop_before(absent), None)
    assert_eq(native_requested_stop_before(selected), Some("commit"))
  }
}

///|
test "Native requested stop rejects unsupported boundaries before project or input IO" {
  for boundary in ["", "Commit", "prepare", "none", "null", " commit"] {
    let matches = command().parse(
      argv=[
        "--mode", "local", "--config", "never-open-config.json", "run", "never-open-program.aql",
        "--stop-before", boundary,
      ],
      env=Map([]),
    )
    let issue = try {
      ignore(execute_native_project_selection(matches))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(issue, "UnsupportedStopBeforeBoundary")
    for operation in ["start", "aql"] {
      let parsed = requested_stop_arguments(operation, Some(boundary))
      let child = parsed.subcommand.unwrap().1
      let local_issue = try {
        ignore(local_intent_wire("never-open-root", operation, child))
        "unexpected success"
      } catch {
        ClientStop(message) => message
      }
      let remote_issue = try {
        ignore(
          request_body(operation, child, "never-open-root", Json::null(), 65536),
        )
        "unexpected success"
      } catch {
        ClientStop(message) => message
      }
      assert_eq(local_issue, "UnsupportedStopBeforeBoundary")
      assert_eq(remote_issue, "UnsupportedStopBeforeBoundary")
    }
  }
}

///|
test "Native requested stop binds the original intent with independent canonical vectors" {
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  let absent = local_intent_wire(
    root,
    "aql",
    requested_stop_arguments("run", None).subcommand.unwrap().1,
  )
  let selected = local_intent_wire(
    root,
    "aql",
    requested_stop_arguments("run", Some("commit")).subcommand.unwrap().1,
  )
  let original = @run_host.prepare_client_submitted_intent(
    absent, 65536, 8192, 64,
  ).unwrap()
  let requested = @run_host.prepare_client_submitted_intent(
    selected, 65536, 8192, 64,
  ).unwrap()
  assert_eq(
    @run_host.client_submitted_intent_wire(original),
    (
      #|{"input":{"format":"sql","text":"SELECT 1 AS id\n"},"kind":"aql","parameters":null}
    ),
  )
  assert_eq(
    @run_host.client_submitted_intent_wire(requested),
    (
      #|{"input":{"format":"sql","text":"SELECT 1 AS id\n"},"kind":"aql","parameters":null,"stopBefore":"commit"}
    ),
  )
  // Independent Python hashlib over the closed canonical intent/version body.
  assert_eq(
    @run_host.client_submitted_intent_cid(original),
    "sha256:7fca23f58926fa5a5e4385cd1b71ea17c9b05a7e57c7485de3726cbfe7315d77",
  )
  assert_eq(
    @run_host.client_submitted_intent_cid(requested),
    "sha256:3bd00241ad0b5101bf65c24d99dbc3745f92f872d531004c1016d209339fbc1c",
  )
  assert_false(@run_host.client_submitted_intent_requests_commit_stop(original))
  assert_true(@run_host.client_submitted_intent_requests_commit_stop(requested))
  assert_false(@run_host.client_submitted_intent_requests_read_only(requested))
}

///|
test "Native requested stop remote packet and intent CID retain the same original restriction" {
  let (context, root) = check_cli_fixture("requested-stop-packet")
  let settings = local_host_settings(
    @utf8.decode(context.configuration_body) catch {
      _ => fail("stop.configuration")
    },
  )
  let scope = public_run_scope(context.host, settings, context.crypto)
  let selection = local_select_run_submission(
    context.host,
    settings,
    context.crypto,
    scope,
    root,
    requested_stop_arguments("run", Some("commit")).subcommand.unwrap().1,
    true,
  )
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(root),
    "stop.inputs",
  )
  result_fresh_host_write(files, "literal.sql", "SELECT 1 AS id\n")
  result_fresh_host_write(files, "program.json", public_run_result_program)
  result_fresh_host_write(
    files,
    "original-submission.json",
    @local_host.native_client_submission_reference_wire(selection.reference),
  )
  effect_finite_cli_ok(files.close(), "stop.inputs.close")
  // Connection DATA is not a permission; this tests the actual request encoder.
  let connection = @json.parse(
    "{\"mode\":\"local\",\"owner\":\"local\",\"consentRefs\":[],\"runners\":[]}",
  ) catch {
    _ => fail("stop.connection")
  }
  assert_true(wire_connection_shape(connection))
  for operation in ["aql", "start"] {
    for boundary in [None, Some("commit")] {
      let child = requested_stop_arguments(operation, boundary).subcommand.unwrap().1
      if operation == "start" {
        child.values["program-file"] = ["program.json"]
      }
      let remote_bytes = request_body(operation, child, root, connection, 65536)
      let remote = @json.parse(
        @utf8.decode(remote_bytes) catch {
          _ => fail("stop.remote.utf8")
        },
      ) catch {
        _ => fail("stop.remote.json")
      }
      let local = @run_host.prepare_client_submitted_intent(
        local_intent_wire(root, operation, child),
        65536,
        8192,
        64,
      ).unwrap()
      assert_eq(
        local_explain_field(remote, "intentCid"),
        Json::string(@run_host.client_submitted_intent_cid(local)),
      )
      guard remote is Object(fields) else { fail("stop.remote.object") }
      assert_eq(fields.get("stopBefore"), boundary.map(Json::string))
      assert_eq(
        @run_host.client_submitted_intent_requests_commit_stop(local),
        boundary is Some(_),
      )
      if operation == "aql" && boundary is Some(_) {
        assert_eq(
          fields.get("intentCid"),
          Some(
            Json::string(
              "sha256:3bd00241ad0b5101bf65c24d99dbc3745f92f872d531004c1016d209339fbc1c",
            ),
          ),
        )
      }
    }
  }
  effect_finite_cli_ok(context.host.close(), "stop.host.close")
}

///|
test "Native requested stop survives original preparation refusal and actual Host restart" {
  let name = "requested-stop-restart"
  let (host, settings, crypto) = request_lookup_fixture(name, ttl_ms=60000.0)
  let child = requested_stop_arguments("run", Some("commit")).subcommand.unwrap().1
  let input_root = @env.current_dir().unwrap() +
    "/scripts/fixtures/native-local-cli"
  let failure = try {
    ignore(
      local_submission_start(
        host,
        settings,
        crypto,
        request_lookup_ok(
          @local_sqlite.load_library(settings.sqlite_library),
          "stop.sqlite",
        ),
        explain_fixture_environment(),
        input_root,
        "aql",
        child,
        public_run=true,
      ),
    )
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  let parts = failure.split(" originalSubmissionRequestId=").to_array()
  guard parts.get(1) is Some(correlation) &&
    correlation.split(" ").next() is Some(id) else {
    fail("stop.original.correlation")
  }
  let id = id.to_owned()
  let reference = request_lookup_some(
    request_lookup_ok(
      host.lookup_submission_reference_by_request_id(
        crypto,
        settings.principal,
        settings.connection,
        id,
        @env.now().to_double(),
      ),
      "stop.original.ref",
    ),
    "stop.original.missing",
  )
  let scope = public_run_scope(host, settings, crypto)
  let journal = request_lookup_ok(host.run_journal(), "stop.journal")
  let epoch = request_lookup_ok(host.epoch_authority(), "stop.epoch")
  let record = request_lookup_ok(
    journal.lookup_submitted_intent(
      epoch,
      reference,
      scope,
      local_submit_allowed(host, settings, crypto, scope),
      @env.now().to_double(),
    ),
    "stop.original.intent",
  )
  guard record is Submitted(original) else { fail("stop.original.retained") }
  assert_true(
    @run_host.client_submitted_intent_requests_commit_stop(
      @local_host.native_client_submitted_intent(original),
    ),
  )
  assert_true(
    @local_host.native_client_submitted_run_admission(original) is None,
  )
  let absent = @run_host.prepare_client_submitted_intent(
    local_intent_wire(
      input_root,
      "aql",
      requested_stop_arguments("run", None).subcommand.unwrap().1,
    ),
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(
    journal.record_submitted_intent(
      epoch,
      reference,
      absent,
      scope,
      local_submit_allowed(host, settings, crypto, scope),
      @env.now().to_double(),
    )
    is Err(ChangedIntent),
  )
  let lookup = command().parse(
      argv=["lookup-request", "--request-id", id],
      env=Map([]),
    ).subcommand.unwrap().1
  let before = local_request_lookup(host, settings, crypto, lookup)
  request_lookup_ok(host.close(), "stop.close")
  let (reopened, reopened_settings, reopened_crypto) = request_lookup_fixture(
    name,
    existing=true,
    ttl_ms=60000.0,
  )
  let after = local_request_lookup(
    reopened, reopened_settings, reopened_crypto, lookup,
  )
  request_lookup_ok(reopened.close(), "stop.reopened.close")
  assert_true(
    failure.has_prefix(
      "LocalRunInstallationRequired originalSubmissionRequestId=",
    ),
  )
  assert_eq(before, after)
  assert_true(
    after.contains(
      "sha256:3bd00241ad0b5101bf65c24d99dbc3745f92f872d531004c1016d209339fbc1c",
    ),
  )
  assert_true(after.contains("\"phase\":\"preparing\""))
  assert_false(after.contains("waiting_checkpoint"))
}
