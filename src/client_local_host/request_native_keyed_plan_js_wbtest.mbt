///|
fn native_keyed_plan_test_parent(
  wire : String,
  environment : @checked.CheckEnvironment,
  current : () -> Bool,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientEffectComputation,
) raise {
  let (parent, child, _, input) = registration_parent_fixture(
    text=wire,
    environment=Some(environment),
    current~,
    effect_limits=Some(
      @publication_host.client_standard_effect_computation_limits(),
    ),
  )
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let original = compile_effect_program_check_preparation(child).unwrap()
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      original,
    ),
  )
  (parent, input, original)
}

///|
test "same Request funds actual keyed first Plan and first Effect compiler consumes its original component" {
  original_composed_keyed_consumer(
    native_transport=true,
    prepare_parent=Some((wire, environment) => {
      native_keyed_plan_test_parent(wire, environment, () => true)
    }),
    first_plan=Some((parent, input, prepared, profile) => {
      let borrow = borrow_request_effect_plan_input(parent, input).unwrap()
      let capacity = parent.effect_capacity.unwrap()
      let ledger = parent.ledger
      let before = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      let occurrence = @publication_host.prepared_client_effect_infer_occurrence(
        prepared,
      ).unwrap()
      let graph = prepare_request_model_graph(
        parent,
        input,
        occurrence,
        effect_model_plan_execution(occurrence),
        request_program_module_contracts(),
        manifests=request_program_module_manifests(),
        compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
        keyed_native_profile=Some(profile),
      ).unwrap()
      let after = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      assert_true(after.0 > before.0 && after.1 > before.1)
      assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
      assert_true(physical_equal(parent.ledger, ledger))
      assert_true(
        physical_equal(
          @publication_host.client_infer_plan_native_keyed_read_profile(graph).unwrap(),
          profile,
        ),
      )
      let keyed = @publication_host.select_client_effect_composed_model_keyed_acquisition(
          prepared, graph,
        )
        .unwrap()
        .unwrap()
      let same = @publication_host.select_client_effect_composed_model_keyed_acquisition(
          prepared, graph,
        )
        .unwrap()
        .unwrap()
      assert_true(physical_equal(keyed, same))
      let compilation = @publication_host.issue_prepared_client_effect_compilation(
        prepared,
        request_program_module_manifests(),
        @publication_host.client_standard_values_sequence_limits(),
        1000,
        10000,
        100000,
        10000,
        100,
        infer=Some(graph),
      ).unwrap()
      assert_true(
        physical_equal(
          @publication_host.client_effect_compilation_owner(compilation),
          prepared,
        ),
      )
      assert_true(
        @publication_host.client_infer_plan_graph_wire(graph).contains(
          "actql-lookup-barrier/0.1",
        ),
      )
      assert_false(@resources.return_preparation_body_borrow(borrow).unwrap())
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    }),
  )
}

///|
test "keyed first Plan current loss refuses before constructors and keeps original failed Request cleanup" {
  for denied in [1, 2, 3] {
    let armed = Ref(false)
    let calls = Ref(0)
    let current = () => {
      if !armed.val {
        return true
      }
      calls.val += 1
      calls.val != denied
    }
    original_composed_keyed_consumer(
      native_transport=true,
      prepare_parent=Some((wire, environment) => {
        native_keyed_plan_test_parent(wire, environment, current)
      }),
      first_plan=Some((parent, input, prepared, profile) => {
        let borrow = borrow_request_effect_plan_input(parent, input).unwrap()
        let ledger = parent.ledger
        let occurrence = @publication_host.prepared_client_effect_infer_occurrence(
          prepared,
        ).unwrap()
        armed.val = true
        assert_true(
          prepare_request_model_graph(
            parent,
            input,
            occurrence,
            effect_model_plan_execution(occurrence),
            request_program_module_contracts(),
            manifests=request_program_module_manifests(),
            compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
            keyed_native_profile=Some(profile),
          )
          is Err(_),
        )
        assert_true(parent.phase == EffectBodyFailed)
        assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
        armed.val = false
        assert_false(@resources.return_preparation_body_borrow(borrow).unwrap())
        abort_request_preparation_after_cleanup(parent).unwrap()
        assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
        assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
      }),
    )
  }
}

///|
test "keyed original construction survives post-measurement current refusal until the same Request abort" {
  let armed = Ref(false)
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let current = () => {
    match selected.val {
      Some(parent) if armed.val =>
        !(parent.program_domain_compilation_inputs
        is Some(RequestModelGraphConstruction(_, _, _, _)))
      _ => true
    }
  }
  original_composed_keyed_consumer(
    native_transport=true,
    prepare_parent=Some((wire, environment) => {
      native_keyed_plan_test_parent(wire, environment, current)
    }),
    first_plan=Some((parent, input, prepared, profile) => {
      selected.val = Some(parent)
      let borrow = borrow_request_effect_plan_input(parent, input).unwrap()
      let ledger = parent.ledger
      let occurrence = @publication_host.prepared_client_effect_infer_occurrence(
        prepared,
      ).unwrap()
      armed.val = true
      assert_true(
        prepare_request_model_graph(
          parent,
          input,
          occurrence,
          effect_model_plan_execution(occurrence),
          request_program_module_contracts(),
          manifests=request_program_module_manifests(),
          compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
          keyed_native_profile=Some(profile),
        )
        is Err(Preparation(Capacity(_))),
      )
      assert_true(parent.phase == EffectBodyFailed)
      assert_true(
        parent.program_domain_compilation_inputs
        is Some(RequestModelGraphConstruction(_, _, _, _)),
      )
      assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
      armed.val = false
      assert_false(@resources.return_preparation_body_borrow(borrow).unwrap())
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_true(parent.program_domain_compilation_inputs is None)
      assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    }),
  )
}
