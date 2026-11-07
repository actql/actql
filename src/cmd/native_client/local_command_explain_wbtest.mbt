///|
// The same selected Host/configuration/current observation used by Local check
// remains live across input reading and static compilation. Its command-local
// reporting key stays private and is never a signing or execution authority.
fn LocalCheckContext::explain(
  self : LocalCheckContext,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  if !self.current() {
    stop("LocalCheckContextUnavailable")
  }
  let reply = local_explain_for_environment(self.environment, input_root, child)
  if !self.current() {
    stop("LocalCheckContextUnavailable")
  }
  reply
}

///|
test "Selected static explain enters the existing operational command scope only in Local mode" {
  let local_command = command().parse(argv=[
    "--mode", "local", "explain", "--program-file", "original.sql", "--format", "sql",
  ])
  assert_true(local_command_preparation_selected(local_command))
  assert_true(command_preparation_invocation.val is None)
  let remote = command().parse(argv=[
    "--mode", "remote", "explain", "--program-file", "original.sql", "--format",
    "sql",
  ])
  assert_false(local_command_preparation_selected(remote))
  prepare_native_command_invocation(remote)
  assert_true(command_preparation_invocation.val is None)
}

///|
test "Selected static explain retains the adopted Environment and refuses a closed original before input IO" {
  // Actual legacy Library/Journal fixture, not the selected operational supplier.
  let (context, root) = check_cli_fixture("native-command-static-explain")
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(root),
    "explain.files",
  )
  let source = @utf8.encode("SELECT 1 AS n")
  let writer = effect_finite_cli_ok(
    files.create_writer("original.sql.stage", source.length().to_int64()),
    "explain.writer",
  )
  effect_finite_cli_ok(writer.append(source), "explain.append")
  effect_finite_cli_ok(writer.seal("original.sql"), "explain.seal") |> ignore
  effect_finite_cli_ok(files.close(), "explain.files.close")
  let parsed = command().parse(argv=[
    "--mode", "local", "explain", "--program-file", "original.sql", "--format", "sql",
    "--json",
  ])
  let (_, child) = parsed.subcommand.unwrap()
  let reply = context.explain(root, child)
  let original = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(context.environment),
    model_tasks=@checked.checking_environment_model_tasks(context.environment),
  ).unwrap()
  let prepared = @local_host.prepare_native_client_program(
    "SELECT 1 AS n",
    Sql,
    context.environment,
    None,
    Some(original),
    [],
    @run_host.client_standard_effect_computation_limits(),
  ).unwrap()
  assert_eq(reply, local_static_plan_view(prepared))
  assert_true(reply.contains("\"provider_io\":0"))
  assert_false(reply.contains("run_ref"))
  assert_true(context.current())
  effect_finite_cli_ok(context.host.close(), "explain.host.close")
  let absent = command().parse(argv=[
    "--mode", "local", "explain", "--program-file", "never-created.sql", "--format",
    "sql", "--json",
  ])
  let (_, absent_child) = absent.subcommand.unwrap()
  let issue = try {
    ignore(context.explain(root, absent_child))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "LocalCheckContextUnavailable")
}
