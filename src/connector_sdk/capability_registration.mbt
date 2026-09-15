///|
/// Host-selected module capabilities, not source permission or semantic proof.
/// One module can provide Acquisition and fixed-input Compute independently.
pub(all) struct CapabilityDescription {
  name : String
  acquisition : Bool
  fixed_compute : Bool
}

///|
pub(all) enum CapabilityRegistrationIssue {
  InvalidLimits
  EntryLimit
  NameLimit
  EmptyName(Int)
  NoCapabilities(Int)
  DuplicateName(Int)
}

///|
struct CapabilityRegistry {
  owner : CapabilityRegistryOwner
  entries : Array[CapabilityRegistration]
}

///|
priv struct CapabilityRegistryOwner {
  mut live : Bool
}

///|
struct CapabilityRegistration {
  owner : CapabilityRegistryOwner
  position : Int
  description : CapabilityDescription
}

///|
/// Pure, bounded Host setup. Entries and descriptions are snapshotted; registration
/// order and diagnostic names are not canonical Plan or acquisition identities.
pub fn prepare_capability_registry(
  descriptions : Array[CapabilityDescription],
  max_entries : Int,
  max_name_units : Int,
) -> Result[CapabilityRegistry, CapabilityRegistrationIssue] {
  if max_entries < 0 || max_name_units < 0 {
    return Err(InvalidLimits)
  }
  if descriptions.length() > max_entries {
    return Err(EntryLimit)
  }
  let registry : CapabilityRegistry = { owner: { live: true, }, entries: [], }
  let names : Map[String, Bool] = Map([])
  let mut remaining = max_name_units
  for index, description in descriptions {
    if description.name.is_empty() {
      return Err(EmptyName(index))
    }
    if description.name.length() > remaining {
      return Err(NameLimit)
    }
    remaining -= description.name.length()
    if !description.acquisition && !description.fixed_compute {
      return Err(NoCapabilities(index))
    }
    if names.contains(description.name) {
      return Err(DuplicateName(index))
    }
    names[description.name] = true
    registry.entries.push({
      owner: registry.owner,
      position: index,
      description,
    })
  }
  Ok(registry)
}

///|
pub fn capability_registration_at(
  registry : CapabilityRegistry,
  index : Int,
) -> CapabilityRegistration? {
  if registry.owner.live {
    registry.entries.get(index)
  } else {
    None
  }
}

///|
pub fn capability_description(
  value : CapabilityRegistration,
) -> CapabilityDescription {
  value.description
}

///|
pub fn capability_registration_available(
  value : CapabilityRegistration,
) -> Bool {
  value.owner.live
}

///|
pub fn capability_registration_matches(
  value : CapabilityRegistration,
  registry : CapabilityRegistry,
) -> Bool {
  registry.owner.live && physical_equal(value.owner, registry.owner)
}

///|
/// Disable future proposals/dispatch recovery without touching completed outputs.
pub fn close_capability_registry(registry : CapabilityRegistry) -> Unit {
  registry.owner.live = false
}
