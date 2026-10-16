// Test-only typed projection into actual Common owners. No substitute parser,
// issuer, grant or production import; selected bounds match the Host fixture.

///|
#export_name("fixtureGcsOriginalStorePair")
pub fn fixture_gcs_original_store_pair(
  environment : @program.CheckEnvironment,
) -> Result[@environment.StoreCommandBinding, String] {
  let original = @program.checking_environment_wire(environment)
  let limits : @environment.Limits = {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 64,
    max_members: 100,
  }
  guard @environment.check_contract_registry(original, limits) is Ok(registry) &&
    @environment.check_catalog_contents(registry, limits) is Ok(catalogs) &&
    @environment.check_mapping_contract_shapes(original, limits, 1000000)
    is Ok(mappings) &&
    @environment.mapping_shape_at(mappings, 0) is Some(mapping) else {
    return Err("FixtureCommonAdmissionRejected")
  }
  @environment.bind_store_command(mapping, catalogs, 1000000).map_err(_ => {
    "FixtureCommonPairRejected"
  })
}

///|
#export_name("fixtureGcsReferenceWire")
pub fn fixture_gcs_reference_wire(value : @admitted.CheckedValue) -> String? {
  match value.value {
    Reference(reference) => Some(@admitted.reference_wire(reference))
    _ => None
  }
}

///|
#export_name("fixtureGcsReferenceAvailable")
pub fn fixture_gcs_reference_available(value : @admitted.CheckedValue) -> Bool {
  match value.value {
    Reference(reference) => @admitted.reference_available(reference)
    _ => false
  }
}
