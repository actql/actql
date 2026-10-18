///|
// Each original public operation has an independent Host and saved Run. Keep
// this property separate from the existing two-operation aggregate test.
fn individual_original_quick_query(operation : String) -> Unit raise {
  let (host, settings, crypto, _) = effect_finite_cli_host(
    "individual-literal-quick-" + operation,
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

///|
test "individual literal SQL returns the same original Host Result" {
  individual_original_quick_query("sql")
}

///|
test "individual literal Pipe returns the same original Host Result" {
  individual_original_quick_query("aql")
}
