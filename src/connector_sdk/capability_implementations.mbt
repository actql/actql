///|
/// Fixed Host installation. T is an implementation entry (usually a closure or
/// interface); the SDK never inspects provider payloads or dispatches by name.
/// Entries cannot be added or replaced after installation.
struct CapabilityImplementations[T] {
  registry : CapabilityRegistry
  entries : Array[(CapabilityRegistration, T)]
}

///|
pub(all) enum CapabilityInstallationIssue {
  InvalidLimits
  EntryLimit
  RegistryClosed
  ForeignRegistration(Int)
  DuplicateRegistration(Int)
}

///|
/// Pure installation of an explicit subset of this Host's registrations. An
/// absent entry means this installation does not provide that operation. This
/// neither calls implementations nor grants source or execution authority.
pub fn[T] install_capability_implementations(
  registry : CapabilityRegistry,
  entries : Array[(CapabilityRegistration, T)],
  max_entries : Int,
) -> Result[CapabilityImplementations[T], CapabilityInstallationIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if entries.length() > max_entries {
    return Err(EntryLimit)
  }
  if !registry.owner.live {
    return Err(RegistryClosed)
  }
  // Registration position is private, bounded and stable for this registry.
  // It is not an implementation ID, semantic identity or resource binding.
  let seen : Map[Int, Bool] = Map([])
  for index, (registration, _) in entries {
    if !capability_registration_matches(registration, registry) {
      return Err(ForeignRegistration(index))
    }
    if seen.contains(registration.position) {
      return Err(DuplicateRegistration(index))
    }
    seen[registration.position] = true
  }
  Ok({ registry, entries: entries.copy(), })
}

///|
/// Exact registration lookup. Equal descriptions from another Host do not
/// recover an implementation. Closing the registry disables future recovery;
/// this is not unloading or cancellation of an already-started implementation.
pub fn[T] capability_implementation(
  installed : CapabilityImplementations[T],
  registration : CapabilityRegistration,
) -> T? {
  if !capability_registration_matches(registration, installed.registry) {
    return None
  }
  for (owned, implementation) in installed.entries {
    if physical_equal(owned, registration) {
      return Some(implementation)
    }
  }
  None
}
