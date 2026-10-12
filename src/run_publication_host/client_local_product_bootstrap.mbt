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
