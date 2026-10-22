///|
priv struct ClientLocalSequenceContracts {
  contracts : @execution.RegisteredRelationContracts
  fragment_contract : @execution.FragmentContract?
  ordered_contract : @execution.RegisteredOrderedContract?
}

///|
priv struct ClientLocalSequenceContractAdmission {
  registry_body : String
  values_body : String
  fragment_body : String?
  ordered_body : String?
  value : ClientLocalSequenceContracts?
}

///|
let client_local_sequence_contract_admission : Ref[
  ClientLocalSequenceContractAdmission?,
] = Ref(None)

///|
fn read_client_local_sequence_contracts(
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientLocalSequenceContracts? {
  if registry_body.length() > 100000 || values_body.length() > 100000 {
    return None
  }
  let registry_value = @identity.from_json(
    @json.parse(registry_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return None
  }
  let values_value = @identity.from_json(
    @json.parse(values_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return None
  }
  let contracts = match
    @execution.admit_relation_registry(registry_value, values_value, {
      max_body_bytes: 100000,
      max_body_nodes: 10000,
      max_body_depth: 100,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let physical : @execution.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let fragment_contract = match fragment_body {
    None => None
    Some(body) => {
      if body.length() > 100000 {
        return None
      }
      let value = @identity.from_json(@json.parse(body), 10000, 100, 100000) catch {
        _ => return None
      }
      match @execution.admit_fragment_contract(contracts, value, physical) {
        Ok(contract) => Some(contract)
        Err(_) => return None
      }
    }
  }
  let ordered_contract = match ordered_body {
    None => None
    Some(body) => {
      if body.length() > 100000 {
        return None
      }
      let value = @identity.from_json(@json.parse(body), 10000, 100, 100000) catch {
        _ => return None
      }
      match @execution.admit_ordered_contract(contracts, value, physical) {
        Ok(contract) => Some(contract)
        Err(_) => return None
      }
    }
  }
  Some({ contracts, fragment_contract, ordered_contract, })
}

///|
fn client_local_sequence_contracts(
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  cached? : Ref[ClientLocalSequenceContractAdmission?] = client_local_sequence_contract_admission,
  read? : (String, String, String?, String?) -> ClientLocalSequenceContracts? = read_client_local_sequence_contracts,
) -> ClientLocalSequenceContracts? {
  // The retained entry is bounded immutable contract DATA, never a checked
  // Program, generated sequence, Run, physical supply or permission.
  if registry_body.length() > 100000 ||
    values_body.length() > 100000 ||
    (fragment_body is Some(body) && body.length() > 100000) ||
    (ordered_body is Some(body) && body.length() > 100000) {
    return None
  }
  // Exact complete wires select the immutable typed facts. Equal CIDs or a
  // changed optional extent cannot borrow an earlier admission. One entry
  // bounds retention; a changed input replaces only pure contract DATA.
  if cached.val is Some(original) &&
    original.registry_body == registry_body &&
    original.values_body == values_body &&
    original.fragment_body == fragment_body &&
    original.ordered_body == ordered_body {
    return original.value
  }
  let value = read(registry_body, values_body, fragment_body, ordered_body)
  cached.val = Some({
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    value,
  })
  value
}
