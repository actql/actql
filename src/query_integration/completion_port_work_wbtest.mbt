///|
/// Independent fixture formula for ASCII completion IDs and field names.
/// The scalar cursor scans the ID twice, compares it once, then scans each name.
/// Three ID phase boundaries, one end per name and final completion are work.
/// This is not a general Unicode formula or a reading of execution counters.
/// Selected Append/Filter/projections reuse admitted metadata instead of this cursor.
fn expected_ascii_completion_port_work(
  id : String,
  names : Array[String],
) -> Int {
  let mut characters = 0
  for name in names {
    characters += name.length()
  }
  3 * id.length() + characters + names.length() + 4
}

///|
/// Exercise each real selected child independently before checking chain work.
/// Expected phase counts are supplied by the fixture, never by this observer.
fn assert_source_free_child_work(
  generated : @execution.GeneratedSequence,
  expected : Array[Int],
) -> Unit raise {
  let owner = @execution.generated_sequence_owner(generated)
  let defaults = dispatch_test_limits()
  let registry = search_registry()
  let mut previous : @execution.CompletedOutput? = None
  for position, work in expected {
    let step = @execution.generated_sequence_step_index_at(generated, position).unwrap()
    let selected = @execution.select_generated_sequence_step(generated, step).unwrap()
    let installed = @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      [selected],
      defaults.local_execution,
      defaults.guards,
      defaults.candidate_work,
      1,
    ).unwrap()
    let provider = @local_connector.local_module_managed_provider(
      installed, 0, selected,
    ).unwrap()
    let inputs = match previous {
      None => []
      Some(output) =>
        [
          @local_connector.managed_provider_relation_input(
            @execution.prepare_producer_read(
              owner,
              @execution.bind_completed_operation_input(
                owner, step, 0, owner, output,
              ).unwrap(),
              10000,
              10000,
            ).unwrap(),
          ),
        ]
    }
    let active = @local_connector.start_managed_provider_with_inputs_and_execution(
      provider,
      selected,
      inputs,
      100,
      10000,
      defaults.local_execution,
    ).unwrap()
    let mut completed : @execution.CompletedOutput? = None
    let mut charged = 0L
    for _ in 0..<(work + 2) {
      if completed is Some(_) {
        break
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work~, ..) => charged += work
        @local_connector.Complete(output, work~, ..) => {
          charged += work
          completed = Some(output)
        }
        _ => fail("selected child did not complete")
      }
    }
    assert_eq(
      charged,
      work.to_int64(),
      msg="selected child " + position.to_string(),
    )
    assert_true(completed is Some(_))
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    previous = completed
  }
}
