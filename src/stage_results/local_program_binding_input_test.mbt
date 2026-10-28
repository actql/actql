///|
fn selected_binding_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 30,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn selected_binding_source(defaulted? : Bool = true) -> @parameters.Source {
  local_program_parse(
    "{\"version\":\"actql/0.1\",\"id\":\"binding\",\"params\":{\"n\":{\"type\":\"number\"" +
    (if defaulted { ",\"default\":2" } else { "" }) +
    "}},\"stages\":[{\"id\":\"s\",\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":[{\"derive\":{\"extra\":\"id + $n\"},\"as\":\"prepared\"}],\"results\":{\"out\":{\"from\":\"prepared\",\"fields\":[\"id\",\"extra\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}",
  )
}

///|
test "original topology selected binding completes without replacing Source wiring or bound values" {
  let source = selected_binding_source()
  let limits = local_program_limits()
  let (wiring, used) = prepare_local_program(source, limits).unwrap()
  for supplied in [None, Some(selected_binding_cursor("{\"n\":7}"))] {
    let original = prepare_local_program_binding_input(wiring, supplied, limits).unwrap()
    let (same_source, same_supplied, selected) = local_program_binding_input_facts(
      original,
    ).unwrap()
    assert_true(physical_equal(same_source, source))
    match (same_supplied, supplied) {
      (None, None) => ()
      (Some(a), Some(b)) =>
        assert_eq(@decode.tree_index(a, b), @decode.tree_index(a, a))
      _ => fail("changed supplied input")
    }
    let declarations = @parameters.declarations(source)
    let (decl_nodes, decl_text) = @binding.declaration_usage(declarations)
    assert_eq(selected.max_nodes, limits.max_nodes - used.nodes - decl_nodes)
    assert_eq(
      selected.max_text_bytes,
      limits.max_text_bytes - used.text_bytes - decl_text,
    )
    let read = @binding.prepare_binding_read(declarations, supplied, selected).unwrap()
    guard @binding.finish_binding_read(read) is Ok(Ready(values)) else {
      fail("expected original completed binding")
    }
    let completed = bind_prepared_program_from_binding(original, read).unwrap()
    assert_true(physical_equal(local_source_source(completed), source))
    assert_true(physical_equal(local_source_wiring(completed), wiring))
    assert_true(physical_equal(local_source_values(completed), values))
    assert_eq(
      local_source_usage(completed),
      local_source_usage(
        bind_prepared_program(wiring, supplied, limits).unwrap(),
      ),
    )
    assert_true(local_program_binding_input_facts(original) is None)
    assert_true(
      bind_prepared_program_from_binding(original, read)
      is Err(MissingPreparation),
    )
  }
}

///|
test "original topology binding never advances foreign pending changed or incompatible readers" {
  let source = selected_binding_source()
  let supplied = Some(selected_binding_cursor("{\"n\":7}"))
  let limits = local_program_limits()
  let (wiring, _) = prepare_local_program(source, limits).unwrap()
  let original = prepare_local_program_binding_input(wiring, supplied, limits).unwrap()
  let (_, _, selected) = local_program_binding_input_facts(original).unwrap()
  let declarations = @parameters.declarations(source)
  let pending = @binding.prepare_binding_read(declarations, supplied, selected).unwrap()
  assert_true(
    bind_prepared_program_from_binding(original, pending)
    is Err(MissingPreparation),
  )
  assert_eq(@binding.binding_read_phase(pending), BindingHeader)
  for
    (other_declarations, other_supplied, other_limits) in [
      (@parameters.declarations(selected_binding_source()), supplied, selected),
      (declarations, Some(selected_binding_cursor("{\"n\":7}")), selected),
      (declarations, Some(selected_binding_cursor("{\"n\":8}")), selected),
      (declarations, None, selected),
      (
        declarations,
        supplied,
        { ..selected, max_depth: selected.max_depth + 1, },
      ),
    ] {
    let other = @binding.prepare_binding_read(
      other_declarations, other_supplied, other_limits,
    ).unwrap()
    assert_true(@binding.finish_binding_read(other) is Ok(Ready(_)))
    assert_true(
      bind_prepared_program_from_binding(original, other)
      is Err(MissingPreparation),
    )
    assert_eq(@binding.binding_read_phase(other), BindingComplete)
  }
  assert_true(@binding.finish_binding_read(pending) is Ok(Ready(_)))
  retire_local_program_binding_input(original)
  assert_true(local_program_binding_input_facts(original) is None)
  assert_true(
    bind_prepared_program_from_binding(original, pending)
    is Err(MissingPreparation),
  )
}

///|
test "original topology binding preserves missing null and typed failure before final assembly" {
  let source = selected_binding_source(defaulted=false)
  let limits = local_program_limits()
  let (wiring, _) = prepare_local_program(source, limits).unwrap()
  for supplied in [None, Some(selected_binding_cursor("{\"n\":null}"))] {
    let original = prepare_local_program_binding_input(wiring, supplied, limits).unwrap()
    let (_, _, selected) = local_program_binding_input_facts(original).unwrap()
    let read = @binding.prepare_binding_read(
      @parameters.declarations(source),
      supplied,
      selected,
    ).unwrap()
    let completed = @binding.finish_binding_read(read)
    if supplied is None {
      assert_true(completed is Ok(NeedsBindings(_)))
      assert_true(
        bind_prepared_program_from_binding(original, read)
        is Err(NeedsBindings(_)),
      )
    } else {
      assert_true(completed is Err(_))
      assert_true(
        bind_prepared_program_from_binding(original, read) is Err(Binding(_)),
      )
    }
    assert_true(local_program_binding_input_facts(original) is None)
  }
}
