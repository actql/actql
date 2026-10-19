///|
fn public_run_arguments(
  extra? : ArrayView[String] = [],
) -> @argparse.Matches raise {
  let args = ["--mode", "local", "run", "literal.sql", "--format", "sql"]
  for value in extra {
    args.push(value)
  }
  let parsed = command().parse(argv=args[:], env=Map([]))
  normalize_native_program_arguments(parsed)
  parsed
}

///|
fn public_run_scope(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
) -> String raise {
  request_lookup_ok(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
    "public.scope",
  )
}

///|
test "public Native run accepts a Program without private correlation files" {
  let parsed = public_run_arguments()
  let child = parsed.subcommand.unwrap().1
  assert_eq(required(child, "program-file"), "literal.sql")
  assert_eq(required(child, "format"), "sql")
  assert_eq(optional(child, "submission-ref-file"), None)
  assert_eq(optional(child, "operation-attempt-id"), None)
  assert_eq(optional(child, "request-id"), None)
  // The private start spelling still requires complete saved correlation.
  // The public literal aql spelling has a distinct parsed query entrance;
  // its nonpublic intake is checked at the original submission Owner below.
  for operation in ["start"] {
    let original = [operation, "--program-file", "literal.sql"]
    let complete = original.copy()
    for
      value in [
        "--submission-ref-file", "original.json", "--operation-attempt-id", "original-attempt",
      ] {
      complete.push(value)
    }
    ignore(command().parse(argv=complete[:], env=Map([])))
    assert_true(
      try {
        command().parse(argv=original[:], env=Map([])) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "public Native run never fills an incomplete original or reinterprets a nonce assertion" {
  for
    args in [
      ["--submission-ref-file", "original.json"],
      ["--operation-attempt-id", "original-attempt"],
      ["--request-id", "original-nonce"],
    ] {
    assert_true(
      try {
        public_run_arguments(extra=args[:]) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  let child = public_run_arguments(extra=[
      "--submission-ref-file", "original.json", "--operation-attempt-id", "original-attempt",
      "--request-id", "original-nonce",
    ]).subcommand.unwrap().1
  assert_eq(required(child, "submission-ref-file"), "original.json")
  assert_eq(required(child, "operation-attempt-id"), "original-attempt")
  assert_eq(optional(child, "request-id"), Some("original-nonce"))
}

///|
test "fresh public run selects authentic original Epoch references on the same physical Host" {
  let (host, settings, crypto) = request_lookup_fixture(
    "public-run-fresh",
    ttl_ms=60000.0,
  )
  let scope = public_run_scope(host, settings, crypto)
  let child = public_run_arguments().subcommand.unwrap().1
  let first = local_select_run_submission(
    host, settings, crypto, scope, "never-open", child, true,
  )
  let second = local_select_run_submission(
    host, settings, crypto, scope, "never-open", child, true,
  )
  let intent = @run_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  let retained = request_lookup_ok(host.run_journal(), "public.journal").record_submitted_intent(
    request_lookup_ok(host.epoch_authority(), "public.epoch"),
    first.reference,
    intent,
    scope,
    local_submit_allowed(host, settings, crypto, scope),
    @env.now().to_double(),
  )
  request_lookup_ok(host.close(), "public.close")
  let original = request_lookup_ok(retained, "public.original")
  assert_true(first.fresh && second.fresh)
  assert_eq(first.attempt.length(), 68)
  assert_true(first.attempt.has_prefix("cli-"))
  assert_true(first.attempt != second.attempt)
  assert_true(
    @local_host.native_client_submission_request_id(first.reference) !=
    @local_host.native_client_submission_request_id(second.reference),
  )
  assert_eq(
    @run_host.client_submitted_intent_wire(
      @local_host.native_client_submitted_intent(original),
    ),
    @run_host.client_submitted_intent_wire(intent),
  )
  assert_true(
    @local_host.native_client_submitted_run_admission(original) is None,
  )
}

///|
test "public run preparation failure retains the original for lookup and process reopen" {
  let name = "public-run-preparing"
  let (host, settings, crypto) = request_lookup_fixture(name, ttl_ms=60000.0)
  let sqlite = request_lookup_ok(
    @local_sqlite.load_library(settings.sqlite_library),
    "public.sqlite",
  )
  let child = public_run_arguments(extra=["--json"]).subcommand.unwrap().1
  // The actual Host intentionally has no Run installation. This isolates the
  // public correlation/intake boundary before compilation, policy or dispatch.
  let failure = local_submission_start(
    host,
    settings,
    crypto,
    sqlite,
    explain_fixture_environment(),
    @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli",
    local_run_original_operation(),
    child,
    public_run=true,
  ) catch {
    ClientStop(message) => message
  }
  let parts = failure.split(" originalSubmissionRequestId=").to_array()
  guard parts.get(1) is Some(correlation) &&
    correlation.split(" ").next() is Some(id) else {
    request_lookup_ok(host.close(), "public.failed.close") |> ignore
    fail("missing original request correlation")
  }
  let id = id.to_owned()
  let lookup = command().parse(
      argv=["lookup-request", "--request-id", id],
      env=Map([]),
    ).subcommand.unwrap().1
  let first = local_request_lookup(host, settings, crypto, lookup)
  let repeated = local_request_lookup(host, settings, crypto, lookup)
  request_lookup_ok(host.close(), "public.close")
  let (reopened, reopened_settings, reopened_crypto) = request_lookup_fixture(
    name,
    existing=true,
    ttl_ms=60000.0,
  )
  let restored = local_request_lookup(
    reopened, reopened_settings, reopened_crypto, lookup,
  )
  request_lookup_ok(reopened.close(), "public.reopened.close")
  assert_true(
    failure.has_prefix(
      "LocalRunInstallationRequired originalSubmissionRequestId=sha256:",
    ),
  )
  assert_true(failure.contains(" originalOperationAttemptId=cli-"))
  assert_eq(first, repeated)
  assert_eq(first, restored)
  let root = @decode.open_object(local_input_cursor(restored)).unwrap()
  assert_eq(
    @decode.text(@decode.required(root, "phase").unwrap()),
    Ok("preparing"),
  )
  assert_eq(@decode.text(@decode.required(root, "requestId").unwrap()), Ok(id))
  assert_true(@decode.lookup(root, "ref") is None)
}

///|
test "fresh public run requires actual current submit and cannot borrow foreign scope" {
  let (host, settings, crypto) = request_lookup_fixture(
    "public-run-denied",
    submit=false,
    ttl_ms=60000.0,
  )
  let scope = public_run_scope(host, settings, crypto)
  let child = public_run_arguments().subcommand.unwrap().1
  let denied = try {
    local_select_run_submission(
      host, settings, crypto, scope, "never-open", child, true,
    )
    |> ignore
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  request_lookup_ok(host.close(), "public.denied.close")
  assert_eq(denied, "LocalSubmissionAuthorizationDenied")
  let (other, other_settings, other_crypto) = request_lookup_fixture(
    "public-run-foreign",
    ttl_ms=60000.0,
  )
  let foreign = try {
    local_select_run_submission(
      other,
      other_settings,
      other_crypto,
      "sha256:" + "f".repeat(64),
      "never-open",
      child,
      true,
    )
    |> ignore
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  request_lookup_ok(other.close(), "public.foreign.close")
  assert_eq(foreign, "LocalSubmissionAuthorizationDenied")
}

///|
test "public run cannot issue another identity from a retired Host or an old nonpublic intake" {
  let (host, settings, crypto) = request_lookup_fixture(
    "public-run-retired",
    ttl_ms=60000.0,
  )
  let scope = public_run_scope(host, settings, crypto)
  let nonpublic = command().parse(
      argv=["aql", "--program-file", "literal.sql", "--format", "sql"],
      env=Map([]),
    ).subcommand.unwrap().1
  let original_required = try {
    local_select_run_submission(
      host, settings, crypto, scope, "never-open", nonpublic, false,
    )
    |> ignore
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  request_lookup_ok(host.close(), "public.retired.close")
  let child = public_run_arguments().subcommand.unwrap().1
  let retired = try {
    local_select_run_submission(
      host, settings, crypto, scope, "never-open", child, true,
    )
    |> ignore
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(retired, "LocalSubmissionAuthorizationDenied")
  assert_eq(original_required, "OriginalSubmissionReferenceRequired")
}

///|
test "public run failure correlation preserves Unknown cleanup responsibility and explicit original bytes" {
  let reference = cli_nonce_reference("original-nonce")
  let explicit : LocalRunSubmission = {
    reference,
    attempt: "original-attempt",
    fresh: false,
  }
  let fresh : LocalRunSubmission = { ..explicit, fresh: true, }
  for
    message in [
      "SubmissionUnknown", "LocalSourceCleanupPending", "LocalResultStoreCleanupPending",
    ] {
    assert_eq(local_run_submission_failure(explicit, message), message)
    let correlated = local_run_submission_failure(fresh, message)
    assert_true(
      correlated.has_prefix(message + " originalSubmissionRequestId="),
    )
    assert_true(
      correlated.contains(
        @local_host.native_client_submission_request_id(reference),
      ),
    )
    assert_true(
      correlated.contains("originalOperationAttemptId=original-attempt"),
    )
    assert_true(correlated.contains("do not resend this operation"))
    assert_false(correlated.contains("succeeded"))
  }
}
