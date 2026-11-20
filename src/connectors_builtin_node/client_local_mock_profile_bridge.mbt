///|
/// Same Common policy DATA for the explicit Local Mock initializer. The Host
/// still owns actual installation, exclusive config/key creation, adoption and
/// independent current backend/Account/Reviewer authority.
#export_name("clientProgramLocalMockAccountProfile")
pub fn client_program_local_mock_account_profile() -> (
  String,
  String,
  String,
  String,
) {
  let profile = @authorization.local_mock_profile_identity()
  (
    profile.profile_id,
    profile.profile_version,
    profile.profile_cid,
    @authorization.local_mock_profile_body(),
  )
}

///|
/// Recognize a saved policy identity, without upgrading its Account or
/// authenticating installation custody. First initialization uses the current
/// profile; reopen keeps the exact known original from its durable intent.
#export_name("clientProgramLocalMockAccountProfileKnown")
pub fn client_program_local_mock_account_profile_known(
  profile_id : String,
  profile_version : String,
  profile_cid : String,
) -> Bool {
  @authorization.is_known_local_mock_profile({
    profile_id,
    profile_version,
    profile_cid,
  })
}

///|
#export_name("clientProgramLocalMockAccountConfiguration")
pub fn client_program_local_mock_account_configuration(
  account_id : String,
  principal : String,
  control_connection : String,
  sources : Array[(String, String)],
  model_tasks : Array[String],
  request_target : (String, String)?,
  update_target : (String, String)?,
  signing_key_resource : String?,
) -> Result[String, @authorization.LocalMockProfileIssue] {
  @authorization.local_mock_account_configuration({
    account_id,
    principal,
    control_connection,
    sources,
    model_tasks,
    request_target,
    update_target,
    signing_key_resource,
  })
}

///|
#export_name("clientProgramLocalMockAccountInventoryPrepared")
pub fn client_program_local_mock_account_inventory_prepared(
  control_connection : String,
  sources : Array[(String, String)],
  model_tasks : Array[String],
  request_target : (String, String)?,
  update_targets : Array[(String, String)],
  prepare : (Int64, Int64) -> Bool,
) -> Result[Unit, @authorization.LocalMockProfileIssue]? {
  @authorization.validate_local_mock_inventory_prepared(
    control_connection,
    sources,
    model_tasks,
    request_target,
    update_targets,
    request => {
      guard account_bridge_cost(request.retained) is Some(r) &&
        account_bridge_cost(request.execution) is Some(e) else {
        return false
      }
      prepare(r, e)
    },
  )
}

///|
#export_name("clientProgramLocalMockAccountConfigurationPrepared")
pub fn client_program_local_mock_account_configuration_prepared(
  account_id : String,
  principal : String,
  control_connection : String,
  sources : Array[(String, String)],
  model_tasks : Array[String],
  request_target : (String, String)?,
  update_targets : Array[(String, String)],
  signing_key_resource : String?,
  prepare : (Int64, Int64) -> Bool,
) -> Result[String, @authorization.LocalMockProfileIssue]? {
  @authorization.local_mock_account_configuration_prepared(
    {
      account_id,
      principal,
      control_connection,
      sources,
      model_tasks,
      request_target,
      update_target: None,
      signing_key_resource,
    },
    update_targets,
    request => {
      guard account_bridge_cost(request.retained) is Some(r) &&
        account_bridge_cost(request.execution) is Some(e) else {
        return false
      }
      prepare(r, e)
    },
  )
}

///|
/// Admit the SAME Read's constructor envelope before key generation. True is
/// only that actual preparation callback's result, not policy/Allow/adoption.
#export_name("clientProgramLocalMockAccountBeforeSigningPrepared")
pub fn client_program_local_mock_account_before_signing_prepared(
  account_id : String,
  principal : String,
  control_connection : String,
  sources : Array[(String, String)],
  model_tasks : Array[String],
  request_target : (String, String)?,
  update_targets : Array[(String, String)],
  signing_key_units : Int,
  prepare : (Int64, Int64) -> Bool,
) -> Bool {
  guard @authorization.local_mock_account_construction_before_signing(
      {
        account_id,
        principal,
        control_connection,
        sources,
        model_tasks,
        request_target,
        update_target: None,
        signing_key_resource: None,
      },
      update_targets,
      signing_key_units,
    )
    is Some(request) &&
    account_bridge_cost(request.retained) is Some(r) &&
    account_bridge_cost(request.execution) is Some(e) else {
    return false
  }
  // No output exists yet. Reuse only this scratch envelope; the later actual
  // constructor separately retains its one returned configuration String.
  prepare(0L, Int64::max(r, e))
}

///|
/// Additive String DATA projection; the existing inventory Unit ABI is intact.
#export_name("clientProgramLocalMockAccountControlConnectionPrepared")
pub fn client_program_local_mock_account_control_connection_prepared(
  preferred : String,
  saved_profile : (String, String, String)?,
  original_control : String?,
  sources : Array[(String, String)],
  update_targets : Array[(String, String)],
  prepare : (Int64, Int64) -> Bool,
) -> Result[String, @authorization.LocalMockProfileIssue]? {
  // The bridge's optional profile record is also under the original Read,
  // before record/Some construction. It borrows the three retained fields.
  if saved_profile is Some(_) {
    guard account_bridge_cost({
        record_headers: 2L,
        reference_slots: 4L,
        scalar_words: 1L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(e) &&
      prepare(0L, e) else {
      return None
    }
  }
  let profile : @authorization.BootstrapProfile? = saved_profile.map(value => {
    profile_id: value.0,
    profile_version: value.1,
    profile_cid: value.2,
  })
  @authorization.local_mock_control_connection_prepared(
    preferred,
    profile,
    original_control,
    sources,
    update_targets,
    request => {
      guard account_bridge_cost(request.retained) is Some(r) &&
        account_bridge_cost(request.execution) is Some(e) else {
        return false
      }
      prepare(r, e)
    },
  )
}
