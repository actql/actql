///|
test "module one-short growth refuses before factory while exact boundary preserves same original" {
  // Calibration reads the actual admitted requirement for this fixed authored
  // input. It is not an independent assertion that the quote is a minimum.
  let (probe, probe_ledger, env, public_env, contracts, manifests) = closed_module_fixture()
  prepare_closed_values_module_body(
    probe,
    env,
    public_env,
    contracts,
    manifests,
    retained_output=true,
    provider_factory=_ => [],
    family_retained=closed_module_no_family,
    family_array=closed_module_empty_factory_array,
    family_temporary=closed_module_no_family,
  ).unwrap()
  let required_r = probe.retained_quote
  let required_e = probe.execution_quote
  println("MODULE_BOUNDARY retained=\{required_r} execution=\{required_e}")
  abort_closed_values_preparation_after_cleanup(probe).unwrap()
  assert_eq(@resources.ledger_usage(probe_ledger).reserved_retention_bytes, 0L)
  for dimension in ["retention", "execution"] {
    for short in [true, false] {
      let (
        owner,
        ledger,
        environment,
        public_environment,
        original_contracts,
        original_manifests,
      ) = closed_module_fixture()
      let limits = @resources.ledger_limits(ledger)
      let other = @resources.reserve_capacity(
        ledger,
        if dimension == "retention" {
          limits.retained_bytes - required_r + (if short { 1L } else { 0L })
        } else {
          0L
        },
        if dimension == "execution" {
          limits.execution_bytes - required_e + (if short { 1L } else { 0L })
        } else {
          0L
        },
      ).unwrap()
      let calls = Ref(0)
      let outcome = prepare_closed_values_module_body(
        owner,
        environment,
        public_environment,
        original_contracts,
        original_manifests,
        retained_output=true,
        provider_factory=_ => {
          calls.val += 1
          []
        },
        family_retained=closed_module_no_family,
        family_array=closed_module_empty_factory_array,
        family_temporary=closed_module_no_family,
      )
      if short {
        guard outcome is Err(CapacityExceeded(facts)) else {
          fail("expected original bounded growth refusal")
        }
        assert_eq(facts.dimension, dimension)
        assert_eq(calls.val, 0)
        assert_true(owner.prepared is None)
        assert_true(owner.source_free is None)
        assert_false(owner.module_constructing)
      } else {
        assert_true(outcome is Ok(_))
        assert_eq(calls.val, 1)
        assert_eq(owner.retained_quote, required_r)
        assert_eq(owner.execution_quote, required_e)
        assert_true(owner.source_free.unwrap().configuration is Some(_))
      }
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      // The independent competing reservation still prevents the SAME child
      // from reporting/stopping; cleanup must not invent an empty census.
      assert_true(
        abort_closed_values_preparation_after_cleanup(owner)
        is Err(Initial(@resources.Unavailable)),
      )
      assert_true(owner.retiring)
      @resources.settle_capacity(ledger, other).unwrap()
      abort_closed_values_preparation_after_cleanup(owner).unwrap()
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    }
  }
}

///|
test "invalid fixed module recipe keeps original partial preparation and activates no factory" {
  let (owner, ledger, environment, public_environment, contracts, manifests) = closed_module_fixture()
  let calls = Ref(0)
  let outcome = prepare_closed_values_module_body(
    owner,
    environment,
    public_environment,
    contracts,
    manifests,
    retained_output=false,
    provider_factory=_ => {
      calls.val += 1
      []
    },
    family_retained={ ..closed_module_no_family, record_headers: -1L, },
    family_array=closed_module_empty_factory_array,
    family_temporary=closed_module_no_family,
  )
  assert_true(outcome is Err(Policy))
  assert_eq(calls.val, 0)
  assert_false(owner.module_constructing)
  assert_true(owner.program is Some(_))
  assert_true(owner.prepared is None)
  assert_true(@resources.ledger_usage(ledger).reserved_retention_bytes > 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  abort_closed_values_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}
