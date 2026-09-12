///|
fn fixture_catalog(
  wire : String,
  cid : String,
) -> @environment.SourceRequestContracts {
  let caps : @environment.Limits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
    max_members: 1000,
  }
  let raw = @environment.read(@utf8.encode(wire), cid, caps).unwrap()
  let registry = @environment.check_contract_registry(raw, caps).unwrap()
  let contents = @environment.check_catalog_contents(registry, caps).unwrap()
  let refs = @environment.check_catalog_references(contents, {
    max_work: 1000000,
    max_references: 10000,
  }).unwrap()
  let policies = @environment.check_source_data_policies(refs, {
    max_work: 1000000,
    max_policies: 1000,
  }).unwrap()
  let values = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 1000,
    contracts: { max_nodes: 100000, max_depth: 100, max_text_bytes: 1000000, },
  }).unwrap()
  let shapes = @environment.check_source_view_shapes(values, {
    max_work: 1000000,
    max_views: 1000,
  }).unwrap()
  let modes = @environment.check_source_read_modes(shapes, 1000000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_work: 1000000,
    max_schemas: 1000,
    bodies: { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
  }).unwrap()
  @environment.check_source_request_contracts(carriers, {
    max_work: 1000000,
    max_roles: 10000,
  }).unwrap()
}

///|
fn fixture_inputs(
  input : String,
  declarations? : String = "",
  stage_bodies? : String? = None,
) -> @inputs.Inputs {
  let stage_bodies = stage_bodies.unwrap_or(
    "{\"id\":\"a\",\"inputs\":{\"remote\":" +
    input +
    "},\"steps\":[],\"results\":{\"r\":{}}}",
  )
  let wire = "{\"version\":\"actql/0.1\",\"id\":\"p\"," +
    declarations +
    "\"stages\":[" +
    stage_bodies +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  let program = @syntax.parse(
    wire,
    {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      tree: {
        max_nodes: 100000,
        max_depth: 100,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_stages: 100,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 100,
    max_nodes: 100,
    max_depth: 100,
    max_text_bytes: 1000,
  }).unwrap()
  @inputs.collect(source, { max_work: 1000000, max_order_keys: 100, }).unwrap()
}

///|
fn caps() -> Limits {
  { max_work: 1000000, max_inputs: 1000, max_views: 1000, }
}

///|
fn check_fixture(
  wire : String,
  cid : String,
  input : String,
  expected : IssueKind?,
  selected : String,
  selected_id : String,
  explicit : Bool,
) -> Unit raise {
  let catalog = fixture_catalog(wire, cid)
  let inputs = fixture_inputs(input)
  let result = resolve(inputs, catalog, caps())
  if expected is Some(kind) {
    guard result is Err(issue) else { fail("expected resolution failure") }
    assert_eq(issue.kind, kind)
    assert_true(issue.source is Some(_))
    if kind == Unresolved && explicit {
      let path = @decode.cursor_path(issue.source.unwrap())
      assert_eq(path[path.length() - 1], @source.Key("view"))
    }
    return
  }
  let resolved = result.unwrap()
  assert_eq(count(resolved), 1)
  let entry = at(resolved, 0).unwrap()
  assert_eq(selected_name(entry), selected)
  assert_eq(selected_cid(entry), selected_id)
  assert_eq(selection(entry), if explicit { Explicit } else { SoleView })
  assert_eq(
    completion_rule(entry),
    if explicit {
      None
    } else {
      Some("actql.source.sole-view-completion")
    },
  )
  assert_true(physical_equal(input_owner(entry), inputs))
  assert_true(physical_equal(catalog_owner(entry), catalog))
  let selected_member = @environment.source_request_member(
    selected_contract(entry),
  )
  let reference_count = selected_reference_count(entry)
  assert_true(reference_count > 0)
  for i in 0..<reference_count {
    let r = selected_reference_at(entry, i).unwrap()
    assert_true(
      physical_equal(@environment.reference_member(r), selected_member),
    )
    assert_true(
      physical_equal(
        @environment.member_environment(
          @environment.contract_member(@environment.reference_contract(r)),
        ),
        @environment.member_environment(selected_member),
      ),
    )
  }
  for i in [-2147483648, -1, reference_count, 2147483647] {
    assert_true(selected_reference_at(entry, i) is None)
  }
  assert_true(physical_equal(@sourceview_resolution.inputs(resolved), inputs))
  assert_true(physical_equal(@sourceview_resolution.catalog(resolved), catalog))
  assert_eq(declaration(entry).view is Some(_), explicit)
  assert_true(at(resolved, -1) is None)
  assert_true(at(resolved, 1) is None)
  assert_true(
    resolve(inputs, catalog, { ..caps(), max_work: work(resolved), }) is Ok(_),
  )
  assert_true(
    resolve(inputs, catalog, { ..caps(), max_work: work(resolved) - 1, })
    is Err(e) &&
    e.kind == WorkLimit,
  )
  assert_true(
    resolve(inputs, catalog, { ..caps(), max_inputs: 0, }) is Err(e) &&
    e.kind == InputLimit,
  )
  assert_true(
    resolve(inputs, catalog, { ..caps(), max_views: 0, }) is Err(e) &&
    e.kind == ViewLimit,
  )
  assert_true(
    resolve(inputs, catalog, { ..caps(), max_work: -1, }) is Err(e) &&
    e.kind == InvalidLimits,
  )
  let other = fixture_catalog(wire, cid)
  check_pipeline_fixture(resolved, other, fixture_inputs(input))
  check_pipeline_stages_fixture(catalog, input)
  assert_false(physical_equal(catalog_owner(entry), other))
  assert_true(
    @environment.source_request_for(
      other,
      @environment.source_request_member(selected_contract(entry)),
    )
    is None,
  )
}
