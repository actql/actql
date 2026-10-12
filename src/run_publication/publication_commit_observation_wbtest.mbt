///|
/// These nominal probes deliberately do not prove a semantic evidence chain.
test "stored validation shares original workspace and cannot release live borrow" {
  let owner = commit_view_lifecycle_probe(25)
  let original = owner.inputs.unwrap()
  let view = owner.finish_view().unwrap()
  owner
  .begin_observed_commit(
    view,
    original.request,
    original.attempt,
    original.index_entry,
  )
  .unwrap()
  let child = view.observed.unwrap()
  assert_eq(owner.live, 13)
  assert_eq(child.max_workspace, 12)
  assert_eq(child.live, 12)
  assert_eq(owner.peak, 25)
  assert_true(
    physical_equal(
      child.inputs.unwrap().computation.definitions,
      original.computation.definitions,
    ),
  )
  assert_true(owner.release_view(view) is Err(CommitEncoding))
  owner.cancel()
  assert_true(child.closed)
  assert_true(child.inputs is None)
  assert_true(owner.inputs is Some(_))
  assert_true(view.owner is Some(_))
  owner.release_observed_commit(view).unwrap()
  owner.release_view(view).unwrap()
  assert_true(owner.inputs is None)
  assert_eq(owner.live, 0)
}

///|
test "stored validation insufficient workspace does not silently mint a budget" {
  let owner = commit_view_lifecycle_probe(24)
  let original = owner.inputs.unwrap()
  let view = owner.finish_view().unwrap()
  assert_true(
    owner.begin_observed_commit(
      view,
      original.request,
      original.attempt,
      original.index_entry,
    )
    is Err(CommitEncoding),
  )
  assert_true(view.observed is None)
  assert_eq(owner.live, 13)
  assert_eq(owner.peak, 13)
  assert_true(physical_equal(owner.inputs.unwrap(), original))
  owner.release_view(view).unwrap()
}
