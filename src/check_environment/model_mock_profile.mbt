///|
/// Source-pinned local fixture implementation. This original is neither a
/// live Provider, current Host, Account grant nor a physical resource supplier.
struct ModelMockProfile {
  mut original : ModelMockProfile?
  mut configuration : String?
  configuration_cid : String
  mut defaults : ModelProviderDefaults?
  execution_bounds : Array[(String, Int64)]
}

///|
fn model_mock_configuration_wire() -> String {
  // No network, credentials, training or Provider-side retained response exists
  // in this implementation. host-local-fixture identifies that implementation
  // scope, not a claim about a remote Provider's geographical processing.
  (
    #|{"model_defaults":{"default_model":"typed-answers","models":[{"data_handling":{"body":{"accepted_classifications":["public","internal","confidential","restricted"],"allowed_regions":["host-local-fixture"],"retention":"none","training_use":"forbidden"},"cid":"sha256:2a8b87c2c7b2a53bc668393360dc2b799269078748e5f5016ad3c1cc1e35452e","id":"actql-mock-model-handling","kind":"request_data_handling","schema":"actql.contract/0.1","version":"0.1"},"generation_config":{"max_output_tokens":1,"temperature":0,"top_p":1},"model":"typed-answers"}]},"provider_id":"mock","version":"actql-mock-model-configuration/0.1"}
  )
}

///|
fn model_mock_configuration_contract_wire() -> String {
  (
    #|{"credentials":false,"kind":"typed_answers","network":false,"provider_id":"mock","required":["model_defaults"],"version":"actql-mock-model-configuration-contract/0.1"}
  )
}

///|
fn model_mock_installation_revision_wire() -> String {
  (
    #|{"execution_profile_cid":"sha256:edadf04e63295c8f8212755301ed48e1ee7b060ec91b4d2519dbc512d5905ff7","implementation":"portable-typed-answers","provider_id":"mock","version":"actql-mock-model-installation/0.1"}
  )
}

///|
/// Install only the explicitly shipped typed-answer fixture profile. Real
/// Provider/default/handling configuration cannot be substituted into it.
/// Full construction, retained originals and emission workspace are Host funded.
pub fn install_model_mock_profile(
  limits : ModelTaskLimits,
) -> Result[ModelMockProfile, ModelTaskIssue] {
  if limits.max_work < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.bodies.max_members < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let wire = model_mock_configuration_wire()
  // Refuse before materializing the UTF-8 source. The parser accounts for its
  // own tree/work; this check retains the original body bound during encoding.
  if @scalar.admit_utf8_length(wire, limits.bodies.max_bytes) is Err(_) {
    return Err({ kind: BodyLimit, source: None, })
  }
  let (defaults, _, _, work) = match
    read_model_provider_defaults_configuration(
      @utf8.encode(wire),
      limits.bodies,
      limits.max_work,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard defaults is Some(defaults) else {
    return Err({ kind: ReferenceMismatch, source: None, })
  }
  let budget : ModelTaskBudget = {
    limits,
    work,
    contract_nodes: 0,
    contract_text: 0,
  }
  let execution_bounds = model_mock_execution_bounds(budget) catch {
    ModelTaskStop(issue) => return Err(issue)
  }
  let original : ModelMockProfile = {
    original: None,
    configuration: Some(wire),
    configuration_cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
    defaults: Some(defaults),
    execution_bounds,
  }
  original.original = Some(original)
  Ok(original)
}

///|
pub fn model_mock_profile_current(original : ModelMockProfile) -> Bool {
  original.original is Some(retained) &&
  physical_equal(original, retained) &&
  original.configuration is Some(_) &&
  original.execution_bounds.length() == 6 &&
  original.defaults is Some(_)
}

///|
/// Exact nonsecret installation/configuration originals, for the existing
/// Model binding and saved-material Owners. Equal bytes do not adopt this
/// nominal profile or a Host/Run/current authority.
pub fn model_mock_profile_originals(
  original : ModelMockProfile,
) -> (String, String, String, String, String, String)? {
  if !model_mock_profile_current(original) {
    return None
  }
  let revision = model_mock_installation_revision_wire()
  let contract = model_mock_configuration_contract_wire()
  Some(
    (
      revision,
      "sha256:" + @sha.hex(@utf8.encode(revision)),
      contract,
      "sha256:" + @sha.hex(@utf8.encode(contract)),
      original.configuration.unwrap(),
      original.configuration_cid,
    ),
  )
}

///|
/// Retire only this installation's DATA references. Escaped Task/answer values
/// and physical cleanup remain owned separately; this is no capacity ACK.
pub fn retire_model_mock_profile(original : ModelMockProfile) -> Bool {
  if !model_mock_profile_current(original) {
    return false
  }
  original.original = None
  original.configuration = None
  original.defaults = None
  original.execution_bounds.clear()
  true
}
