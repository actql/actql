///|
/// Rebuild-time module contributions. Capability presence comes from actual
/// entrypoints, not a second list of capability flags. These factories are
/// trusted, pure bootstrap code; they receive their exact Host registration.
pub(all) struct CapabilityBundle[A, C] {
  name : String
  acquisition : ((CapabilityRegistry, CapabilityRegistration) -> A)?
  fixed_compute : ((CapabilityRegistry, CapabilityRegistration) -> C)?
}

///|
struct InstalledBundles[A, C] {
  registry : CapabilityRegistry
  acquisition : CapabilityImplementations[A]
  fixed_compute : CapabilityImplementations[C]
}

///|
/// Validate the complete manifest before invoking any factory. Installation
/// snapshots the contributions; there is no append, replacement or dynamic
/// load operation. Resource bindings and fixed input locations are not module
/// identities and are supplied to the installed operations separately.
pub fn[A, C] install_bundles(
  bundles : Array[CapabilityBundle[A, C]],
  max_entries : Int,
  max_name_units : Int,
) -> Result[InstalledBundles[A, C], CapabilityRegistrationIssue] {
  if max_entries < 0 || max_name_units < 0 {
    return Err(InvalidLimits)
  }
  if bundles.length() > max_entries {
    return Err(EntryLimit)
  }
  let owned = bundles.copy()
  let registry = match
    prepare_capability_registry(
      owned.map(bundle => {
        name: bundle.name,
        acquisition: bundle.acquisition is Some(_),
        fixed_compute: bundle.fixed_compute is Some(_),
      }),
      max_entries,
      max_name_units,
    ) {
    Err(issue) => return Err(issue)
    Ok(registry) => registry
  }
  let acquisition = []
  let fixed_compute = []
  for index, bundle in owned {
    let registration = registry.entries[index]
    if bundle.acquisition is Some(prepare) {
      acquisition.push((registration, prepare(registry, registration)))
    }
    if bundle.fixed_compute is Some(prepare) {
      fixed_compute.push((registration, prepare(registry, registration)))
    }
  }
  // The arrays above contain exactly this registry's registrations once each.
  // A factory may close its registry; that makes both installations unusable,
  // rather than restoring liveness or panicking in a post-factory constructor.
  Ok({
    registry,
    acquisition: { registry, entries: acquisition, },
    fixed_compute: { registry, entries: fixed_compute, },
  })
}

///|
pub fn[A, C] installed_bundle_registry(
  installed : InstalledBundles[A, C],
) -> CapabilityRegistry {
  installed.registry
}

///|
pub fn[A, C] installed_acquisition_implementations(
  installed : InstalledBundles[A, C],
) -> CapabilityImplementations[A] {
  installed.acquisition
}

///|
pub fn[A, C] installed_compute_implementations(
  installed : InstalledBundles[A, C],
) -> CapabilityImplementations[C] {
  installed.fixed_compute
}
