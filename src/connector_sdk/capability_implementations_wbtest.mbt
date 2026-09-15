///|
fn installation_registry() -> CapabilityRegistry {
  prepare_capability_registry(
    [
      { name: "first", acquisition: false, fixed_compute: true, },
      { name: "second", acquisition: true, fixed_compute: false, },
      { name: "third", acquisition: false, fixed_compute: true, },
    ],
    3,
    100,
  ).unwrap()
}

///|
test "installed entrypoints are snapshotted exact and never called by installation" {
  let registry = installation_registry()
  let first = capability_registration_at(registry, 0).unwrap()
  let second = capability_registration_at(registry, 1).unwrap()
  let third = capability_registration_at(registry, 2).unwrap()
  let calls = Ref(0)
  let entries : Array[(CapabilityRegistration, () -> Int)] = [
    (
      third,
      fn() {
        calls.val += 1
        33
      },
    ),
    (
      first,
      fn() {
        calls.val += 1
        11
      },
    ),
  ]
  let installed = install_capability_implementations(registry, entries, 2).unwrap()
  assert_eq(calls.val, 0)
  entries.clear()
  let invoke = capability_implementation(installed, first).unwrap()
  assert_eq(calls.val, 0)
  assert_eq(invoke(), 11)
  let invoke = capability_implementation(installed, third).unwrap()
  assert_eq(invoke(), 33)
  assert_eq(calls.val, 2)
  assert_true(capability_implementation(installed, second) is None)
  let other = installation_registry()
  assert_true(
    capability_implementation(
      installed,
      capability_registration_at(other, 0).unwrap(),
    )
    is None,
  )
  close_capability_registry(registry)
  assert_true(capability_implementation(installed, first) is None)
  assert_true(capability_registration_at(other, 0) is Some(_))
}

///|
test "installation rejects duplicate foreign closed and over-budget registrations" {
  let registry = installation_registry()
  let first = capability_registration_at(registry, 0).unwrap()
  let foreign = capability_registration_at(installation_registry(), 0).unwrap()
  assert_true(
    install_capability_implementations(registry, [(first, 1)], -1)
    is Err(InvalidLimits),
  )
  assert_true(
    install_capability_implementations(registry, [(first, 1)], 0)
    is Err(EntryLimit),
  )
  assert_true(
    install_capability_implementations(registry, [(first, 1), (first, 2)], 2)
    is Err(DuplicateRegistration(1)),
  )
  assert_true(
    install_capability_implementations(registry, [(first, 1), (foreign, 2)], 2)
    is Err(ForeignRegistration(1)),
  )
  let empty : CapabilityImplementations[Int] = install_capability_implementations(
    registry,
    [],
    0,
  ).unwrap()
  assert_true(capability_implementation(empty, first) is None)
  close_capability_registry(registry)
  assert_true(
    install_capability_implementations(registry, [(first, 1)], 1)
    is Err(RegistryClosed),
  )
}
