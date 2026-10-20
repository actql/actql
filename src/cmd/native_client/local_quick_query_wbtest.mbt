///|
fn quick_query_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  let selected = command().parse(argv~, env=Map([]))
  normalize_native_query_arguments(selected)
  selected
}

///|
// Report only the closed issue variant, never the submitted document or wire.
fn quick_query_intent_original(
  wire : String,
) -> @run_host.ClientSubmittedIntent raise {
  match @run_host.prepare_client_submitted_intent(wire, 65536, 8192, 64) {
    Ok(original) => original
    Err(issue) => {
      let kind = match issue {
        InvalidLimits => "InvalidLimits"
        Limit => "Limit"
        InvalidEnvelope => "InvalidEnvelope"
        Encoding => "Encoding"
      }
      fail("quick.prepare_client_submitted_intent." + kind)
    }
  }
}

///|
test "public quick queries select literal SQL and Pipe inputs without reading a Program file" {
  for (operation, format) in [("sql", "sql"), ("aql", "aql-text")] {
    let text = "SELECT 'é\r\n😀' AS value"
    let selected = quick_query_arguments([
      "--mode", "local", operation, text, "--format", "jsonl",
    ])
    let (_, child) = selected.subcommand.unwrap()
    assert_true(local_quick_query_requested(operation, child))
    assert_eq(optional(child, "program-file"), None)
    let wire = local_intent_wire("/never-open-this-root", operation, child)
    let original = quick_query_intent_original(wire)
    assert_true(@run_host.client_submitted_intent_requests_read_only(original))
    assert_false(
      @run_host.client_submitted_intent_requests_commit_stop(original),
    )
    let intent = effect_finite_cli_ok(
      @decode.open_object(local_input_cursor(wire)),
      "quick.intent.open_object",
    )
    let input = effect_finite_cli_ok(
      @decode.open_object(
        effect_finite_cli_ok(
          @decode.required(intent, "input"),
          "quick.input.required",
        ),
      ),
      "quick.input.open_object",
    )
    assert_eq(run_text(input, "text"), text)
    assert_eq(run_text(input, "format"), format)
    assert_eq(run_text(intent, "kind"), "aql")
    // required intentionally refuses explicit null; this original optional
    // parameter input must be present and null rather than absent.
    guard @decode.lookup(intent, "parameters") is Some(parameters) else {
      fail("quick.parameters.lookup")
    }
    assert_true(@decode.is_null(parameters))
  }
}

///|
test "quick query params aliases keep the original separate parameter input" {
  for operation in ["sql", "aql"] {
    let selected = quick_query_arguments([
      operation, "SELECT @value AS value", "--params", "parameters.json",
    ])
    normalize_native_query_arguments(selected)
    let (_, child) = selected.subcommand.unwrap()
    assert_eq(optional(child, "parameters-file"), Some("parameters.json"))
    assert_eq(optional(child, "params"), None)
    assert_eq(optional(child, "parameter-declarations-file"), None)
  }
}

///|
fn quick_query_declared_preparation(
  wire : String,
) -> Result[
  @local_host.NativeClientSubmittedPreparation,
  @local_host.NativeClientSubmittedPreparationIssue,
] raise {
  let environment = explain_fixture_environment()
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  @local_host.prepare_native_client_submitted_program(
    quick_query_intent_original(wire),
    environment,
    Some(context),
    [],
    @run_host.client_standard_effect_computation_limits(),
  )
}

