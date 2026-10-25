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
  value : ClientLocalSequenceContracts
}

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
/// Immutable installed contract DATA, not a Program or resource permission.
/// The installation retains this exact admitted four-wire closure; sequence
/// consumers neither reparse it nor consult process-global state.
struct ClientInstalledSequenceContracts {
  original : ClientLocalSequenceContractAdmission
}

///|
pub fn prepare_installed_sequence_contracts(
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[ClientInstalledSequenceContracts, ClientInstalledManagedRunIssue] {
  guard read_client_local_sequence_contracts(
      registry_body, values_body, fragment_body, ordered_body,
    )
    is Some(value) else {
    return Err(Unsupported)
  }
  Ok({
    original: {
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
      value,
    },
  })
}

///|
// Optional bodies select already admitted capabilities, not another admission.
// A Values-only prefix may omit fragment/ordered support from a fuller bundle.
fn client_local_sequence_selection_matches(
  installed : ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
) -> Bool {
  let original = installed.original
  original.values_body == values &&
  (fragment is None || fragment == original.fragment_body) &&
  (ordered is None || ordered == original.ordered_body)
}
