///|
test "generated assembly registry ordering preserves Host preference and input ownership" {
  let registry = installation_registry()
  let first = capability_registration_at(registry, 0).unwrap()
  let third = capability_registration_at(registry, 2).unwrap()
  let input = [(third, 30), (first, 10)]
  let installed = install_capability_implementations(
    registry,
    input,
    2,
    registry_order=true,
  ).unwrap()
  assert_true(physical_equal(input[0].0, third))
  let order = capability_implementation_registrations(installed, 2).unwrap()
  assert_true(physical_equal(order[0], first))
  assert_true(physical_equal(order[1], third))
  assert_eq(capability_implementation(installed, first), Some(10))
  input.clear()
  assert_eq(capability_implementation(installed, third), Some(30))
  assert_true(
    install_capability_implementations(
      registry,
      [(third, 1), (third, 2)],
      2,
      registry_order=true,
    )
    is Err(DuplicateRegistration(1)),
  )
  assert_true(
    install_capability_implementations(
      registry,
      [(third, 1), (first, 2)],
      1,
      registry_order=true,
    )
    is Err(EntryLimit),
  )
  close_capability_registry(registry)
  assert_true(capability_implementation(installed, first) is None)
}

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
test "bundle projections preserve exact registrations order and live ownership" {
  let registry = installation_registry()
  let first = capability_registration_at(registry, 0).unwrap()
  let third = capability_registration_at(registry, 2).unwrap()
  let installed = install_capability_implementations(
    registry,
    [(third, (3, 30)), (first, (1, 10))],
    2,
  ).unwrap()
  let calls = Ref(0)
  assert_true(
    project_capability_implementations(
      installed,
      value => {
        calls.val += 1
        value.0
      },
      1,
    )
    is Err(EntryLimit),
  )
  assert_eq(calls.val, 0)
  let preparation = project_capability_implementations(
    installed,
    value => value.0,
    2,
  ).unwrap()
  let proposal = project_capability_implementations(
    installed,
    value => value.1,
    2,
  ).unwrap()
  assert_eq(capability_implementation(preparation, third), Some(3))
  assert_eq(capability_implementation(proposal, third), Some(30))
  let order = capability_implementation_registrations(proposal, 2).unwrap()
  assert_true(physical_equal(order[0], third))
  assert_true(physical_equal(order[1], first))
  let other = installation_registry()
  assert_true(
    capability_implementation(
      proposal,
      capability_registration_at(other, 2).unwrap(),
    )
    is None,
  )
  close_capability_registry(registry)
  assert_true(capability_implementation(preparation, first) is None)
  assert_true(capability_implementation(proposal, first) is None)
  assert_true(
    project_capability_implementations(installed, value => value.0, 2)
    is Err(RegistryClosed),
  )
}

///|
test "closing during projection cannot publish partially installed entrypoints" {
  let registry = installation_registry()
  let installed = install_capability_implementations(
    registry,
    [(capability_registration_at(registry, 0).unwrap(), 7)],
    1,
  ).unwrap()
  let calls = Ref(0)
  assert_true(
    project_capability_implementations(
      installed,
      value => {
        calls.val += 1
        close_capability_registry(registry)
        value
      },
      1,
    )
    is Err(RegistryClosed),
  )
  assert_eq(calls.val, 1)
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
