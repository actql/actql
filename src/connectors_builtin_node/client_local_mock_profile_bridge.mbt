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
