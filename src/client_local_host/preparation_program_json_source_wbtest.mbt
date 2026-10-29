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
  assert_true(
    program_json_preparation_initial_inventory() ==
    {
      record_headers: 559L,
      reference_slots: 203L,
      scalar_words: 1208L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  )
  assert_eq(program_json_initial_control_bytes, 20232L)
  // Independently counted5nodes/4fields/2objects/1array/depth2 and58UTF8bytes.
  // Existing Source/key/index units yield554H/846R/(1507+35*58)W/
  // (53*58+18)UTF16, or63104 logical bytes including fixed post controls.
  let core = 63104L
  for short in [true, false] {
    let ledger = @resources.create_ledger({
      planning_work: 7,
      attempts: 2,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 73L + 17L + core - (if short { 1L } else { 0L }),
      execution_bytes: 91L + 19L + core,
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
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((20305L, 20323L)),
    )
    assert_true(finish_program_json_preparation(owner) is Err(WrongPhase))
    let geometry = funded_json_ready(owner)
    assert_eq(geometry.input_bytes, 58)
    assert_eq(
      program_json_source_index_quote(geometry, bounds),
      Some((core, core)),
    )
    let result = finish_program_json_preparation(owner)
    if short {
      assert_true(result is Err(Capacity(Resource(RetentionLimit))))
      assert_eq(
        @resources.preparation_capacity_working_extents(capacity, input),
        Ok((20305L, 20323L)),
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
      // Retained only: driver+geometry24H31R51W; Source15H9R54W/33U;
      // indexed storage28H84R56W; Stage2H2R4W =>69H126R165W/33U,
      // 3498logicalB. Index keys/ancestry/controls were temporary, not retained.
      // Required quote workspace18120 remains in E, so E=3498+18120=21618.
      assert_eq(
        @resources.preparation_capacity_working_extents(capacity, input),
        Ok((73L + 3498L, 91L + 21618L)),
      )
      let indexed = take_program_json_preparation_input(owner).unwrap()
      let root = @syntax.program_input_cursor(indexed)
      assert_eq(@decode.object_length(root), Some(4))
      let (key, value) = @decode.field_at(root, 1).unwrap()
      assert_eq(key, "id")
      assert_eq(@decode.text(value), Ok("é"))
      assert_true(take_program_json_preparation_input(owner) is Err(WrongPhase))
      clear_program_json_preparation(owner).unwrap()
      // Clearing the old phase does not clear the next caller's indexed body.
      assert_eq(@decode.object_length(root), Some(4))
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        73L + 17L + 3498L,
      )
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
