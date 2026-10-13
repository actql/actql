///|
test "observed Result read selects original complete stored chain without replacing candidate or issuing grant" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let names = manifest_result_names(fixture.originals[2]).unwrap()
  let name = names[0]
  assert_true(
    owner.observed_result_read_materials(view, name, 16)
    is Err(Commit(CommitEncoding)),
  )
  let (attempt, stored) = observed_commit_test_pair(fixture)
  owner
  .begin_observed_commit(view, fixture.originals[5], attempt, stored)
  .unwrap()
  assert_true(
    owner.observed_result_read_materials(view, name, 16)
    is Err(Commit(CommitEncoding)),
  )
  observed_commit_test_complete(owner, view, 64) |> ignore
  let selected = owner.observed_result_read_materials(view, name, 16).unwrap()
  assert_true(physical_equal(selected.index, stored))
  assert_true(physical_equal(selected.manifest, fixture.originals[2]))
  assert_true(
    physical_equal(owner.view_contract(view, 7).unwrap(), fixture.originals[7]),
  )
  assert_eq(selected.read.result_name, name)
  assert_eq(
    selected.read.result_schema_cid,
    "sha256:98fbcb0aa0d1065cf0b027b6390716452941ac4723d0b2cadfce3476280683db",
  )
  assert_eq(selected.read.material_generation_cid, ordering_test_cid("2"))
  assert_eq(selected.read.store_authority_cid, ordering_test_cid("3"))
  assert_eq(selected.read.result_fields, ["value"])
  assert_eq(selected.read.row_count, 1L)
  assert_eq(selected.read.byte_count, 13L)
  assert_eq(selected.read.physical_sha256, "4".repeat(64))
  assert_eq(
    publication_contract_identity(selected.retention),
    selected.read.effective_retention_policy_cid,
  )
  assert_eq(
    publication_contract_identity(selected.definition),
    selected.read.result_definition_cid,
  )
  assert_eq(
    publication_contract_identity(selected.artifact),
    selected.read.result_artifact_cid,
  )
  owner.release_observed_commit(view).unwrap()
  owner.release_view(view).unwrap()
}

///|
test "observed Result read rejects foreign cancelled closed missing and out of bound materials" {
  let fixture = commit_read_fixture()
  let owner = fixture.preparation
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  let other = commit_read_fixture()
  commit_read_complete(other.preparation, 64) |> ignore
  let foreign = other.preparation.finish_view().unwrap()
  assert_true(
    owner.observed_result_read_materials(foreign, "answer", 16)
    is Err(Commit(CommitEncoding)),
  )
  let (attempt, stored) = observed_commit_test_pair(fixture)
  owner
  .begin_observed_commit(view, fixture.originals[5], attempt, stored)
  .unwrap()
  observed_commit_test_complete(owner, view, 64) |> ignore
  assert_true(
    owner.observed_result_read_materials(view, "missing", 16)
    is Err(Projection(DeliveryIssuanceUnknownResult("missing"))),
  )
  assert_true(
    owner.observed_result_read_materials(view, "answer", 0)
    is Err(Projection(DeliveryIssuanceInvalidLimit)),
  )
  owner.cancel()
  assert_true(
    owner.observed_result_read_materials(view, "answer", 16)
    is Err(Commit(CommitEncoding)),
  )
  owner.release_observed_commit(view).unwrap()
  assert_true(
    owner.observed_result_read_materials(view, "answer", 16)
    is Err(Commit(CommitEncoding)),
  )
  owner.release_view(view).unwrap()
  assert_true(
    owner.observed_result_read_materials(view, "answer", 16)
    is Err(Commit(CommitEncoding)),
  )
  other.preparation.release_view(foreign).unwrap()
}
