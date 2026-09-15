///|
/// Host-owned identity of a particular resource binding for one implementation.
/// This is distinct from registration, cost profile, input content and the live
/// resource instance. Minting it performs no I/O and grants no start permission.
/// Concrete configuration and handles remain in the connector's typed state.
struct ResourceBinding {
  registration : CapabilityRegistration
}

///|
pub fn prepare_resource_binding(
  registry : CapabilityRegistry,
  registration : CapabilityRegistration,
) -> Result[ResourceBinding, CapabilityInstallationIssue] {
  if !registry.owner.live {
    return Err(RegistryClosed)
  }
  if !capability_registration_matches(registration, registry) {
    return Err(ForeignRegistration(0))
  }
  Ok({ registration, })
}

///|
pub fn resource_binding_registration(
  binding : ResourceBinding,
) -> CapabilityRegistration {
  binding.registration
}
