///|
/// Original operator selection for the installed Python row sink. This is
/// metadata only, never current authorization, a grant or a delivery attempt.
struct LocalSDKResultReadSelection {
  wire : String
  cid : String
  data_policy_cid : String
  accepted_run_policy : Bool
  scope : LocalSDKResultReadScope
  connection : String
} derive(Eq, Debug)

///|
// The read subject and the source of its data policy are independent.
pub(all) enum LocalSDKResultReadScope {
  RequestedOriginal
  WorkerAnswer
} derive(Eq, Debug)

///|
pub(all) enum LocalSDKReadSelectionIssue {
  InvalidBinding
  ForeignOriginal
  Encoding
} derive(Eq, Debug)

///|
fn local_sdk_result_read_wire(
  run_policy_profile_cid : String,
  data_policy_cid : String,
  scope : LocalSDKResultReadScope,
  connection : String,
  accepted_run_policy : Bool,
) -> Result[String, LocalSDKReadSelectionIssue] {
  let wire = try {
    let writer = @encode.writer(8192, 32, 4)
    @encode.begin_object(writer)
    if accepted_run_policy {
      @encode.key(writer, "accepted_run_policy")
      @encode.bool_value(writer, true)
    }
    @encode.key(writer, "connection")
    @encode.string_value(writer, connection)
    if !accepted_run_policy {
      @encode.key(writer, "data_policy_cids")
      @encode.begin_array(writer)
      @encode.string_value(writer, data_policy_cid)
      @encode.end_array(writer)
    }
    @encode.key(writer, "formats")
    @encode.begin_array(writer)
    @encode.string_value(writer, "jsonl")
    @encode.end_array(writer)
    @encode.key(writer, "max_bytes")
    @encode.number_value(writer, 65536.0)
    @encode.key(writer, "max_uses")
    @encode.number_value(writer, 1.0)
    @encode.key(writer, "principal")
    @encode.string_value(writer, "local-cli")
    @encode.key(writer, "purpose")
    @encode.string_value(writer, "python-local-read")
    @encode.key(writer, "result_selection")
    @encode.begin_object(writer)
    @encode.key(writer, "authority")
    match scope {
      RequestedOriginal => {
        @encode.string_value(writer, "original_result_read")
        @encode.key(writer, "kind")
        @encode.string_value(writer, "requested_original_result")
      }
      WorkerAnswer => {
        @encode.string_value(writer, "named_result_read")
        @encode.key(writer, "kind")
        @encode.string_value(writer, "finite_result_names")
        @encode.key(writer, "names")
        @encode.begin_array(writer)
        @encode.string_value(writer, "answer")
        @encode.end_array(writer)
      }
    }
    @encode.end_object(writer)
    @encode.key(writer, "run_policy_profile_cid")
    @encode.string_value(writer, run_policy_profile_cid)
    @encode.key(writer, "sink")
    @encode.string_value(writer, "sdk-rows")
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-local-sdk-result-read-selection/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok(wire)
}

///|
fn seal_local_sdk_result_read_selection(
  wire : String,
  data_policy_cid : String,
  scope : LocalSDKResultReadScope,
  connection : String,
  accepted_run_policy : Bool,
) -> LocalSDKResultReadSelection {
  {
    wire,
    cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
    data_policy_cid,
    accepted_run_policy,
    scope,
    connection,
  }
}

///|
/// Select the existing jsonl SDK sink. The selected scope is metadata, and
/// carries neither the current Account nor a Run or Result grant.
pub fn issue_local_sdk_result_read_selection(
  run_policy_profile_cid : String,
  data_policy_cid : String,
  scope? : LocalSDKResultReadScope = RequestedOriginal,
  connection? : String = "local",
  accepted_run_policy? : Bool = false,
) -> Result[LocalSDKResultReadSelection, LocalSDKReadSelectionIssue] {
  if !valid_contract_cid(run_policy_profile_cid) ||
    !valid_contract_cid(data_policy_cid) ||
    (scope is WorkerAnswer && (connection != "local" || accepted_run_policy)) ||
    !local_sdk_read_connection_fits(connection) {
    return Err(InvalidBinding)
  }
  local_sdk_result_read_wire(
    run_policy_profile_cid, data_policy_cid, scope, connection, accepted_run_policy,
  ).map(wire => {
    seal_local_sdk_result_read_selection(
      wire, data_policy_cid, scope, connection, accepted_run_policy,
    )
  })
}

///|
fn local_sdk_read_connection_fits(connection : String) -> Bool {
  @scalar.admit_utf8_length(connection, 256) is Ok(count) && count > 0
}

///|
/// Admit the selected metadata by exact whole-body equality. A Project
/// caller may opt into the explicit accepted-Run selector. A historical
/// literal selector still admits its own exact bytes.
pub fn admit_local_sdk_result_read_selection(
  wire : String,
  run_policy_profile_cid : String,
  data_policy_cid : String,
  connection? : String = "local",
  permits_accepted_run_policy? : Bool = false,
) -> Result[LocalSDKResultReadSelection, LocalSDKReadSelectionIssue] {
  if !valid_contract_cid(run_policy_profile_cid) ||
    !valid_contract_cid(data_policy_cid) ||
    !local_sdk_read_connection_fits(connection) {
    return Err(InvalidBinding)
  }
  let accepted_run_policy = wire.has_prefix("{\"accepted_run_policy\":")
  if accepted_run_policy && !permits_accepted_run_policy {
    return Err(ForeignOriginal)
  }
  let scope = if local_sdk_result_read_wire(
      run_policy_profile_cid,
      data_policy_cid,
      RequestedOriginal,
      connection,
      accepted_run_policy,
    )
    is Ok(expected) &&
    expected == wire {
    RequestedOriginal
  } else if !accepted_run_policy &&
    connection == "local" &&
    local_sdk_result_read_wire(
      run_policy_profile_cid,
      data_policy_cid,
      WorkerAnswer,
      connection,
      false,
    )
    is Ok(expected) &&
    expected == wire {
    WorkerAnswer
  } else {
    return Err(ForeignOriginal)
  }
  Ok(
    seal_local_sdk_result_read_selection(
      wire, data_policy_cid, scope, connection, accepted_run_policy,
    ),
  )
}

///|
pub fn local_sdk_result_read_selection_wire(
  original : LocalSDKResultReadSelection,
) -> String {
  original.wire
}

///|
pub fn local_sdk_result_read_selection_cid(
  original : LocalSDKResultReadSelection,
) -> String {
  original.cid
}

///|
/// The original issuer's selected Policy reference, not classification or
/// current read authority. The actual retained compiled body remains required.
pub fn local_sdk_result_read_selection_data_policy_cid(
  original : LocalSDKResultReadSelection,
) -> String {
  original.data_policy_cid
}

///|
/// Parameters for the existing delivery issuer, not an issued read grant.
pub fn local_sdk_result_read_selection_parameters(
  original : LocalSDKResultReadSelection,
) -> (String, String, String, String?, String, Int, Int) {
  (
    "local-cli",
    original.connection,
    "python-local-read",
    if original.scope is WorkerAnswer {
      Some("answer")
    } else {
      None
    },
    "jsonl",
    65536,
    1,
  )
}

///|
/// Metadata selection only. Actual membership, current permission and finite
/// committed material are independently checked by the original read Owners.
pub fn local_sdk_result_read_selection_accepts_name(
  original : LocalSDKResultReadSelection,
  name : String,
) -> Bool {
  match original.scope {
    WorkerAnswer => name == "answer"
    RequestedOriginal => !name.is_empty()
  }
}

///|
pub fn local_sdk_result_read_selection_uses_installed_result_authority(
  original : LocalSDKResultReadSelection,
) -> Bool {
  original.scope is RequestedOriginal
}

///|
/// A selector for a bounded same-Run policy original. The committed Result,
/// actual policy closure and current Account still need proof.
pub fn local_sdk_result_read_selection_uses_accepted_run_policy(
  original : LocalSDKResultReadSelection,
) -> Bool {
  original.accepted_run_policy
}
