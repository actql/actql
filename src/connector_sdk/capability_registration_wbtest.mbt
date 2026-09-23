///|
test "capability registration is bounded owned and independent of caller arrays" {
  let description : CapabilityDescription = {
    name: "duckdb",
    acquisition: true,
    fixed_compute: true,
    effect: false,
  }
  let input = [description]
  let registry = prepare_capability_registry(input, 1, 6).unwrap()
  input.clear()
  let registration = capability_registration_at(registry, 0).unwrap()
  assert_eq(capability_description(registration).name, "duckdb")
  assert_true(capability_description(registration).acquisition)
  assert_true(capability_description(registration).fixed_compute)
  assert_true(capability_registration_matches(registration, registry))
  assert_true(capability_registration_at(registry, -1) is None)
  assert_true(capability_registration_at(registry, 1) is None)
  let same = prepare_capability_registry([description], 1, 6).unwrap()
  assert_false(capability_registration_matches(registration, same))
  close_capability_registry(registry)
  assert_false(capability_registration_matches(registration, registry))
  assert_true(capability_registration_at(registry, 0) is None)
  assert_true(capability_registration_at(same, 0) is Some(_))
  close_capability_registry(registry)
}

///|
test "capability declaration failures do not create a partial registry" {
  let entry : CapabilityDescription = {
    name: "local",
    acquisition: false,
    fixed_compute: true,
    effect: false,
  }
  assert_true(prepare_capability_registry([entry], -1, 5) is Err(InvalidLimits))
  assert_true(prepare_capability_registry([entry], 1, -1) is Err(InvalidLimits))
  assert_true(prepare_capability_registry([entry], 0, 5) is Err(EntryLimit))
  assert_true(prepare_capability_registry([entry], 1, 4) is Err(NameLimit))
  assert_true(prepare_capability_registry([entry], 1, 5) is Ok(_))
  assert_true(
    prepare_capability_registry([entry, entry], 2, 10) is Err(DuplicateName(1)),
  )
  assert_true(
    prepare_capability_registry([{ ..entry, name: "", }], 1, 5)
    is Err(EmptyName(0)),
  )
  assert_true(
    prepare_capability_registry(
      [{ ..entry, fixed_compute: false, effect: false, }],
      1,
      5,
    )
    is Err(NoCapabilities(0)),
  )
  assert_true(prepare_capability_registry([], 0, 0) is Ok(_))
}
