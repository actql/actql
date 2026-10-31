///|
test "same original compiled Run definition performs full binding work once" {
  for tasks in [false, true] {
    let (_, original, definition) = local_values_invocation_fixture(tasks)
    // The issuer already checked its Definition. Start a fresh empty slot to
    // count actual full binder executions, rather than checker entries.
    let compiled = { ..original, definition_binding: None, }
    let full = Ref(0)
    for _ in 0..<3 {
      check_client_compiled_run_definition_owned(compiled, definition, bind=(
        value,
        selected,
      ) => {
        full.val += 1
        bind_client_compiled_run_definition(value, selected)
      }).unwrap()
    }
    assert_eq(full.val, 1)
  }
}

///|
fn counted_compiled_definition_binding(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  full : Ref[Int],
) -> Result[Unit, ClientCompiledRunIssue] {
  check_client_compiled_run_definition_owned(compiled, definition, bind=(
    value,
    selected,
  ) => {
    full.val += 1
    bind_client_compiled_run_definition(value, selected)
  })
}

///|
test "issuer retains the completed typed Values and Tasks bindings" {
  for tasks in [false, true] {
    let (_, compiled, definition) = local_values_invocation_fixture(tasks)
    let original = compiled.definition_binding.unwrap()
    match (tasks, original.binding) {
      (false, ValuesDefinition(binding)) =>
        assert_eq(
          client_values_run_binding_definition_cid(binding),
          @publication.publication_contract_identity(definition),
        )
      (true, TaskDefinition(binding)) =>
        assert_eq(
          client_task_run_binding_definition_cid(binding),
          @publication.publication_contract_identity(definition),
        )
      _ => fail("issuer retained the wrong binding kind")
    }
    let full = Ref(0)
    counted_compiled_definition_binding(compiled, definition, full).unwrap()
    check_client_compiled_run_definition(compiled, definition).unwrap()
    assert_eq(full.val, 0)
    assert_true(physical_equal(compiled.definition_binding.unwrap(), original))
  }
}

///|
test "restored equal Definition requires full validation and preserves the original slot" {
  for tasks in [false, true] {
    let (_, compiled, definition) = local_values_invocation_fixture(tasks)
    let restored = @publication.admit_publication_contract(
      "run_definition",
      @publication.publication_contract_json(definition),
      100000,
      10000,
      100,
    ).unwrap()
    assert_false(physical_equal(restored, definition))
    let full = Ref(0)
    counted_compiled_definition_binding(compiled, restored, full).unwrap()
    counted_compiled_definition_binding(compiled, restored, full).unwrap()
    assert_eq(full.val, 2)
    assert_true(
      physical_equal(
        compiled.definition_binding.unwrap().definition,
        definition,
      ),
    )
    counted_compiled_definition_binding(compiled, definition, full).unwrap()
    counted_compiled_definition_binding(compiled, definition, full).unwrap()
    assert_eq(full.val, 2)
    assert_true(
      physical_equal(
        compiled.definition_binding.unwrap().definition,
        definition,
      ),
    )
    let (_, _, foreign) = local_values_invocation_fixture(
      tasks,
      document=run_materials_document.replace(
        old="client-values",
        new="another-program",
      ),
    )
    assert_true(
      counted_compiled_definition_binding(compiled, foreign, full) is Err(_),
    )
    counted_compiled_definition_binding(compiled, definition, full).unwrap()
    assert_eq(full.val, 3)
    assert_true(
      physical_equal(
        compiled.definition_binding.unwrap().definition,
        definition,
      ),
    )
  }
}

///|
test "foreign owner compilation or admission cannot borrow a copied binding slot" {
  for tasks in [false, true] {
    let (_, compiled, definition) = local_values_invocation_fixture(tasks)
    let (_, foreign, _) = local_values_invocation_fixture(
      tasks,
      document=run_materials_document.replace(
        old="client-values",
        new="another-program",
      ),
    )
    for
      changed in [
        { ..compiled, owner: foreign.owner, },
        { ..compiled, compilation: foreign.compilation, },
        { ..compiled, admission: foreign.admission, },
      ] {
      let full = Ref(0)
      assert_true(
        counted_compiled_definition_binding(changed, definition, full) is Err(_),
      )
      assert_eq(full.val, 1)
    }
    let full = Ref(0)
    counted_compiled_definition_binding(compiled, definition, full).unwrap()
    assert_eq(full.val, 0)
  }
}

///|
test "changed original evidence roots use the full binder before retaining facts" {
  for tasks in [false, true] {
    let (_, compiled, definition) = local_values_invocation_fixture(tasks)
    let (_, foreign, _) = local_values_invocation_fixture(tasks)
    for
      changed in [
        { ..compiled, template: foreign.template, },
        { ..compiled, plan: foreign.plan, },
        { ..compiled, prepared: foreign.prepared, },
        { ..compiled, authorization: foreign.authorization, },
      ] {
      let full = Ref(0)
      counted_compiled_definition_binding(changed, definition, full).unwrap()
      counted_compiled_definition_binding(changed, definition, full).unwrap()
      assert_eq(full.val, 1)
      assert_true(
        physical_equal(
          changed.definition_binding.unwrap().prepared,
          changed.prepared,
        ),
      )
    }
  }
}

///|
test "Effect compiled definition checks retain the original full path" {
  let (_, allowed, definition) = original_effect_materials_fixture()
  let compiled = client_effect_allowed_component_run(allowed, None)
  let full = Ref(0)
  for _ in 0..<3 {
    counted_compiled_definition_binding(compiled, definition, full).unwrap()
  }
  assert_eq(full.val, 3)
  assert_true(compiled.definition_binding is None)
}
