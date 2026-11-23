///|
/// Original operator selection for the installed Python row sink. This is
/// metadata only, never current authorization, a grant or a delivery attempt.
struct LocalSDKResultReadSelection {
  wire : String
  cid : String
  data_policy_cid : String
  fixed_result_name : String?
} derive(Eq, Debug)

///|
pub(all) enum LocalSDKReadSelectionIssue {
  InvalidBinding
  ForeignOriginal
  Encoding
} derive(Eq, Debug)

///|
/// Select the existing jsonl serialization and finite first-install SDK sink.
/// Profile/Policy CIDs still require their original Host adoption and current
/// Account, committed index/manifest/retention and usage checks at delivery.
pub fn issue_local_sdk_result_read_selection(
  run_policy_profile_cid : String,
  data_policy_cid : String,
  requested_original_result? : Bool = false,
) -> Result[LocalSDKResultReadSelection, LocalSDKReadSelectionIssue] {
  if !valid_contract_cid(run_policy_profile_cid) ||
    !valid_contract_cid(data_policy_cid) {
    return Err(InvalidBinding)
  }
  let wire = try {
    let writer = @encode.writer(8192, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "connection")
    @encode.string_value(writer, "local")
    @encode.key(writer, "data_policy_cids")
    @encode.begin_array(writer)
    @encode.string_value(writer, data_policy_cid)
    @encode.end_array(writer)
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
    if requested_original_result {
      @encode.key(writer, "result_selection")
      @encode.begin_object(writer)
      @encode.key(writer, "authority")
      @encode.string_value(writer, "original_result_read")
      @encode.key(writer, "kind")
      @encode.string_value(writer, "requested_original_result")
      @encode.end_object(writer)
    } else {
      @encode.key(writer, "result_names")
      @encode.begin_array(writer)
      @encode.string_value(writer, "answer")
      @encode.end_array(writer)
    }
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
  Ok({
    wire,
    cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
    data_policy_cid,
    fixed_result_name: if requested_original_result {
      None
    } else {
      Some("answer")
    },
  })
}

///|
/// Exact closed-body admission against the selected original dependencies.
/// No parser, clock or grant is created by admitting these metadata bytes.
pub fn admit_local_sdk_result_read_selection(
  wire : String,
  run_policy_profile_cid : String,
  data_policy_cid : String,
) -> Result[LocalSDKResultReadSelection, LocalSDKReadSelectionIssue] {
  // The marker chooses which closed body to reconstruct. Only equality of
  // every byte admits either the legacy original or the first-install mode.
  issue_local_sdk_result_read_selection(
    run_policy_profile_cid,
    data_policy_cid,
    requested_original_result=wire.contains("\"result_selection\":"),
  ).bind(original => {
    if original.wire == wire {
      Ok(original)
    } else {
      Err(ForeignOriginal)
    }
  })
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
    "local",
    "python-local-read",
    original.fixed_result_name,
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
  match original.fixed_result_name {
    Some(expected) => name == expected
    None => !name.is_empty()
  }
}

///|
pub fn local_sdk_result_read_selection_uses_installed_result_authority(
  original : LocalSDKResultReadSelection,
) -> Bool {
  original.fixed_result_name is None
}
