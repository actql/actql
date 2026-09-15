///|
/// Fixed Host installation. T is an implementation entry (usually a closure or
/// interface); the SDK never inspects provider payloads or dispatches by name.
/// Entries cannot be added or replaced after installation.
struct CapabilityImplementations[T] {
  registry : CapabilityRegistry
  entries : Array[(CapabilityRegistration, T)]
}

///|
/// Exact owned registry, including for an empty installation. Reading this
/// handle does not restore its liveness or add implementations.
pub fn[T] capability_implementations_registry(
  installed : CapabilityImplementations[T],
) -> CapabilityRegistry {
  installed.registry
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
/// Generated composition can request registry order so file enumeration does
/// not become Host preference. The default preserves the supplied entry order.
pub fn[T] install_capability_implementations(
  registry : CapabilityRegistry,
  entries : Array[(CapabilityRegistration, T)],
  max_entries : Int,
  registry_order? : Bool = false,
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
  let owned = entries.copy()
  if registry_order {
    owned.sort_by((left, right) => left.0.position.compare(right.0.position))
  }
  Ok({ registry, entries: owned, })
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

///|
/// Snapshot of this immutable installation's exact registrations. Identity is
/// retained after closure; actual implementation lookup still checks liveness.
pub fn[T] capability_implementation_registrations(
  installed : CapabilityImplementations[T],
  max_entries : Int,
) -> Array[CapabilityRegistration]? {
  if max_entries < 0 || installed.entries.length() > max_entries {
    return None
  }
  Some(installed.entries.map(entry => entry.0))
}

///|
/// Project entrypoints from one immutable bundle installation, preserving exact
/// registration ownership and order. The trusted projector is pure wiring, not
/// execution; it cannot add registrations or migrate them to another registry.
pub fn[T, U] project_capability_implementations(
  installed : CapabilityImplementations[T],
  project : (T) -> U,
  max_entries : Int,
) -> Result[CapabilityImplementations[U], CapabilityInstallationIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if installed.entries.length() > max_entries {
    return Err(EntryLimit)
  }
  if !installed.registry.owner.live {
    return Err(RegistryClosed)
  }
  let entries = []
  for (registration, implementation) in installed.entries {
    let projected = project(implementation)
    if !installed.registry.owner.live {
      return Err(RegistryClosed)
    }
    entries.push((registration, projected))
  }
  Ok({ registry: installed.registry, entries, })
}
