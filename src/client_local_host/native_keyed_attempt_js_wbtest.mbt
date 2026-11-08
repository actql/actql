///|
// Actual original Request/Effect Plan/Model Scope/keyed RowRun. Provider
// current/response ports remain explicit component inputs; no Native I/O or
// installed runtime/physical cleanup acknowledgement is claimed here.

///|
#cfg(target="js")
test "Native content caller retains the exact keyed Request tuple without another current observation" {
  let current_calls = Ref(0)
  let observed = Ref(false)
  original_composed_keyed_consumer(
    native_keyed=true,
    keyed_start_observer=Some(read => {
      let selected = read.model.unwrap()
      let acquisition = read.acquisition.unwrap()
      let before = current_calls.val
      let same = installed_keyed_source_read_request_matches(
        read,
        acquisition,
        selected.keyed,
        selected.request,
        selected.model.compiled,
        selected.model.definition,
      )
      let foreign = match
        @publication_host.select_client_effect_composed_model_keyed_acquisition(
          selected.plan.prepared,
          selected.model.graph,
        ) {
        Ok(Some(duplicate)) =>
          !physical_equal(duplicate, selected.keyed) &&
          !installed_keyed_source_read_request_matches(
            read,
            acquisition,
            duplicate,
            selected.request,
            selected.model.compiled,
            selected.model.definition,
          )
        _ => false
      }
      let (_, _, _, other_run) = effect_model_plan_for_prepared(
        selected.plan.prepared,
        acquired=true,
      )
      let foreign_run = !installed_keyed_source_read_request_matches(
        read,
        acquisition,
        selected.keyed,
        selected.request,
        other_run.compiled,
        other_run.definition,
      )
      observed.val = same &&
        foreign &&
        foreign_run &&
        current_calls.val == before
    }),
    prepare_parent=Some((wire, selected_environment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selected_environment),
        effect_limits=Some(
          @publication_host.client_standard_effect_computation_limits(),
        ),
        current=() => {
          current_calls.val += 1
          true
        },
      )
      finish_effect_program_check_preparation(child).unwrap() |> ignore
      let prepared = compile_effect_program_check_preparation(child).unwrap()
      assert_true(
        physical_equal(
          continue_request_effect_preparation(parent, input).unwrap(),
          prepared,
        ),
      )
      (parent, input, prepared)
    }),
    foreign_run=Some(() => {
      let (prepared, _, _) = effect_operation_plan_inputs()
      effect_parent_bound_run(prepared)
    }),
  )
  assert_true(observed.val)
}

///|
#cfg(target="js")
test "Native keyed caller spends its original attempt before bytes and retains the same managed read" {
  original_composed_keyed_consumer(
    native_keyed=true,
    prepare_parent=Some((wire, selected_environment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selected_environment),
        effect_limits=Some(
          @publication_host.client_standard_effect_computation_limits(),
        ),
      )
      finish_effect_program_check_preparation(child).unwrap() |> ignore
      let prepared = compile_effect_program_check_preparation(child).unwrap()
      assert_true(
        physical_equal(
          continue_request_effect_preparation(parent, input).unwrap(),
          prepared,
        ),
      )
      (parent, input, prepared)
    }),
    foreign_run=Some(() => {
      let (prepared, _, _) = effect_operation_plan_inputs()
      effect_parent_bound_run(prepared)
    }),
  )
}

