///|
// Binding assertions use the separately retained original checked Owner and
// the fixture's explicit authored coordinate. They do not mint expected CIDs
// with this projection or establish physical/current signing authority.
test "Checkpoint unit projection reads the original checked definition at its authored coordinate" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let artifact = @checkpoint.seal_checkpoint(body, {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }).unwrap()
  assert_eq(
    artifact.checkpoint.subject,
    @checkpoint.RunUnit(
      run_id="original-run",
      unit_id="source",
      run_definition_cid=@publication.publication_contract_identity(definition),
    ),
  )
  let original_checked = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(allowed.compilation.owner),
  )
  assert_eq(
    client_effect_review_checkpoint_unit_definition_cid(
      allowed, definition, artifact,
    ).unwrap(),
    @checked.unit_definition_cid(original_checked, 0).unwrap(),
  )
}

///|
test "Checkpoint unit projection refuses foreign explicit unit Run and definition without fallback" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  for
    subject in [
      @checkpoint.RunUnit(
        run_id="original-run",
        unit_id="foreign-unit",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      @checkpoint.RunUnit(
        run_id="foreign-run",
        unit_id="source",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      @checkpoint.RunUnit(
        run_id="original-run",
        unit_id="source",
        run_definition_cid="sha256:" + "f".repeat(64),
      ),
    ] {
    let artifact = @checkpoint.seal_checkpoint({ ..body, subject, }, limits).unwrap()
    assert_true(
      client_effect_review_checkpoint_unit_definition_cid(
        allowed, definition, artifact,
      )
      is Err(ForeignSubject),
    )
  }
}
