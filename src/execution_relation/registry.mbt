///|
/// Exact supported contract selection, not a backend or Program execution permit.
struct RegisteredRelationContracts {
  registry_cid : String
  values_contract_cid : String
}

///|
pub(all) struct RegistryLimits {
  max_body_bytes : Int
  max_body_nodes : Int
  max_body_depth : Int
}

///|
pub(all) enum RegistryIssue {
  InvalidRegistryLimits
  RegistryBodyLimit
  ValuesContractBodyLimit
  UnsupportedRegistry
  ValuesContractMismatch
} derive(Eq, Debug)

///|
/// Both arguments are already admitted immutable canonical values. Raw artifact
/// decoding and noncanonical-value rejection belong before this boundary.
/// Exact body identities commit to signatures, file/pointer and dependencies;
/// caller-supplied digest strings cannot substitute for the bodies.
pub fn admit_relation_registry(
  registry : @identity.CanonicalValue,
  values_contract : @identity.CanonicalValue,
  limits : RegistryLimits,
) -> Result[RegisteredRelationContracts, RegistryIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 0 ||
    limits.max_body_depth < 0 {
    return Err(InvalidRegistryLimits)
  }
  let registry_cid = @identity.cid_value(
    registry,
    limits.max_body_bytes,
    limits.max_body_nodes,
    limits.max_body_depth,
  ) catch {
    _ => return Err(RegistryBodyLimit)
  }
  if registry_cid != selected_registry_cid {
    return Err(UnsupportedRegistry)
  }
  let values_contract_cid = @identity.cid_value(
    values_contract,
    limits.max_body_bytes,
    limits.max_body_nodes,
    limits.max_body_depth,
  ) catch {
    _ => return Err(ValuesContractBodyLimit)
  }
  if values_contract_cid != selected_values_contract_cid {
    return Err(ValuesContractMismatch)
  }
  Ok({ registry_cid, values_contract_cid, })
}
