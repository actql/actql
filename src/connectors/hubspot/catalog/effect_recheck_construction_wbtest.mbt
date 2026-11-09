///|
test "Catalog recheck quote funds one borrowed-key Map without retaining another Catalog" {
  for count in [1, 2, 256, 65536, 2147483647] {
    let actual = effect_catalog_recheck_construction_capacity(count).unwrap()
    let map = @shape.map_construction_extent(1L, count.to_int64()).unwrap()
    assert_eq(@execution.execution_capacity_retained_bytes(actual), 0L)
    assert_eq(
      @execution.execution_capacity_execution_bytes(actual),
      @execution.preparation_representation_cost({
        record_headers: map.record_headers,
        reference_slots: map.reference_slots,
        scalar_words: map.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }).unwrap(),
    )
  }
  assert_true(effect_catalog_recheck_construction_capacity(0) is None)
  assert_true(effect_catalog_recheck_construction_capacity(-1) is None)
}

///|
test "Catalog recheck retains full native meaning and rejects an undersupplied original workspace" {
  let original = catalog(
    (
      #|{"results":[{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"same","label":"Original"}]},{"name":"name","type":"string","fieldType":"text"}]}
    ),
  )
  let reordered = catalog(
    (
      #|{"results":[{"name":"name","type":"string","fieldType":"text"},{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"same","label":"Renamed"}]}]}
    ),
  )
  let changed = catalog(
    (
      #|{"results":[{"name":"stage","type":"enumeration","fieldType":"select","options":[{"value":"other","label":"Original"}]},{"name":"name","type":"string","fieldType":"text"}]}
    ),
  )
  let quote = effect_catalog_recheck_construction_capacity(2).unwrap()
  let work = @execution.execution_capacity_execution_bytes(quote)
  let limits : @resources.LedgerLimits = {
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: work - 1L,
  }
  let short = @resources.create_ledger(limits).unwrap()
  let before = @resources.ledger_usage(short)
  assert_true(
    @resources.reserve_capacity(short, 0L, work) is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(short), before)
  // The already-owned input Catalogs are outside this private Map quote.
  let ledger = @resources.create_ledger({ ..limits, execution_bytes: work, }).unwrap()
  let token = @resources.reserve_capacity(ledger, 0L, work).unwrap()
  assert_eq(recheck_property_catalog(original, reordered, 2), Ok(()))
  assert_eq(recheck_property_catalog(original, changed, 2), Err(ForeignCatalog))
  assert_eq(
    recheck_property_catalog(original, original, 1),
    Err(BudgetExceeded),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, work)
  @resources.settle_capacity(ledger, token).unwrap()
}
