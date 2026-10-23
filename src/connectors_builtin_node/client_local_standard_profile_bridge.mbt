///|
/// Standard Local policy DATA. The Host still owns initial exclusive creation,
/// durable adoption and the actual current Account/installation association.
#export_name("clientProgramLocalStandardAccountProfile")
pub fn client_program_local_standard_account_profile() -> (
  String,
  String,
  String,
  String,
) {
  let profile = @authorization.local_standard_profile_identity()
  (
    profile.profile_id,
    profile.profile_version,
    profile.profile_cid,
    @authorization.local_standard_profile_body(),
  )
}

///|
#export_name("clientProgramLocalStandardAccountConfiguration")
pub fn client_program_local_standard_account_configuration(
  account_id : String,
  principal : String,
  control_connection : String,
  configured_connections : Array[String],
  model_tasks : Array[(String, String)],
  request_target : (String, String)?,
  signing_key_resource : String?,
) -> Result[String, @authorization.LocalStandardProfileIssue] {
  @authorization.local_standard_account_configuration({
    account_id,
    principal,
    control_connection,
    configured_connections,
    model_tasks,
    request_target,
    signing_key_resource,
  })
}
