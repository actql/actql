///|
fn snapshot_test_completion() -> Completed[Unit, Int] {
  let binding = fixture_binding()
  let receipt = complete_receipt(binding, RelationMeasure(rows=1, columns=1)).unwrap()
  complete(
    retain(
      prepare_retention_port(binding, (_ : Unit) => {
        Some((receipt, (), 42, 16L, () => true))
      }),
      (),
    ).unwrap(),
  ).unwrap()
}

///|
fn snapshot_test_material(
  completed : Completed[Unit, Int],
  factory : SnapshotFactory?,
  reclaimed : Ref[Int],
) -> Material {
  prepare_material(
    completion_reference(completed),
    (_, _, _) => None,
    (_, _, _, _) => None,
    () => {
      reclaim_completed(completed, _ => {
        reclaimed.val += 1
        true
      })
    },
    snapshot_factory=factory,
  ).unwrap()
}

///|
fn snapshot_test_operation(
  reference : CompletionReference,
  cleanup : () -> Result[Bool, SnapshotIssue],
) -> SnapshotIO {
  prepare_snapshot_io(
    reference,
    100,
    10,
    100L,
    _ => Ok({ complete: false, progress: 0L, work: 0L, issue: None, }),
    () => Ok(""),
    () => Err(SnapshotUnavailable),
    _ => Err(SnapshotUnavailable),
    (_, _) => Err(SnapshotUnavailable),
    _ => Err(SnapshotUnavailable),
    () => Err(SnapshotUnavailable),
    cleanup,
  ).unwrap()
}

///|
test "snapshot claim is exact-generation and once-only across aliases" {
  let completed = snapshot_test_completion()
  let calls = Ref(0)
  let cleanup_calls = Ref(0)
  let reclaimed = Ref(0)
  let operation = snapshot_test_operation(completion_reference(completed), () => {
    cleanup_calls.val += 1
    Ok(true)
  })
  let factory = prepare_snapshot_factory(completion_reference(completed), () => {
    calls.val += 1
    Ok(operation)
  }).unwrap()
  let material = snapshot_test_material(completed, Some(factory), reclaimed)
  let same_material = material
  assert_true(material_prepare_snapshot(material).unwrap() is Some(_))
  assert_true(
    material_prepare_snapshot(same_material) is Err(SnapshotAlreadyClaimed),
  )
  assert_eq(calls.val, 1)
  assert_true(reclaim_material(material))
  assert_false(material_cleanup_pending(material))
  assert_false(reclaim_material(same_material))
  assert_eq((cleanup_calls.val, reclaimed.val), (1, 1))
}

///|
test "foreign snapshot factory performs no acquisition even with equal checked contents" {
  let completed = snapshot_test_completion()
  let other = snapshot_test_completion()
  let calls = Ref(0)
  let reclaimed = Ref(0)
  let factory = prepare_snapshot_factory(completion_reference(other), () => {
    calls.val += 1
    Ok(snapshot_test_operation(completion_reference(other), () => Ok(true)))
  }).unwrap()
  let material = snapshot_test_material(completed, Some(factory), reclaimed)
  assert_true(
    material_prepare_snapshot(material) is Err(SnapshotForeignGeneration),
  )
  assert_eq(calls.val, 0)
  assert_true(completed_available(completed))
  assert_true(completed_available(other))
  assert_true(reclaim_material(material))
  assert_true(completed_available(other))
}

///|
test "snapshot creation failure cannot allocate again and keeps source custody" {
  let completed = snapshot_test_completion()
  let calls = Ref(0)
  let reclaimed = Ref(0)
  let factory = prepare_snapshot_factory(completion_reference(completed), () => {
    calls.val += 1
    Err(SnapshotFamilyFailure("injected preparation failure"))
  }).unwrap()
  let material = snapshot_test_material(completed, Some(factory), reclaimed)
  assert_true(
    material_prepare_snapshot(material) is Err(SnapshotFamilyFailure(_)),
  )
  assert_true(
    material_prepare_snapshot(material) is Err(SnapshotAlreadyClaimed),
  )
  assert_eq(calls.val, 1)
  assert_true(material_cleanup_pending(material))
  assert_true(reclaim_material(material))
  assert_eq(reclaimed.val, 1)
}

///|
test "rejected operation keeps cleanup custody through failure and retry" {
  let completed = snapshot_test_completion()
  let other = snapshot_test_completion()
  let cleanup_calls = Ref(0)
  let reclaimed = Ref(0)
  let operation = snapshot_test_operation(completion_reference(other), () => {
    cleanup_calls.val += 1
    match cleanup_calls.val {
      1 => Err(SnapshotFamilyFailure("injected cleanup failure"))
      2 => Ok(false)
      _ => Ok(true)
    }
  })
  let factory = prepare_snapshot_factory(completion_reference(completed), () => {
    Ok(operation)
  }).unwrap()
  let material = snapshot_test_material(completed, Some(factory), reclaimed)
  assert_true(
    material_prepare_snapshot(material) is Err(SnapshotForeignGeneration),
  )
  assert_true(
    material_prepare_snapshot(material) is Err(SnapshotAlreadyClaimed),
  )
  assert_false(reclaim_material(material))
  assert_false(reclaim_material(material))
  assert_eq(reclaimed.val, 0)
  assert_true(material_cleanup_pending(material))
  assert_true(reclaim_material(material))
  assert_false(reclaim_material(material))
  assert_eq((cleanup_calls.val, reclaimed.val), (3, 1))
  assert_true(completed_available(other))
}

///|
test "revoked source still owns an unfinished snapshot cleanup" {
  let completed = snapshot_test_completion()
  let cleanup_calls = Ref(0)
  let reclaimed = Ref(0)
  let operation = snapshot_test_operation(completion_reference(completed), () => {
    cleanup_calls.val += 1
    Ok(cleanup_calls.val > 1)
  })
  let factory = prepare_snapshot_factory(completion_reference(completed), () => {
    Ok(operation)
  }).unwrap()
  let material = snapshot_test_material(completed, Some(factory), reclaimed)
  material_prepare_snapshot(material).unwrap() |> ignore
  reclaim_completed(completed, _ => true) |> ignore
  assert_false(material_available(material))
  assert_true(material_cleanup_pending(material))
  assert_false(reclaim_material(material))
  assert_true(material_cleanup_pending(material))
  reclaim_material(material) |> ignore
  assert_false(material_cleanup_pending(material))
  reclaim_material(material) |> ignore
  assert_eq(cleanup_calls.val, 2)
  assert_eq(reclaimed.val, 0)
}
