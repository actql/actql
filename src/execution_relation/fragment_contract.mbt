///|
/// Registered execution contract, not admission of a particular fragment.
priv struct FragmentContract {
  relations : RegisteredRelationContracts
  cid : String
}

///|
priv enum FragmentContractIssue {
  InvalidLimits
  BodyLimit
  ContractMismatch
}

///|
fn admit_fragment_contract(
  relations : RegisteredRelationContracts,
  body : @identity.CanonicalValue,
  limits : RegistryLimits,
) -> Result[FragmentContract, FragmentContractIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 1 ||
    limits.max_body_depth < 0 {
    return Err(InvalidLimits)
  }
  let cid = @identity.cid_value(
    body,
    limits.max_body_bytes,
    limits.max_body_nodes,
    limits.max_body_depth,
  ) catch {
    _ => return Err(BodyLimit)
  }
  if cid != selected_fragment_contract_cid ||
    relations.registry_cid != selected_registry_cid {
    return Err(ContractMismatch)
  }
  Ok({ relations, cid, })
}
