///|
// Original request/Run codecs and the actual journal transaction, without
// executing work, publishing a Result or issuing read permission.
fn run_observation_reuse_fixture(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  @host.ClientRequestIdentity,
  @host.PreparedClientProgram,
  @host.ClientCompiledRun,
  NativeClientRunRecord,
) raise {
  let (database, journal, authority, reference) = submitted_test_setup(name)
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, initial_compiled, definition) = submitted_run_test_input(
    reference, name,
  )
  // The later Policy CAS uses the actual captured source-free Result policy,
  // not a missing-dependency placeholder or an inferred permission.
  let compiled = @host.with_client_source_free_result_policy(
    initial_compiled,
    selected_policy_fixture_cid,
    @host.client_local_product_assets().result_policy,
    65536,
    8192,
    64,
  ).unwrap()
  guard preparation.preparation is Computation(prepared) else {
    fail("expected actual checked computation")
  }
  journal.operation_active = true
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1001.0,
  )
  .unwrap()
  |> ignore
  guard journal.operation_run_identity is Some((_, _, _, Some(issued))) else {
    fail("missing first-admission metadata")
  }
  let original = journal.retained(request).unwrap().unwrap()
  assert_true(physical_equal(original.observation_original.unwrap(), issued))
  (database, journal, request, prepared, compiled, original)
}

///|
test "unchanged Run compiler metadata is admitted once across unrelated row revisions" {
  let (database, journal, request, prepared, compiled, first) = run_observation_reuse_fixture(
    "observation-unrelated-cas",
  )
  let original = first.observation_original.unwrap()
  let plan = original.plan.unwrap()
  let (updated, observed) = journal
    .transaction(() => {
      let updated = journal
        .save({
          ..first,
          publication_binding: Some("sha256:" + "b".repeat(64)),
        })
        .unwrap()
      Ok((updated, journal.retained(request).unwrap().unwrap()))
    })
    .unwrap()
  assert_false(physical_equal(updated, observed))
  assert_eq(observed.publication_binding, updated.publication_binding)
  assert_eq(observed.revision, first.revision + 1L)
  assert_true(physical_equal(observed.observation_original.unwrap(), original))
  let policies = run_policy_originals_wire(prepared, compiled~).unwrap()
  let next = journal
    .transaction(() => {
      journal
      .save({ ..observed, publication_policy_originals: Some(policies), })
      .unwrap()
      |> ignore
      journal.retained(request)
    })
    .unwrap()
    .unwrap()
  assert_eq(next.publication_policy_originals, Some(policies))
  assert_true(physical_equal(next.observation_original.unwrap(), original))
  assert_true(
    physical_equal(next.observation_original.unwrap().plan.unwrap(), plan),
  )
  assert_eq(next.run_observation_originals, first.run_observation_originals)
  journal.operation_active = false
  journal.invalidate_operation_record()
  guard journal.lookup(request, true).unwrap() is Retained(fresh) else {
    fail("missing committed original")
  }
  assert_false(physical_equal(fresh.observation_original.unwrap(), original))
  assert_eq(fresh.observation_original.unwrap().plan.unwrap().view, plan.view)
  database.close_checked().unwrap()
}

///|
test "changed compiler metadata and failed transaction cannot revive retained Run originals" {
  let (database, journal, request, _, _, first) = run_observation_reuse_fixture(
    "observation-changed-cas",
  )
  let original = first.observation_original.unwrap()
  assert_false(
    original.matches(original.wire, first.definition, Some("foreign-program")),
  )
  let changed = original.wire.replace(old="\"plan\"", new="\"foreign_plan\"")
  assert_false(
    original.matches(changed, first.definition, original.program_cid),
  )
  let invalidated = Ref(false)
  let result : Result[Unit, NativeClientRunJournalIssue] = journal.transaction(() => {
    let emitted = journal
      .save({ ..first, run_observation_originals: Some(changed), })
      .unwrap()
    invalidated.val = emitted.observation_original is None
    match journal.retained(request) {
      Err(CustodyLost) => Err(CustodyLost)
      _ => Ok(())
    }
  })
  assert_true(invalidated.val)
  assert_true(result is Err(CustodyLost))
  assert_true(journal.operation_run_identity is None)
  assert_true(journal.admitted_record is None)
  let restored = journal.retained(request).unwrap().unwrap()
  assert_eq(restored.revision, first.revision)
  assert_eq(restored.run_observation_originals, first.run_observation_originals)
  assert_false(physical_equal(restored.observation_original.unwrap(), original))
  journal.operation_active = false
  journal.invalidate_operation_record()
  database.close_checked().unwrap()
}
