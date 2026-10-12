///|
/// Lower-level nominal/lifetime checks. The black-box binding-view file closes
/// real complete evidence; this probe deliberately skips semantic validation.
test "commit binding view copied token cannot acquire original inputs" {
  let preparation = commit_view_lifecycle_probe(13)
  let inputs = preparation.inputs.unwrap()
  let view = preparation.finish_view().unwrap()
  let copied : PublicationCommitReadView = {
    owner: Some(preparation),
    released: false,
    observed: None,
  }
  assert_true(preparation.view_binding(copied, 0) is Err(CommitEncoding))
  let binding = preparation.view_binding(view, 0).unwrap()
  assert_true(physical_equal(binding, inputs.bindings[0]))
  assert_true(physical_equal(preparation.inputs.unwrap(), inputs))
  assert_eq(preparation.live, 13)
  assert_eq(preparation.peak, 13)
  preparation.release_view(view).unwrap()
}

///|
test "commit binding view cancelled borrow retains original descriptor until same cleanup" {
  let preparation = commit_view_lifecycle_probe(13)
  let inputs = preparation.inputs.unwrap()
  let view = preparation.finish_view().unwrap()
  preparation.cancel()
  assert_true(preparation.view_binding(view, 0) is Err(CommitEncoding))
  assert_true(physical_equal(preparation.inputs.unwrap(), inputs))
  assert_eq(preparation.live, 13)
  preparation.release_view(view).unwrap()
  assert_eq(preparation.live, 0)
  assert_true(preparation.inputs is None)
  preparation.release_view(view).unwrap()
  assert_eq(preparation.live, 0)
}
