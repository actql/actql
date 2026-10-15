///|
/// Explicit Python worker first-adoption metadata, never a restored Account or
/// a worker permit. The existing Host adoption Owner must retain this exact
/// Account before its original provisioning child operation can use it.
pub fn client_local_product_python_worker_bootstrap_originals(
  configuration_root : String,
  observed_at : String,
) -> Result[
  ClientLocalProductSDKBootstrapOriginals,
  ClientLocalProductConfigurationIssue,
] {
  let sdk = match
    client_local_product_sdk_bootstrap_originals(
      configuration_root, observed_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let principal = "local-cli"
  let connection = "local"
  let account = match
    product_wire(
      product_object([
        ("version", Json::string("actql-execution-account-config/0.1")),
        ("account_id", Json::string(principal)),
        (
          "entries",
          Json::array([
            product_object([
              ("entry_id", Json::string("local-result-read")),
              ("principal", product_selector(principal)),
              ("connection", product_selector(connection)),
              ("resource", product_selector("result/answer")),
              ("operation", product_selector("read")),
              ("outcome", Json::string("allow")),
              ("exclusions", Json::array([])),
            ]),
            product_object([
              ("entry_id", Json::string("local-run-control")),
              ("principal", product_selector(principal)),
              ("connection", product_selector(connection)),
              ("resource", product_selector("run")),
              (
                "operation",
                product_object([
                  (
                    "any_of",
                    product_texts(["cancel", "publish", "read", "submit"]),
                  ),
                ]),
              ),
              ("outcome", Json::string("allow")),
              ("exclusions", Json::array([])),
            ]),
            product_object([
              ("entry_id", Json::string("local-worker-provisioning")),
              ("principal", product_selector(principal)),
              ("connection", product_selector(connection)),
              ("resource", product_selector("worker")),
              (
                "operation",
                product_object([
                  ("any_of", product_texts(["provision", "read"])),
                ]),
              ),
              ("outcome", Json::string("allow")),
              ("exclusions", Json::array([])),
            ]),
          ]),
        ),
      ]),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @authorization.admit_account_configuration_json(account) is Err(_) {
    return Err(ConfigurationLimit)
  }
  Ok({
    ..sdk,
    original: {
      ..sdk.original,
      common: { ..sdk.original.common, account: @utf8.encode(account), },
    },
  })
}