///|
test "literal queries retain bounded typed declarations through original normalization" {
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  for operation in ["sql", "aql"] {
    let selected = quick_query_arguments([
      operation, "SELECT @id AS id", "--parameter-declarations-file", "parameter-declarations.json",
      "--params", "parameter-values.json",
    ])
    normalize_native_query_arguments(selected)
    let (_, child) = selected.subcommand.unwrap()
    assert_eq(
      optional(child, "parameter-declarations-file"),
      Some("parameter-declarations.json"),
    )
    let wire = local_intent_wire(root, operation, child)
    let prepared = quick_query_declared_preparation(wire).unwrap()
    assert_eq(
      @local_host.native_client_submitted_preparation_intent_cid(prepared),
      @run_host.client_submitted_intent_cid(quick_query_intent_original(wire)),
    )
    guard @local_host.native_client_submitted_preparation(prepared)
      is @local_host.Computation(original) else {
      fail("typed literal query did not prepare its own computation")
    }
    assert_eq(@run_host.prepared_client_result_count(original), 1)
    // Preparation alone is insufficient for the public Run path: the same
    // checked owner must supply its actual supported normalization inventory.
    let normalization = @run_host.issue_prepared_client_local_normalization(
      original,
    ).unwrap()
    assert_true(
      @run_host.prepared_client_local_normalization_evidence(
        original, normalization,
      )
      is Ok(_),
    )
    // Both routes share the same original declaration/values file intake.
    let file = command().parse(
      argv=[
        "run",
        "--program-file",
        "parameterized.sql",
        "--format",
        if operation == "sql" {
          "sql"
        } else {
          "aql-text"
        },
        "--parameter-declarations-file",
        "parameter-declarations.json",
        "--params",
        "parameter-values.json",
      ],
      env=Map([]),
    )
    normalize_native_program_arguments(file)
    let file_wire = local_intent_wire(root, "run", file.subcommand.unwrap().1)
    let file_prepared = quick_query_declared_preparation(file_wire).unwrap()
    guard @local_host.native_client_submitted_preparation(file_prepared)
      is @local_host.Computation(file_original) else {
      fail("file-backed typed query did not prepare")
    }
    assert_eq(
      @run_host.prepared_client_identity(original).parameter_values_cid,
      @run_host.prepared_client_identity(file_original).parameter_values_cid,
    )
  }
}

///|
test "literal query values cannot infer declarations or bypass required value contracts" {
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  for operation in ["sql", "aql"] {
    let undeclared = quick_query_arguments([
      operation, "SELECT @id AS id", "--params", "parameter-values.json",
    ])
    let wire = local_intent_wire(
      root,
      operation,
      undeclared.subcommand.unwrap().1,
    )
    assert_true(quick_query_declared_preparation(wire) is Err(_))
    let selected = quick_query_arguments([
      operation, "SELECT @id AS id", "--parameter-declarations-file", "parameter-declarations.json",
      "--params", "parameter-values.json",
    ])
    let wire = local_intent_wire(
      root,
      operation,
      selected.subcommand.unwrap().1,
    )
    let original_values = "\"parameters\":{\"id\":7}"
    assert_true(wire.contains(original_values))
    for invalid in ["{}", "{\"id\":null}", "{\"id\":\"7\"}"] {
      let changed = wire.replace(
        old=original_values,
        new="\"parameters\":" + invalid,
      )
      assert_true(quick_query_declared_preparation(changed) is Err(_))
    }
  }
}

///|
test "quick query result encoding never chooses the source parser" {
  for operation in ["sql", "aql"] {
    for format in ["json", "jsonl", "csv", "table"] {
      let selected = quick_query_arguments([
        operation, "SELECT 1 AS id", "--format", format,
      ])
      let (_, child) = selected.subcommand.unwrap()
      assert_eq(local_quick_query_format(child), format)
      let wire = local_intent_wire("/never-open-this-root", operation, child)
      let input = @decode.open_object(
        @decode.required(
          @decode.open_object(local_input_cursor(wire)).unwrap(),
          "input",
        ).unwrap(),
      ).unwrap()
      assert_eq(
        run_text(input, "format"),
        if operation == "sql" {
          "sql"
        } else {
          "aql-text"
        },
      )
    }
  }
  let selected = quick_query_arguments(["sql", "SELECT 1 AS id"])
  assert_eq(local_quick_query_format(selected.subcommand.unwrap().1), "table")
}

