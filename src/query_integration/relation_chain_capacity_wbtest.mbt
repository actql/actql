///|
/// Use the existing checked fixture and actual registration/selection route.
/// This oracle checks declared allowances, not runtime heap measurements.
fn capacity_evidence_child_sum(
  sequence : @execution.GeneratedSequence,
  family : @local_connector.ManagedProvider,
) -> Int64 {
  let mut total = 0L
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    let selected = @execution.select_generated_sequence_step(
      sequence,
      @execution.generated_sequence_step_index_at(sequence, index).unwrap(),
    ).unwrap()
    let child = @local_connector.managed_provider_capacity(
      chain_evidence_provider(selected, family),
      selected,
    ).unwrap()
    total += child.retained_bytes + child.execution_bytes
  }
  total
}

///|
fn capacity_evidence_family(
  sequence : @execution.GeneratedSequence,
  capacity : @execution.ExecutionCapacity,
) -> @local_connector.ManagedProvider {
  let actual = chain_evidence_family(sequence, chain_evidence_probe())
  @local_connector.managed_provider(
    s => @local_connector.managed_provider_accepts(actual, s),
    _ => Some(capacity),
    fn(s, inputs, rows, bytes, limits) {
      @local_connector.start_managed_provider_with_execution(
        actual, s, inputs, rows, bytes, limits,
      )
    },
  )
}

///|
test "capacity evidence declared child sums match the actual registered chain" {
  for count in [2, 3, 4] {
    let sequence = chain_evidence_sequence(count, select_last=count > 2)
    let family = chain_evidence_family(sequence, chain_evidence_probe())
    let provider = chain_evidence_provider(sequence, family)
    let actual = @local_connector.managed_provider_capacity(provider, sequence).unwrap()
    let limits = dispatch_test_limits()
    let base = @execution.generated_sequence_capacity(
      sequence,
      limits.local_execution,
      limits.guards,
    ).unwrap()
    let children = capacity_evidence_child_sum(sequence, family)
    assert_eq(actual.retained_bytes, base.retained_bytes)
    assert_eq(
      actual.execution_bytes,
      // Multi-step input selection and producer read retain two metadata handles.
      // This checks the declared reservation, not a physical sizing theorem.
      Int64::max(
        base.execution_bytes,
        children + count.to_int64() * 256L + 512L,
      ),
    )
    // A max(child) mutation must not substitute a serial execution argument
    // for the actual overlap of retained children.
    assert_true(actual.execution_bytes >= children)
  }
}

///|
test "capacity evidence actual Int64 guards reject child sum and handle overflow" {
  let sequence = chain_evidence_sequence(2)
  let zero = capacity_evidence_family(
    sequence,
    @execution.execution_capacity(0L, 0L).unwrap(),
  )
  let suffix = capacity_evidence_child_sum(sequence, zero)
  let handles = 2L * 256L
  let preparation = 512L
  let maximum = 9223372036854775807L
  let get = fn(retained : Int64, execution : Int64) raise {
    let family = capacity_evidence_family(
      sequence,
      @execution.execution_capacity(retained, execution).unwrap(),
    )
    let registry = search_registry()
    let limits = dispatch_test_limits()
    match
      @local_connector.prepare_local_compute_module(
        registry,
        @connector.capability_registration_at(registry, 0).unwrap(),
        [sequence],
        limits.local_execution,
        limits.guards,
        limits.candidate_work,
        1,
        managed_providers=[family],
      ) {
      // The selected provider's capacity is checked before installation. A
      // successful module must retain a finite quote, never a later None.
      Err(ForeignPreparation) => None
      Err(_) => fail("capacity fixture refused outside its overflow admission")
      Ok(installed) =>
        Some(
          @local_connector.managed_provider_capacity(
            @local_connector.local_module_managed_provider(
              installed, 0, sequence,
            ).unwrap(),
            sequence,
          ).unwrap(),
        )
    }
  }
  // Overflow inside a single child's retained+execution pair.
  assert_true(get(maximum, maximum) is None)
  // The pair fits, but the next child's addition cannot fit.
  assert_true(get(0L, maximum) is None)
  // Child accumulation fits exactly; adding actual parent handles cannot.
  assert_true(get(0L, maximum - suffix) is None)
  // Child and handle sums fit exactly, but metadata preparation cannot.
  assert_true(get(0L, maximum - suffix - handles) is None)
  // Every declared term fits exactly; one additional byte must be refused.
  let exact = get(0L, maximum - suffix - handles - preparation).unwrap()
  assert_eq(exact.execution_bytes, maximum)
  assert_true(get(0L, maximum - suffix - handles - preparation + 1L) is None)
  assert_true(@execution.execution_capacity(-1L, 0L) is None)
  assert_true(@execution.execution_capacity(1L, 0L) is None)
}

///|
test "capacity evidence live predecessor survives handoff and cleanup pending" {
  let sequence = chain_evidence_sequence(3, select_last=true)
  let probe = chain_evidence_probe(delay_cleanup=true)
  let provider = chain_evidence_provider(
    sequence,
    chain_evidence_family(sequence, probe),
  )
  let active = @local_connector.start_managed_provider_with_execution(
    provider,
    sequence,
    [],
    100,
    10000,
    dispatch_test_limits().local_execution,
  ).unwrap()
  for _ in 0..<4 {
    assert_true(
      @local_connector.advance_managed_provider(active, 1).unwrap()
      is @local_connector.Continue(_),
    )
  }
  let old = probe.output.unwrap()
  assert_true(@execution.completed_output_available(old))
  // Handoff starts a different child while the old output is still alive.
  assert_true(
    @local_connector.advance_managed_provider(active, 1).unwrap()
    is @local_connector.Continue(work=1L, ..),
  )
  assert_true(@execution.completed_output_available(old))
  assert_false(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_eq(probe.cleanup_calls, 0)
  let mut completed = false
  for _ in 0..<200 {
    if !completed {
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(_) => ()
        @local_connector.Complete(output, ..) => {
          assert_eq(@execution.completed_row_count(output), 3)
          completed = true
        }
        _ => fail("unexpected capacity lifetime observation")
      }
      assert_true(@execution.completed_output_available(old))
    }
  }
  assert_true(completed)
  let starts = probe.starts
  let advances = probe.advances
  assert_true(@local_connector.managed_provider_stopped(active))
  assert_false(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@execution.completed_output_available(old))
  assert_true(@local_connector.cleanup_managed_provider(active) is Err(_))
  assert_true(@execution.completed_output_available(old))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_eq(probe.cleanup_calls, 3)
  assert_eq(probe.starts, starts)
  assert_eq(probe.advances, advances)
  // Do not assert physical reclamation: an accepted descendant may still own
  // the output. Session cleanup and retained-output lifetime are separate.
}
