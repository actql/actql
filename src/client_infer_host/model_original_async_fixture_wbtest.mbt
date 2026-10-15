///|
// Actual original read/Model/Entry owners; byte amounts, physical response and
// cleanup acknowledgements remain explicit fixture doubles, not public funding.
test "original async fixture keeps its preconfigured read Ledger through Unknown cleanup" {
  let original : Ref[
    (@resources.Ledger, @publication_host.ClientModelReadPreparation)?,
  ] = Ref(None)
  let calls = Ref(0)
  let polls = Ref(0)
  let ready = Ref(false)
  let release = Ref(false)
  let cleaned : Array[Bool] = []
  let (active, prefix) = async_response_fixture(
    calls,
    polls,
    Ref(0),
    cleaned,
    ready,
    release,
    @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
    prepare_original=Some(active => {
      let (ledger, read) = original_preparation_test_read(
        active,
        quantities=Some(active.quantity_capacity.unwrap().limits),
      )
      bind_original_model_preparation(active, read, 100L, 5L).unwrap()
      original.val = Some((ledger, read))
    }),
  )
  let (ledger, read) = original.val.unwrap()
  let binding = active.run_binding.unwrap()
  let preparation = active.original_preparation.unwrap()
  let prepared = prepared_call_set(active).unwrap()
  assert_true(@model.prepared_model_call_count(prepared) is Some(2))
  assert_true(
    @resources.quantity_configuration_matches(
      ledger,
      Some(active.quantity_capacity.unwrap().limits),
    ),
  )
  assert_true(fixture_finish(active, initial_work=prefix) is AwaitIo(..))
  assert_eq(calls.val, 1)
  assert_eq(
    @model.model_execution_resource_usage(active.model.unwrap()),
    @resources.ledger_usage(ledger),
  )
  let before = @resources.ledger_usage(ledger)
  ready.val = true
  assert_true(cancel(active))
  let terminal = fixture_finish(active, initial_work=active.work)
  assert_true(terminal is Stopped(..) || terminal is Failed(_, ..))
  assert_false(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
  assert_true(cleaned.length() > 0)
  // Handoff consumes read availability without retiring its reservation.
  // Retained custody must not be mistaken for another allocation/claim grant.
  assert_false(
    @publication_host.client_model_read_available(
      read,
      binding.compiled,
      binding.definition,
      active.plan.unwrap(),
    ),
  )
  assert_true(physical_equal(active.original_preparation.unwrap(), preparation))
  assert_true(preparation.read is Bound(same) && physical_equal(same, read))
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_eq(
    @model.model_execution_quantity_usage(active.model.unwrap()).consumed.tokens,
    0L,
  )
  // NULL observations stay unknown; zero consumed is not a fabricated usage
  // observation. Only the same physical cleanup acknowledgement retires it.
  release.val = true
  async_io_stop_and_cleanup(active)
  assert_eq(calls.val, 1)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(physical_equal(active.run_binding.unwrap(), binding))
  original_preparation_test_release(ledger, read)
}
