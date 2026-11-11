///|
// The same checked Whole Source roots feed both the keyed prefix and the
// normal Model input. Imported completions preserve the original occurrence;
// a different source slot and a retired lookup are not substitutes.
#cfg(target="js")
test "keyed and Model share the original completed Source producers without replay" {
  composed_shared_source_custody()
}

///|
#cfg(target="js")
test "restored Source custody binds the same completed producer without reopening its read" {
  composed_shared_source_custody(restored=true)
}

///|
#cfg(target="js")
fn composed_shared_source_custody(restored? : Bool = false) -> Unit raise {
  original_composed_keyed_consumer(
    whole=true,
    shared_source_producers=true,
    restored~,
    prepare_parent=Some((wire, selectedEnvironment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selectedEnvironment),
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
  )
}
