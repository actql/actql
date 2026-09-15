///|
test "standard check derives values evidence without caller proof material" {
  let (text, parsed, environment, evidence, limits) = public_input_fixture(
    generated=true,
  )
  let automatic = public_checked(
    @program_check.check_parsed(parsed, environment, None, limits),
  )
  let documented = public_checked(
    @program_check.check_document(
      text,
      environment,
      None,
      limits,
      format=Json,
      source_path="fixture.actql",
    ),
  )
  let explicit = public_checked(
    @program_check.check_parsed_with_evidence(
      parsed,
      environment,
      None,
      evidence,
      limits,
    ),
  )
  // The same producer is visited by two Stages, but only one row-count artifact
  // pair is constructed. Supplying that admitted pair requires no re-emission.
  assert_eq(
    @context.program_identity_capacity_metadata_usage(
      @program_check.source_identity(automatic),
    ),
    (606, 22),
  )
  assert_eq(
    @context.program_identity_capacity_metadata_usage(
      @program_check.source_identity(explicit),
    ),
    (0, 0),
  )
  let auto_index = @context.incoming_links_resolutions(
    @context.stage_requirement_owner(@program_check.requirements(automatic)),
  )
  let explicit_index = @context.incoming_links_resolutions(
    @context.stage_requirement_owner(@program_check.requirements(explicit)),
  )
  assert_eq(
    @context.operation_resolution_values_metadata_usage(auto_index),
    @context.operation_resolution_values_metadata_usage(explicit_index),
  )
  for stage in 0..<2 {
    // One authored row, preserved by derive/assert and the downstream take.
    // The independent Host ceiling is 1000 and is not the selected minimum.
    let publication = @program_check.unit_publication_at(automatic, stage, 0).unwrap()
    assert_eq(
      @context.publication_row_limit_maximum(
        @program_check.publication_selection(publication),
      ),
      1L,
    )
    let identity = @program_check.unit_definition_cid(automatic, stage).unwrap()
    assert_eq(
      identity,
      @program_check.unit_definition_cid(explicit, stage).unwrap(),
    )
    assert_eq(
      identity,
      @program_check.unit_definition_cid(documented, stage).unwrap(),
    )
    let expected = @program_check.unit_publication_at(explicit, stage, 0).unwrap()
    assert_eq(
      @wire.limit_cid(@program_check.publication_rows(publication)),
      @wire.limit_cid(@program_check.publication_rows(expected)),
    )
    let root = @program_check.publication_proof_at(publication, 0).unwrap()
    assert_eq(
      @wire.value(@wire.program_proof_witness(@program_check.proof_claim(root))),
      1L,
    )
    assert_eq(
      @program_check.proof_source(root).unit_definition_cid,
      @program_check.unit_definition_cid(automatic, 0).unwrap(),
    )
  }
}

///|
test "standard values count preserves empty and repeated authored rows" {
  let (text, _, environment, _, limits) = public_input_fixture(generated=true)
  for (rows, expected) in [("[]", 0L), ("[{\"id\":1},{\"id\":1}]", 2L)] {
    // Drop the uniqueness assertion for duplicate data: count evidence itself
    // makes no claim that the authored values are unique.
    let source = text
      .replace(old="\"rows\":[{\"id\":1}]", new="\"rows\":" + rows)
      .replace(
        old="{\"assert_rows\":{\"unique_by\":[\"id\"]}}",
        new="{\"distinct\":true}",
      )
    let program = public_checked(
      @program_check.check_document(
        source,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
    let publication = @program_check.unit_publication_at(program, 0, 0).unwrap()
    assert_eq(
      @context.publication_row_limit_maximum(
        @program_check.publication_selection(publication),
      ),
      expected,
    )
    assert_eq(
      @context.program_identity_capacity_metadata_usage(
        @program_check.source_identity(program),
      ),
      (606, 22),
    )
  }
}

///|
test "standard construction charges the independently sized automatic count once" {
  let (_, parsed, environment, evidence, limits) = public_input_fixture(
    generated=true,
  )
  fn succeeds(bytes : Int, supplied : Bool) -> Bool {
    let limited = {
      ..limits,
      compilation: {
        ..limits.compilation,
        artifacts: { ..limits.compilation.artifacts, bytes, },
      },
    }
    let outcome = if supplied {
      @program_check.check_parsed_with_evidence(
        parsed,
        environment,
        None,
        evidence,
        limited,
      )
    } else {
      @program_check.check_parsed(parsed, environment, None, limited)
    }
    outcome is Checked(_)
  }
  fn threshold(supplied : Bool) -> Int raise {
    let mut low = 0
    let mut high = limits.compilation.artifacts.bytes
    assert_true(succeeds(high, supplied))
    while low < high {
      let middle = low + (high - low) / 2
      if succeeds(middle, supplied) {
        high = middle
      } else {
        low = middle + 1
      }
    }
    assert_true(succeeds(low, supplied))
    assert_false(succeeds(low - 1, supplied))
    low
  }
  // The expected difference is the independent canonical byte length, not a
  // value read from the product's usage counters. Every other artifact agrees.
  assert_eq(threshold(false) - threshold(true), 606)
}
