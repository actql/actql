///|
test "chain carrier rejection retains terminal work through cleanup" {
  let source = carrier_graph_source_owner()
  let graph = carrier_graph_match_owner(source, "[1]")
  let material = carrier_match_graph_material(graph, source)
  let sequence = chain_evidence_sequence(2)
  let actual = chain_evidence_family(sequence, chain_evidence_probe())
  let stopped = Ref(false)
  let starts = Ref(0)
  let cleanup_calls = Ref(0)
  let child : Ref[@local_connector.ManagedProviderExecution?] = Ref(None)
  let family = @local_connector.managed_provider(
    s => @local_connector.managed_provider_accepts(actual, s),
    s => @local_connector.managed_provider_capacity(actual, s),
    fn(_, _, _, _, _) {
      starts.val += 1
      let owner = @local_connector.managed_provider_execution(
        fn(_) {
          stopped.val = true
          Ok(
            @local_connector.managed_provider_carrier_complete(material, 0L, 1L),
          )
        },
        fn() { false },
        fn() { stopped.val },
        fn() {
          cleanup_calls.val += 1
          @carrier_runtime.reclaim_material(material) |> ignore
          Ok(true)
        },
      )
      child.val = Some(owner)
      Ok(owner)
    },
  )
  let chain = @local_connector.start_managed_provider_with_execution(
    chain_evidence_provider(sequence, family),
    sequence,
    [],
    100,
    10000,
    { ..dispatch_test_limits().local_execution, max_work: 10, },
  ).unwrap()
  let result = @local_connector.advance_managed_provider(chain, 1).unwrap()
  assert_true(
    result
    is @local_connector.Failed(
      @connector.Execution(@execution.InputSet),
      progress=0L,
      work=1L
    ),
  )
  assert_eq(
    @local_connector.managed_provider_cumulative_work(child.val.unwrap()),
    Ok(1L),
  )
  assert_eq(@local_connector.managed_provider_cumulative_work(chain), Ok(1L))
  assert_eq(starts.val, 1) // A wrong carrier never starts the successor.
  assert_true(@local_connector.managed_provider_stopped(chain))
  assert_true(@local_connector.advance_managed_provider(chain, 1) is Err(_))
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_eq(cleanup_calls.val, 1)
  assert_eq(
    @local_connector.managed_provider_cumulative_work(child.val.unwrap()),
    Ok(1L),
  )
  assert_eq(@local_connector.managed_provider_cumulative_work(chain), Ok(1L))
}

///|
test "zero work Continue latches accounting failure through stop and cleanup" {
  let cancelled = Ref(false)
  let stopped = Ref(false)
  let productive = Ref(0)
  let cleanup_calls = Ref(0)
  let owner = @local_connector.managed_provider_execution(
    fn(_) {
      if stopped.val {
        return Err(@connector.InvalidLimits)
      }
      if cancelled.val {
        stopped.val = true
        Ok(@local_connector.managed_provider_stopped_poll(0L, 0L))
      } else {
        productive.val += 1
        Ok(@local_connector.managed_provider_continue(0L, 0L))
      }
    },
    fn() {
      let changed = !cancelled.val
      cancelled.val = true
      changed
    },
    fn() { stopped.val },
    fn() {
      if !stopped.val {
        return Ok(false)
      }
      if cleanup_calls.val >= 3 {
        return Ok(true)
      }
      cleanup_calls.val += 1
      match cleanup_calls.val {
        1 => Ok(false)
        2 => Err(@connector.InvalidLimits)
        _ => Ok(true)
      }
    },
  )
  @local_connector.advance_managed_provider(owner, 1).unwrap() |> ignore
  assert_eq(
    @local_connector.managed_provider_cumulative_work(owner),
    Err(@local_connector.InvalidReport),
  )
  assert_true(cancelled.val)
  assert_false(@local_connector.managed_provider_stopped(owner))
  assert_false(@local_connector.cleanup_managed_provider(owner).unwrap())
  assert_true(
    @local_connector.advance_managed_provider(owner, 1).unwrap()
    is @local_connector.Stopped(work=0L, ..),
  )
  assert_eq(productive.val, 1)
  assert_false(@local_connector.cleanup_managed_provider(owner).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(owner) is Err(_))
  assert_eq(
    @local_connector.managed_provider_cumulative_work(owner),
    Err(@local_connector.InvalidReport),
  )
  assert_true(@local_connector.cleanup_managed_provider(owner).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(owner).unwrap())
  assert_eq(cleanup_calls.val, 3)
  assert_true(@local_connector.advance_managed_provider(owner, 1) is Err(_))
  assert_eq(
    @local_connector.managed_provider_cumulative_work(owner),
    Err(@local_connector.InvalidReport),
  )
}

///|
test "zero work terminal provider polls remain valid accounting reports" {
  let source = carrier_graph_source_owner()
  let output = carrier_events_source_output(source)
  let graph = carrier_graph_match_owner(source, "[1]")
  let material = carrier_match_graph_material(graph, source)
  let polls = [
    @local_connector.managed_provider_complete(output, 0L, 0L),
    @local_connector.managed_provider_carrier_complete(material, 0L, 0L),
    @local_connector.managed_provider_failed(@connector.InvalidLimits, 0L, 0L),
    @local_connector.managed_provider_stopped_poll(0L, 0L),
  ]
  for poll in polls {
    let cancellations = Ref(0)
    let owner = @local_connector.managed_provider_execution(
      _ => Ok(poll),
      fn() {
        cancellations.val += 1
        true
      },
      fn() { true },
      fn() { Ok(true) },
    )
    @local_connector.advance_managed_provider(owner, 1).unwrap() |> ignore
    assert_eq(@local_connector.managed_provider_cumulative_work(owner), Ok(0L))
    assert_eq(cancellations.val, 0)
    assert_true(@local_connector.cleanup_managed_provider(owner).unwrap())
    assert_eq(@local_connector.managed_provider_cumulative_work(owner), Ok(0L))
  }
  @carrier_runtime.reclaim_material(material) |> ignore
}
