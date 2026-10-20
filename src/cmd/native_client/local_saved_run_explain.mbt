///|
// Read the exact first-admission compiler map. No Program, parameters, current
// Task declarations, compilation or physical execution is reconstructed here.
fn local_saved_run_explain(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  let id = required(child, "run")
  let scope = local_host_result(
    match capture {
      None =>
        host.authority_scope_cid(
          settings.principal,
          settings.connection,
          crypto,
        )
      Some(original) =>
        original.authority_scope_cid_in_original_read(
          settings.principal,
          settings.connection,
        )
    },
  )
  let current = () => {
    local_run_operation_allowed(host, settings, crypto, scope, "read", capture~)
  }
  if !current() {
    stop("LocalRunStateReadAuthorizationDenied")
  }
  let lookup = match capture {
    None =>
      host.lookup_submitted_run_plan_by_id(
        crypto,
        settings.principal,
        settings.connection,
        id,
      )
    Some(original) =>
      local_host_result(
        original.lookup_submitted_run_plan_by_id_in_original_read(
          settings.principal,
          settings.connection,
          id,
        ),
      )
  }
  let selected = match lookup {
    Ok(value) => value
    Err(@local_host.Unavailable) => stop("LocalOriginalRunPlanUnavailable")
    Err(issue) => stop(local_saved_state_issue(issue))
  }
  let plan_wire = selected.wire()
  let plan = @json.parse(plan_wire) catch {
    _ => stop("LocalOriginalRunPlanUnavailable")
  }
  let reference = local_original_run_reference(
    selected.original().definition(),
    scope,
  )
  let wire = encode_request_json(
    Json::object(
      Map([
        ("version", Json::string("actql-run-plan-view/0.1")),
        ("run_ref", reference),
        ("plan_view", plan),
      ]),
    ),
    65536,
  )
  ignore(
    @publication.parse_interactive_run_control_shape(
      "run_plan_view", wire, 65536, 8192, 64,
    ).unwrap_or_else(() => stop("LocalOriginalRunPlanUnavailable")),
  )
  if !current() {
    stop("LocalRunStateReadAuthorizationDenied")
  }
  if child.flags.get("json").unwrap_or(false) {
    return wire
  }
  let output = { text: StringBuilder(), remaining: 65536, }
  output.append(
    "ActQL EXPLAIN · saved Run\nRun: " +
    local_explain_literal(Json::string(id)) +
    "\nRecorded compiler plan; runtime choices and measurements are not represented.\n",
  )
  local_explain_computation(output, plan)
  output.text.to_string()
}
