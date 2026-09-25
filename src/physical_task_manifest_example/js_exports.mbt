///|
#export_name("applicationTaskManifest")
pub fn application_task_manifest(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  data : @manifest.DataProfile,
) -> Array[@strategy.CheckedTaskIdentity] raise {
  @manifest.application_task_manifest(
    program_json,
    environment_json,
    environment_cid,
    parameter_json,
    Some(data),
  )
}

///|
#export_name("applicationTaskManifestDefault")
pub fn application_task_manifest_default(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
) -> Array[@strategy.CheckedTaskIdentity] raise {
  @manifest.application_task_manifest(
    program_json,
    environment_json,
    environment_cid,
    parameter_json,
    None,
  )
}
