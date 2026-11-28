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
  product_sdk_bootstrap_originals(
    configuration_root,
    observed_at,
    RequestedOriginal,
  )
}

///|
/// Use the exact installed Local Account in the existing SDK bootstrap. Its
/// admitted policy selects no additional template, grants or bootstrap profile.
pub fn client_local_product_sdk_bootstrap_with_account(
  configuration_root : String,
  observed_at : String,
  account : Bytes,
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Result[
  ClientLocalProductSDKBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  guard account.length() > 0 && account.length() <= 65536 else {
    return Err(ConfigurationLimit)
  }
  let body = @utf8.decode(account) catch { _ => return Err(UnsupportedAsset) }
  match
    @authorization.admit_account_configuration_json_prepared(body, prepare) {
    None => return Err(ConfigurationLimit)
    Some(Ok(original)) if original.account_id() == "local-cli" &&
      original.bootstrap_profile() is None &&
      original.retains_original_bytes(account) => ()
    Some(_) => return Err(UnsupportedAsset)
  }
  product_sdk_bootstrap_originals(
    configuration_root,
    observed_at,
    RequestedOriginal,
    protected_account=Some(account),
  )
}

///|
/// First-adoption metadata for the selected Mock Account and target subjects.
pub fn client_local_product_sdk_mock_bootstrap_originals(
  configuration_root : String,
  observed_at : String,
  subjects : @authorization.LocalMockAccountSubjects,
  targets : Array[(String, String)],
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Result[
  ClientLocalProductSDKBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  product_sdk_bootstrap_originals(
    configuration_root,
    observed_at,
    RequestedOriginal,
    mock=Some(subjects),
    mock_preparation=Some((targets, prepare)),
  )
}

///|
/// Issue first-adoption metadata from the same selected Project Catalogs.
/// The new Account is scoped to exact declared read tuples and one disjoint
/// Host control connection. Reopen uses the retained adopted originals.
pub fn client_local_product_sdk_file_bootstrap_originals(
  configuration_root : String,
  observed_at : String,
  catalogs : Array[ClientProjectLocalFileCatalog],
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Result[
  ClientLocalProductSDKBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  let mut rows = 0L
  for catalog in catalogs {
    rows += catalog.declaration.views.length().to_int64()
  }
  if rows < 1L || rows > 2147483647L {
    return Err(ConfigurationLimit)
  }
  let vector : @authorization.AccountConfigurationConstructionUnits = {
    record_headers: 4L + rows,
    reference_slots: 8L + 4L * rows,
    scalar_words: 8L + 2L * rows,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard prepare({ retained: vector, execution: vector, }) else {
    return Err(ConfigurationLimit)
  }
  let sources : Array[(String, String)] = Array(capacity=rows.to_int())
  for catalog in catalogs {
    for view in catalog.declaration.views {
      sources.push((catalog.project_files.connection, view.resource))
    }
  }
  match
    @authorization.local_standard_file_account_configuration_prepared(
      sources, prepare,
    ) {
    Some(Ok(account)) =>
      product_sdk_bootstrap_originals(
        configuration_root,
        observed_at,
        RequestedOriginal,
        file_account=Some(account),
      )
    Some(Err(_)) => Err(UnsupportedAsset)
    None => Err(ConfigurationLimit)
  }
}

///|
fn product_sdk_bootstrap_originals(
  configuration_root : String,
  observed_at : String,
  scope : @publication.LocalSDKResultReadScope,
  mock? : @authorization.LocalMockAccountSubjects? = None,
  mock_preparation? : (
    Array[(String, String)],
    (@authorization.AccountConfigurationConstruction) -> Bool,
  )? = None,
  file_account? : (String, String)? = None,
  protected_account? : Bytes? = None,
) -> Result[
  ClientLocalProductSDKBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  let baseline = match
    product_bootstrap_originals(
      configuration_root,
      observed_at,
      scope is RequestedOriginal,
      mock~,
      mock_preparation~,
      file_account~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = match protected_account {
    Some(account) => { ..baseline, common: { ..baseline.common, account, }, }
    None => baseline
  }
  let profile = match client_local_run_policy_profile(original.common) {
    Ok(value) => value
    Err(_) => return Err(InvalidResultPolicy)
  }
  let policy = @utf8.decode(original.common.result_policy) catch {
    _ => return Err(InvalidResultPolicy)
  }
  let connection = match file_account {
    Some((control, _)) => control
    None => "local"
  }
  let read = match
    @publication.issue_local_sdk_result_read_selection(
      client_local_run_policy_profile_cid(profile),
      product_cid(policy),
      scope~,
      connection~,
      accepted_run_policy=file_account is Some(_),
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
  product_bootstrap_originals(configuration_root, observed_at, false)
}

///|
fn product_bootstrap_originals(
  configuration_root : String,
  observed_at : String,
  original_result_read : Bool,
  mock? : @authorization.LocalMockAccountSubjects? = None,
  mock_preparation? : (
    Array[(String, String)],
    (@authorization.AccountConfigurationConstruction) -> Bool,
  )? = None,
  file_account? : (String, String)? = None,
) -> Result[
  ClientLocalProductBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  let assets = client_local_product_assets()
  let common = match
    product_common_bootstrap_originals(
      configuration_root,
      observed_at,
      assets,
      original_result_read,
      mock~,
      mock_preparation~,
      file_account~,
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
