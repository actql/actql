///|
// Actual original Run/Plan/body and canonical issued evidence. This is a
// constructor/backing component, not a physical Source or publication ACK.
test "keyed complete evidence geometry grows the same original publication body" {
  let original = effect_publication_values_original()
  let body = effect_unit_publication_body(
    original.run,
    original.plan,
    original.request,
  ).unwrap()
  let observation = @publication_host.client_effect_source_free_invocation_original_observation(
    original.issued,
  )
  let invocation = @publication_host.client_effect_source_free_invocation_original_invocation(
    original.issued,
  )
  for
    (name, wire) in [
      ("observation_set", @publication.run_evidence_value_json(observation)),
      ("run_invocation", @publication.publication_contract_json(invocation)),
    ] {
    let writer = @encode.construction_measuring_writer(1000000, 100000, 64)
    @encode.emit_json(@json.parse(wire), writer)
    let geometry = @encode.finish_construction_measurement(writer)
    let before = @resources.preparation_body_borrow_reserved_extents(body).unwrap()
    reserve_installed_effect_keyed_encoding(
      original.run,
      original.plan,
      original.request,
      @publication.publication_contract_identity(original.definition),
      name,
      geometry,
      complete_body=true,
    ).unwrap()
    let after = @resources.preparation_body_borrow_reserved_extents(body).unwrap()
    assert_true(after.0 > before.0 && after.1 >= after.0)
    // A malformed extent still cannot construct or grow this same body.
    assert_true(
      reserve_installed_effect_keyed_encoding(
        original.run,
        original.plan,
        original.request,
        @publication.publication_contract_identity(original.definition),
        name,
        { ..geometry, nodes: 0, },
        complete_body=true,
      )
      is Err(InsufficientCapacity),
    )
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(body),
      Ok(after),
    )
  }
  // The other existing callbacks still supply preimages. Their default quote
  // must continue adding the registry-owned self field before construction.
  let preimage_json = @json.parse(
    @publication.publication_contract_json(invocation),
  )
  guard preimage_json is Object(fields) else {
    fail("original invocation object")
  }
  fields.remove("invocation_cid") |> ignore
  let writer = @encode.construction_measuring_writer(1000000, 100000, 64)
  @encode.emit_json(preimage_json, writer)
  let preimage = @encode.finish_construction_measurement(writer)
  let identity = @publication.publication_contract_identity(original.definition)
  let original_quote = effect_unit_publication_capacity(
    [("run_invocation", preimage)],
    identity,
  ).unwrap()
  let without_self = effect_unit_publication_capacity(
    [("run_invocation", preimage)],
    identity,
    complete_body=true,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(original_quote) >
    @execution.execution_capacity_retained_bytes(without_self),
  )
  close_effect_publication_values(original)
}
