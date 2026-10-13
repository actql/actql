///|
/// Installed source-free bootstrap metadata, never an adopted Host or grant.
/// Existing physical adoption must persist these exact originals once. Restore
/// uses retained originals and must not call this factory to replace them.
pub(all) struct ClientLocalProductBootstrapOriginals {
  common : ClientLocalProductCommonOriginals
  environment : String
  compute : String
}

///|
pub(all) struct ClientLocalProductSDKBootstrapOriginals {
  original : ClientLocalProductBootstrapOriginals
  profile : ClientLocalRunPolicyProfile
  read : @publication.LocalSDKResultReadSelection
}

///|
/// Explicit new first-adoption selection. Restoring seven-file material must
/// never invoke this issuer to add missing profile/read originals.
pub fn client_local_product_sdk_bootstrap_originals(
  configuration_root : String,
  observed_at : String,
) -> Result[
  ClientLocalProductSDKBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  let original = match
    client_local_product_bootstrap_originals(configuration_root, observed_at) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let profile = match client_local_run_policy_profile(original.common) {
    Ok(value) => value
    Err(_) => return Err(InvalidResultPolicy)
  }
  let policy = @utf8.decode(original.common.result_policy) catch {
    _ => return Err(InvalidResultPolicy)
  }
  let read = match
    @publication.issue_local_sdk_result_read_selection(
      client_local_run_policy_profile_cid(profile),
      product_cid(policy),
    ) {
    Ok(value) => value
    Err(_) => return Err(ConfigurationLimit)
  }
  Ok({ original, profile, read, })
}

///|
/// Use the same packaged assets and original metadata Owner as Native Local,
/// without Native library paths, a CLI configuration or Python-built policies.
pub fn client_local_product_bootstrap_originals(
  configuration_root : String,
  observed_at : String,
) -> Result[
  ClientLocalProductBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  let assets = client_local_product_assets()
  let common = match
    client_local_product_common_originals(
      configuration_root, observed_at, assets,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let compute = match
    product_wire(
      product_object([
        ("registry", Json::string(assets.registry)),
        ("values", Json::string(assets.values)),
        ("fragment", Json::string(assets.fragment)),
        (
          "ordered",
          match assets.ordered {
            Some(value) => Json::string(value)
            None => Json::null()
          },
        ),
      ]),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ common, environment: assets.environment, compute, })
}
