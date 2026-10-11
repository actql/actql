///|
/// Lower-level lifecycle probe only. This deliberately bypasses validation;
/// the black-box read-view tests validate a real complete evidence chain.
fn commit_view_lifecycle_probe(workspace : Int) -> PublicationCommitPreparation {
  let fixture = commit_cursor_fixture(["answer"])
  let refs = fixture.reference_inputs
  let bindings = fixture.binding_inputs
  let preparation = start_effect_free_publication_commit_check(
    refs.run_definition,
    refs.invocation,
    refs.definitions,
    bindings.artifacts,
    [],
    bindings.orderings,
    bindings.retentions,
    bindings.bindings,
    refs.manifest,
    refs.receipt,
    refs.captured_run,
    refs.request,
    refs.attempt,
    refs.index_entry,
    65536,
    4096,
    32,
    workspace,
  )
  preparation.phase = Done
  preparation
}

///|
test "commit view descriptor uses original workspace and cancellation retains borrow" {
  let refused = commit_view_lifecycle_probe(12)
  assert_true(refused.finish_view() is Err(CommitEncoding))
  assert_eq(refused.live, 12)
  assert_true(refused.inputs is Some(_))
  refused.cancel()
  assert_eq(refused.live, 0)
  let preparation = commit_view_lifecycle_probe(13)
  let inputs = preparation.inputs.unwrap()
  let view = preparation.finish_view().unwrap()
  assert_eq(preparation.live, 13)
  assert_eq(preparation.peak, 13)
  assert_true(physical_equal(preparation.inputs.unwrap(), inputs))
  preparation.cancel()
  preparation.cancel()
  assert_eq(preparation.live, 13)
  assert_true(physical_equal(preparation.inputs.unwrap(), inputs))
  assert_true(preparation.view_contract(view, 0) is Err(CommitEncoding))
  // A physical cleanup failure must not call release_view. Retrying physical
  // cleanup holds these same originals and descriptor; only success releases.
  preparation.release_view(view).unwrap()
  assert_eq(preparation.live, 0)
  assert_eq(preparation.peak, 13)
  assert_true(preparation.inputs is None)
  preparation.release_view(view).unwrap()
  assert_eq(preparation.live, 0)
}

///|
test "commit view copied descriptor cannot borrow or release original inputs" {
  let preparation = commit_view_lifecycle_probe(13)
  let view = preparation.finish_view().unwrap()
  let copy : PublicationCommitReadView = {
    owner: Some(preparation),
    released: false,
  }
  assert_true(preparation.view_count(copy) is Err(CommitEncoding))
  assert_true(preparation.view_contract(copy, 7) is Err(CommitEncoding))
  assert_true(preparation.release_view(copy) is Err(CommitEncoding))
  assert_eq(preparation.live, 13)
  preparation.release_view(view).unwrap()
  assert_true(view.owner is None)
  copy.released = true
  assert_true(preparation.release_view(copy) is Err(CommitEncoding))
}