///|
test "quick query grammar refuses ambiguous original and output selections" {
  for
    args in [
      ["sql", "SELECT 1", "SELECT 2"],
      ["aql", "SELECT 1", "--program-file", "other.sql"],
      ["sql", "SELECT 1", "--params", "a.json", "--parameters-file", "b.json"],
      ["aql", "SELECT 1", "--stop-before", "commit"],
      ["aql", "SELECT 1", "--submission-ref-file", "original.json"],
      ["aql", "SELECT 1", "--request-id", "old-nonce"],
      ["sql", "SELECT 1", "--format", "sql"],
      ["sql", "SELECT 1", "--format", "JSON"],
    ] {
    assert_true(
      try {
        ignore(quick_query_arguments(args[:]))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "the existing file-backed AQL route retains original format and correlation" {
  let parsed = quick_query_arguments([
    "aql", "--program-file", "literal.sql", "--format", "sql", "--submission-ref-file",
    "original-submission.json", "--operation-attempt-id", "original-attempt", "--request-id",
    "original-nonce",
  ])
  let (_, child) = parsed.subcommand.unwrap()
  assert_false(local_quick_query_requested("aql", child))
  assert_eq(optional(child, "query"), None)
  let root = @env.current_dir().unwrap() + "/scripts/fixtures/native-local-cli"
  assert_eq(
    local_intent_wire(root, "aql", child),
    (
      #|{"kind":"aql","input":{"text":"SELECT 1 AS id\n","format":"sql"},"parameters":null}
    ),
  )
  assert_eq(required(child, "submission-ref-file"), "original-submission.json")
  assert_eq(required(child, "operation-attempt-id"), "original-attempt")
  assert_eq(optional(child, "request-id"), Some("original-nonce"))
}

///|
test "quick query Remote refusal precedes connection or input IO" {
  for operation in ["sql", "aql"] {
    let parsed = quick_query_arguments([
      "--mode", "remote", operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    let issue = try {
      ignore(execute(parsed))
      "unexpected success"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(issue, "QuickQueryRequiresLocalHost")
  }
}

///|
test "quick query payload routes do not append a second response or newline" {
  for operation in ["sql", "aql"] {
    let selected = quick_query_arguments([
      "--mode", "local", operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    assert_true(local_payload_already_streamed(selected))
    let remote = quick_query_arguments([
      "--mode", "remote", operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    assert_false(local_payload_already_streamed(remote))
  }
  let legacy = quick_query_arguments([
    "--mode", "local", "aql", "--program-file", "literal.sql", "--format", "sql",
    "--submission-ref-file", "original.json", "--operation-attempt-id", "original",
  ])
  assert_false(local_payload_already_streamed(legacy))
}

///|
test "literal SQL and Pipe quick queries read the actual same Host published Result" {
  for operation in ["sql", "aql"] {
    let (host, settings, crypto, _) = effect_finite_cli_host(
      "literal-quick-" + operation,
      ttl_ms=86400000.0,
      observed_at=local_utc_now(),
      managed_root=true,
    )
    defer host.close() |> ignore
    let sqlite = effect_finite_cli_ok(
      @local_sqlite.load_library(settings.sqlite_library),
      "quick.sqlite",
    )
    let assets = @run_host.client_local_product_assets()
    let fields = @decode.open_object(local_input_cursor(assets.environment)).unwrap()
    let environment = @run_host.admit_client_check_environment(
      assets.environment,
      run_text(fields, "evidence_bundle_cid"),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ).unwrap()
    let selected = quick_query_arguments([
      "--mode", "local", operation, "SELECT 1 AS id", "--format", "jsonl",
    ])
    result_fresh_host_marker("ACTQL_QUICK_" + operation + "_BEGIN")
    let reply = local_quick_query(
      host,
      settings,
      crypto,
      sqlite,
      environment,
      "/never-read-query-file",
      operation,
      selected.subcommand.unwrap().1,
    ) catch {
      ClientStop(issue) => fail("quick." + operation + ": " + issue)
    }
    result_fresh_host_marker("ACTQL_QUICK_" + operation + "_END")
    assert_eq(reply, "")
    effect_finite_cli_ok(host.close(), "quick.host.close")
  }
}
