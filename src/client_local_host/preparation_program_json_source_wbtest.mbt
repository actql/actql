///|
fn funded_json_bounds() -> @syntax.Limits {
  {
    source: { max_input_bytes: 1000, max_nodes: 100, max_depth: 20, },
    tree: {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
    max_stages: 10,
  }
}

///|
fn[I, P] funded_json_ready(
  owner : ClientProgramJsonPreparation[I, P],
) -> @source.JsonSourceGeometry raise {
  for _ in 0..<1000 {
    match advance_program_json_preparation(owner, 3).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(geometry, ..) => return geometry
      @source.JsonSourceFailed(_, ..) => fail("unexpected source refusal")
    }
  }
  fail("source preflight did not finish")
}

///|
test "actual generic JSON driver preserves outside debits sibling and original source across one-short grow" {
  let wire = "{\"version\":\"actql/0.1\",\"id\":\"é\",\"stages\":[],\"results\":{}}"
  let bounds = funded_json_bounds()
  // This fixture constrains the actual selected next-phase quote below.
  // Fixed Host wrapper counts are not a language or Resource contract.
  for short in [true, false] {
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 1000000L,
      execution_bytes: 1000000L,
    }).unwrap()
    let sibling = @resources.reserve_capacity(ledger, 17L, 19L).unwrap()
    let input = ["same original"]
    let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
      ledger,
      input,
      73L,
      91L,
      max_borrowers=1,
    ).unwrap()
    assert_true(
      begin_program_json_preparation(capacity, ["same original"], wire, bounds)
      is Err(Capacity(ForeignOriginal)),
    )
    let owner = begin_program_json_preparation(capacity, input, wire, bounds).unwrap()
    let initial = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    assert_true(initial.0 > 73L && initial.1 > 91L)
    assert_true(finish_program_json_preparation(owner) is Err(WrongPhase))
    let geometry = funded_json_ready(owner)
    assert_eq(geometry.input_bytes, 58)
    let (r, e) = program_json_source_index_quote(geometry, bounds).unwrap()
    // An actual original quotation is DATA for this admission test, not its
    // own tariff oracle. The independent Source identity/content assertions
    // below stay fixed; neither byte cap nor arithmetic is changed.
    let blocker = if short {
      Some(
        @resources.reserve_capacity(ledger, 1000000L - 73L - 17L - r + 1L, 0L).unwrap(),
      )
    } else {
      None
    }
    let result = finish_program_json_preparation(owner)
    if short {
      assert_true(result is Err(Capacity(Resource(RetentionLimit))))
      assert_eq(
        @resources.preparation_capacity_working_extents(capacity, input),
        Ok(initial),
      )
      guard advance_program_json_preparation(owner, 1).unwrap()
        is @source.JsonSourceReady(same, work~) else {
        fail("lost original ready holder")
      }
      assert_true(physical_equal(same, geometry))
      assert_eq(work, 0)
      assert_true(take_program_json_preparation_input(owner) is Err(WrongPhase))
    } else {
      assert_eq(result, Ok(()))
      let retained = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      assert_true(retained.0 >= 73L && retained.0 < 73L + r)
      assert_true(retained.1 >= 91L && retained.1 <= 91L + e)
      let indexed = take_program_json_preparation_input(owner).unwrap()
      let root = @syntax.program_input_cursor(indexed)
      assert_eq(@decode.object_length(root), Some(4))
      assert_eq(@decode.admission_usage(root).nodes, 5)
      assert_eq(@decode.admission_usage(root).depth, 2)
      assert_eq(@decode.admission_usage(root).total_string_bytes, 33)
      let (key, value) = @decode.field_at(root, 1).unwrap()
      assert_eq(key, "id")
      assert_eq(@decode.text(value), Ok("é"))
      assert_true(take_program_json_preparation_input(owner) is Err(WrongPhase))
      clear_program_json_preparation(owner).unwrap()
      // Clearing the old phase does not clear the next caller's indexed body.
      assert_eq(@decode.object_length(root), Some(4))
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        retained.0 + 17L,
      )
    }
    if blocker is Some(blocker) {
      @resources.settle_capacity(ledger, blocker).unwrap()
    }
    clear_program_json_preparation(owner).unwrap()
    clear_program_json_preparation(owner).unwrap()
    // Backend/raw input aliases and the taken index have unwound here. Only
    // this explicit fixture now invokes the existing original Resource cleanup.
    assert_true(
      @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 17L)
    @resources.settle_capacity(ledger, sibling).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).planning_work, 0)
    assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  }
}