///|
#cfg(target="js")
test "Native keyed caller reentrant start retirement retains the actual unfinished child" {
  let observe : Ref[(() -> Unit)?] = Ref(None)
  let attempted = Ref(0)
  let retained = Ref(true)
  original_composed_keyed_consumer(
    native_keyed=true,
    keyed_start_observer=Some(read => {
      observe.val = Some(() => {
        if read.start is Constructing {
          attempted.val += 1
          retained.val = retained.val &&
            retire_installed_keyed_source_read(read) is Err(CleanupPending) &&
            !read.retired &&
            read.acquisition is Some(_)
        }
      })
    }),
    prepare_parent=Some((wire, selected_environment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selected_environment),
        effect_limits=Some(
          @publication_host.client_standard_effect_computation_limits(),
        ),
        current=() => {
          if observe.val is Some(callback) {
            callback()
          }
          true
        },
      )
      finish_effect_program_check_preparation(child).unwrap() |> ignore
      let prepared = compile_effect_program_check_preparation(child).unwrap()
      assert_true(
        physical_equal(
          continue_request_effect_preparation(parent, input).unwrap(),
          prepared,
        ),
      )
      (parent, input, prepared)
    }),
    foreign_run=Some(() => {
      let (prepared, _, _) = effect_operation_plan_inputs()
      effect_parent_bound_run(prepared)
    }),
  )
  observe.val = None
  assert_true(attempted.val > 0)
  assert_true(retained.val)
}

///|
#cfg(target="js")
test "Native keyed managed caller uses one predispatch original plan through Model input and retirement" {
  original_composed_keyed_consumer(
    native_keyed=true,
    pre_dispatch_plan=true,
    prepare_parent=Some((wire, selected_environment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selected_environment),
        effect_limits=Some(
          @publication_host.client_standard_effect_computation_limits(),
        ),
      )
      finish_effect_program_check_preparation(child).unwrap() |> ignore
      let prepared = compile_effect_program_check_preparation(child).unwrap()
      assert_true(
        physical_equal(
          continue_request_effect_preparation(parent, input).unwrap(),
          prepared,
        ),
      )
      (parent, input, prepared)
    }),
    foreign_run=Some(() => {
      let (prepared, _, _) = effect_operation_plan_inputs()
      effect_parent_bound_run(prepared)
    }),
  )
}

///|
#cfg(target="js")
test "Native keyed transport keeps the checked implementation on its original managed plan" {
  original_composed_keyed_consumer(
    native_keyed=true,
    pre_dispatch_plan=true,
    native_transport=true,
    prepare_parent=Some((wire, selected_environment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selected_environment),
        effect_limits=Some(
          @publication_host.client_standard_effect_computation_limits(),
        ),
      )
      finish_effect_program_check_preparation(child).unwrap() |> ignore
      let prepared = compile_effect_program_check_preparation(child).unwrap()
      assert_true(
        physical_equal(
          continue_request_effect_preparation(parent, input).unwrap(),
          prepared,
        ),
      )
      (parent, input, prepared)
    }),
    foreign_run=Some(() => {
      let (prepared, _, _) = effect_operation_plan_inputs()
      effect_parent_bound_run(prepared)
    }),
  )
}

///|
#cfg(target="js")
test "Native keyed activation retains the original first attempt and refuses duplicate preparation" {
  original_composed_keyed_consumer(
    native_keyed=true,
    native_activation=true,
    pre_dispatch_plan=true,
    native_transport=true,
    prepare_parent=Some((wire, selected_environment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selected_environment),
        effect_limits=Some(
          @publication_host.client_standard_effect_computation_limits(),
        ),
      )
      finish_effect_program_check_preparation(child).unwrap() |> ignore
      let prepared = compile_effect_program_check_preparation(child).unwrap()
      assert_true(
        physical_equal(
          continue_request_effect_preparation(parent, input).unwrap(),
          prepared,
        ),
      )
      (parent, input, prepared)
    }),
    foreign_run=Some(() => {
      let (prepared, _, _) = effect_operation_plan_inputs()
      effect_parent_bound_run(prepared)
    }),
  )
}

///|
#cfg(target="js")
test "Native keyed activation Source live reentry preserves the first returned original" {
  original_composed_keyed_consumer(
    whole=true,
    restored=true,
    native_activation=true,
    activation_reentry=true,
    pre_dispatch_plan=true,
    native_transport=true,
  )
}

///|
#cfg(target="js")
test "Native original left identity Source live reentry preserves the first returned original" {
  original_composed_keyed_consumer(
    whole=true,
    restored=true,
    left_identity_reentry=true,
    native_activation=true,
    pre_dispatch_plan=true,
    native_transport=true,
  )
}
