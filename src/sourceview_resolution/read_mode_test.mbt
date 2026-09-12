///|
fn check_mode_fixture(
  wire : String,
  cid : String,
  input : String,
  expected : String,
  bounded : Bool,
  checkpoint_cid : String,
) -> Unit raise {
  let catalog = fixture_catalog(wire, cid)
  let inputs = fixture_inputs(input)
  let resolved = resolve(inputs, catalog, caps()).unwrap()
  let entry = at(resolved, 0).unwrap()
  let result = select_direct_mode(entry, 1000)
  if expected == "watch" {
    assert_true(result is Err(e) && e.kind == UnsupportedWatch)
    return
  }
  if expected == "undeclared_snapshot" || expected == "undeclared_changes" {
    guard result is Err(e) else { fail("expected undeclared mode") }
    assert_eq(
      e.kind,
      UndeclaredMode(
        if expected == "undeclared_snapshot" {
          @environment.SnapshotMode
        } else {
          @environment.ChangesMode
        },
      ),
    )
    let path = @decode.cursor_path(e.source)
    assert_eq(path[path.length() - 2], @source.Key("scan"))
    assert_eq(path[path.length() - 1], @source.Key("mode"))
    return
  }
  let selected = result.unwrap()
  if checkpoint_cid == "" {
    assert_true(mode_checkpoint(selected) is None)
  } else {
    let checkpoint = mode_checkpoint(selected).unwrap()
    let reference = checkpoint_reference(checkpoint)
    let contract = checkpoint_value_contract(checkpoint)
    assert_eq(
      @environment.contract_identity(
        @environment.protocol_value_envelope(contract),
      ).2,
      checkpoint_cid,
    )
    assert_true(
      physical_equal(
        @environment.reference_contract(reference),
        @environment.protocol_value_envelope(contract),
      ),
    )
    let checkpoint_path = @decode.cursor_path(
      @environment.reference_source(reference),
    )
    assert_eq(
      checkpoint_path[checkpoint_path.length() - 1],
      @source.Key("value_schema"),
    )
    assert_eq(
      checkpoint_path[checkpoint_path.length() - 2],
      @source.Key("checkpoint"),
    )
    let refs = @environment.data_policy_references(
      @environment.value_contract_policies(
        @environment.source_view_shape_values(
          @environment.read_mode_shapes(
            @environment.carrier_schema_modes(
              @environment.source_request_carriers(catalog),
            ),
          ),
        ),
      ),
    )
    let foreign_refs = @environment.data_policy_references(
      @environment.value_contract_policies(
        @environment.source_view_shape_values(
          @environment.read_mode_shapes(
            @environment.carrier_schema_modes(
              @environment.source_request_carriers(fixture_catalog(wire, cid)),
            ),
          ),
        ),
      ),
    )
    assert_true(
      physical_equal(
        @environment.catalog_reference_for_cursor(
          refs,
          @environment.reference_source(reference),
        ).unwrap(),
        reference,
      ),
    )
    assert_true(
      @environment.catalog_reference_for_cursor(
        foreign_refs,
        @environment.reference_source(reference),
      )
      is None,
    )
  }
  assert_true(physical_equal(mode_input(selected), entry))
  assert_eq(
    @environment.read_mode_kind(mode_contract(selected)),
    if expected == "snapshot" {
      @environment.SnapshotMode
    } else {
      @environment.ChangesMode
    },
  )
  assert_eq(@environment.read_mode_bounded(mode_contract(selected)), bounded)
  assert_eq(
    mode_origin(selected),
    if declaration(entry).scan is Some(_) {
      AuthoredMode
    } else {
      ContractDefault
    },
  )
  let path = @decode.cursor_path(mode_source(selected))
  if declaration(entry).scan is Some(_) {
    assert_eq(path[path.length() - 1], @source.Key("mode"))
  } else {
    assert_true(path[path.length() - 1] is @source.Index(_))
  }
  let obligations = mode_obligations(selected)
  if expected == "changes" {
    assert_eq(obligations, [
      RuntimeModeSupport,
      BoundedChangesRange,
      SourceStateRequirement,
    ])
  } else {
    assert_eq(obligations, [RuntimeModeSupport])
  }
  obligations.clear()
  assert_true(!mode_obligations(selected).is_empty())
  assert_true(select_direct_mode(entry, mode_work(selected)) is Ok(_))
  assert_true(
    select_direct_mode(entry, mode_work(selected) - 1) is Err(e) &&
    e.kind == WorkLimit,
  )
  assert_true(
    select_direct_mode(entry, -1) is Err(e) && e.kind == InvalidLimits,
  )
  let modes = @environment.carrier_schema_modes(
    @environment.source_request_carriers(catalog),
  )
  let item = @environment.source_request_member(selected_contract(entry))
  let view = @environment.read_mode_for(modes, item).unwrap()
  let registry_member = @environment.member_at(
    @environment.member_environment(item),
    @environment.ContractRegistry,
    0,
  ).unwrap()
  assert_true(@environment.read_mode_for(modes, registry_member) is None)
  let mut found = false
  for i in 0..<@environment.read_mode_count(view) {
    if physical_equal(
        @environment.read_mode_at(view, i).unwrap(),
        mode_contract(selected),
      ) {
      found = true
    }
  }
  assert_true(found)
  let foreign = fixture_catalog(wire, cid)
  let foreign_modes = @environment.carrier_schema_modes(
    @environment.source_request_carriers(foreign),
  )
  assert_true(@environment.read_mode_for(foreign_modes, item) is None)
}
