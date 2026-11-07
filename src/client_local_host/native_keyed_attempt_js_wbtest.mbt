///|
// Actual original Request/Effect Plan/Model Scope/keyed RowRun. Provider
// current/response ports remain explicit component inputs; no Native I/O or
// installed runtime/physical cleanup acknowledgement is claimed here.
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
