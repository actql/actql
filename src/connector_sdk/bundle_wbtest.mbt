///|
test "bundle manifest validates before factories and isolates immutable Host installations" {
  let calls = Ref(0)
  let bundle : CapabilityBundle[Int, CapabilityRegistration, Unit] = {
    name: "compute-only",
    acquisition: None,
    fixed_compute: Some(fn(_registry, registration) {
      calls.val += 1
      registration
    }),
    effect: None,
  }
  assert_true(
    install_bundles([bundle, bundle], 2, 100) is Err(DuplicateName(1)),
  )
  assert_eq(calls.val, 0)
  let manifest = [bundle]
  let first = install_bundles(manifest, 1, 100).unwrap()
  manifest.clear()
  let second = install_bundles([bundle], 1, 100).unwrap()
  assert_eq(calls.val, 2)
  let registration = capability_registration_at(
    installed_bundle_registry(first),
    0,
  ).unwrap()
  assert_false(capability_description(registration).acquisition)
  assert_true(capability_description(registration).fixed_compute)
  assert_true(
    capability_implementation(
      installed_acquisition_implementations(first),
      registration,
    )
    is None,
  )
  assert_true(
    physical_equal(
      capability_implementation(
        installed_compute_implementations(first),
        registration,
      ).unwrap(),
      registration,
    ),
  )
  assert_true(
    capability_implementation(
      installed_compute_implementations(second),
      registration,
    )
    is None,
  )
  close_capability_registry(installed_bundle_registry(first))
  assert_true(
    capability_implementation(
      installed_compute_implementations(first),
      registration,
    )
    is None,
  )
  assert_true(
    capability_registration_at(installed_bundle_registry(second), 0) is Some(_),
  )
}

///|
test "effect-only bundle installs under one owned registration" {
  let calls = Ref(0)
  let bundle : CapabilityBundle[Unit, Unit, CapabilityRegistration] = {
    name: "write-only",
    acquisition: None,
    fixed_compute: None,
    effect: Some(fn(_registry, registration) {
      calls.val += 1
      registration
    }),
  }
  let installed = install_bundles([bundle], 1, 100).unwrap()
  assert_eq(calls.val, 1)
  let registry = installed_bundle_registry(installed)
  let registration = capability_registration_at(registry, 0).unwrap()
  let description = capability_description(registration)
  assert_false(description.acquisition)
  assert_false(description.fixed_compute)
  assert_true(description.effect)
  assert_true(
    capability_implementation(
      installed_acquisition_implementations(installed),
      registration,
    )
    is None,
  )
  assert_true(
    capability_implementation(
      installed_compute_implementations(installed),
      registration,
    )
    is None,
  )
  assert_true(
    physical_equal(
      capability_implementation(
        installed_effect_implementations(installed),
        registration,
      ).unwrap(),
      registration,
    ),
  )
  close_capability_registry(registry)
  assert_true(
    capability_implementation(
      installed_effect_implementations(installed),
      registration,
    )
    is None,
  )
}
