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
  let wire = match capture {
    Some(original) =>
      local_host_result(
        original.saved_run_plan_reply_in_original_read(selected, scope),
      )
    // Legacy callers have no original Read to grow. Keep their old bounded
    // presentation rather than manufacturing an unbacked large constructor.
    None =>
      local_saved_run_plan_reply(
        local_original_run_reference(selected.original().definition(), scope),
        plan_wire,
      )
  }
  if !current() {
    stop("LocalRunStateReadAuthorizationDenied")
  }
  if child.flags.get("json").unwrap_or(false) {
    return wire
  }
  // The human formatter still owns only its original small-view parser.
  // Refuse before builtin JSON allocation; large saved plans use the funded
  // canonical --json path above, not a silently expanded display budget.
  let mut display_bytes = 0L
  for character in plan_wire {
    let scalar = character.to_int()
    display_bytes += if scalar < 128 {
      1L
    } else if scalar < 2048 {
      2L
    } else if scalar < 65536 {
      3L
    } else {
      4L
    }
    if display_bytes > 65536L {
      stop(
        "LocalSavedPlanTextLimitUseJson: saved plan exceeds the text display limit; rerun with --json",
      )
    }
  }
  let output = { text: StringBuilder(), remaining: 65536, }
  output.append(
    "ActQL EXPLAIN · saved Run\nRun: " +
    local_explain_literal(Json::string(id)) +
    "\nRecorded compiler plan; runtime choices and measurements are not represented.\n",
  )
  let plan = @json.parse(plan_wire) catch {
    _ => stop("LocalOriginalRunPlanUnavailable")
  }
  local_explain_computation(
    output,
    plan,
    verbose=child.flags.get("verbose").unwrap_or(false),
  )
  output.text.to_string()
}

///|
// Bounded presentation of an already selected original. DATA construction here
// cannot select a Run, authorize a read or manufacture compiler evidence.
fn local_saved_run_plan_reply(
  reference : Json,
  plan_wire : String,
) -> String raise ClientStop {
  let plan = @json.parse(plan_wire) catch {
    _ => stop("LocalOriginalRunPlanUnavailable")
  }
  let envelope = Json::object(
    Map([
      ("version", Json::string("actql-run-plan-view/0.1")),
      ("run_ref", reference),
      ("plan_view", plan),
    ]),
  )
  // Admission budgets are nodes, depth and text units; emission separately
  // limits UTF-8 bytes for the complete public envelope.
  let canonical = @canonical.from_json(
    envelope,
    8192,
    64,
    65536,
    data_keys=true,
  ) catch {
    _ => stop("LocalOriginalRunPlanUnavailable")
  }
  let wire = @canonical.stringify_value(canonical, 65536, 8192, 64) catch {
    _ => stop("LocalOriginalRunPlanUnavailable")
  }
  ignore(
    @publication.parse_interactive_run_control_shape(
      "run_plan_view", wire, 65536, 8192, 64,
    ).unwrap_or_else(() => stop("LocalOriginalRunPlanUnavailable")),
  )
  wire
}
