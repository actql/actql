///|
#borrow(root)
extern "C" fn test_fail_root_sync(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_root_sync"

///|
test "native retained task seal and release retain cleanup on sync failure" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-sync-" + @env.now().to_string()
  let file = begin_native_retained_task_file(root, occurrence, 3L).unwrap()
  file.append("abc").unwrap()
  test_fail_root_sync(file.root, 1)
  assert_true(file.seal("sha256:" + @sha256.hex(b"abc"), 3) is Err(_))
  assert_false(file.available())
  test_fail_root_sync(file.root, 1)
  assert_true(file.release() is Err(_))
  assert_false(file.release_confirmed())
  file.release().unwrap()
  assert_true(file.release_confirmed())
  assert_false(file.available())
}

///|
/// Let the sealed writer owner leave this scope. Its finalizer keeps the
/// committed file; restoration must acquire no writer or substitute identity.
fn sealed_restoration_fixture(
  root : String,
  occurrence : String,
) -> (@filesystem.NativeFileGeneration, String) raise {
  let file = begin_native_retained_task_file(root, occurrence, 3L).unwrap()
  file.append("abc").unwrap()
  let cid = "sha256:" + @sha256.hex(b"abc")
  assert_eq(file.sealed_generation(), None)
  file.seal(cid, 3).unwrap()
  (file.sealed_generation().unwrap(), cid)
}

///|
test "native retained missing release refuses existing storage and confirms missing synchronization" {
  guard native_retained_test_root() is Some(root) else {
    fail("private retained file Root required")
  }
  let occurrence = "task-file-missing-release-" + @env.now().to_string()
  let (generation, cid) = sealed_restoration_fixture(root, occurrence)
  let cleanup = restore_native_retained_task_file_cleanup(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  assert_eq(cleanup.confirm_missing_release().unwrap(), false)
  assert_false(cleanup.release_confirmed())
  assert_true(cleanup.root.verify_generation(cleanup.name, generation))
  // Only the existing physical file Owner performs the actual reclamation.
  let original = restore_native_retained_task_file_cleanup(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  original.release().unwrap()
  test_fail_root_sync(cleanup.root, 1)
  assert_true(cleanup.confirm_missing_release() is Err(Filesystem(_)))
  assert_false(cleanup.release_confirmed())
  assert_true(cleanup.root.inspect_generation(cleanup.name) is Ok(None))
  assert_true(cleanup.confirm_missing_release().unwrap())
  assert_true(cleanup.release_confirmed())
  assert_true(cleanup.confirm_missing_release().unwrap())
}

///|
test "native retained missing release rejects a live Owner and preserves replacement storage" {
  guard native_retained_test_root() is Some(root) else {
    fail("private retained file Root required")
  }
  let occurrence = "task-file-missing-replacement-" + @env.now().to_string()
  let live = begin_native_retained_task_file(root, occurrence, 3L).unwrap()
  assert_true(live.confirm_missing_release() is Err(InvalidState))
  live.append("abc").unwrap()
  let cid = "sha256:" + @sha256.hex(b"abc")
  live.seal(cid, 3).unwrap()
  let generation = live.sealed_generation().unwrap()
  let cleanup = restore_native_retained_task_file_cleanup(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  let pin = live.root.open_reader(live.name, generation).unwrap()
  live.release().unwrap()
  let replacement = live.root
    .create_writer("changed-" + occurrence, 3L)
    .unwrap()
  replacement.append(b"xyz").unwrap()
  let changed = replacement.seal(live.name).unwrap()
  assert_eq(cleanup.confirm_missing_release().unwrap(), false)
  assert_false(cleanup.release_confirmed())
  assert_true(cleanup.root.verify_generation(cleanup.name, changed))
  pin.close().unwrap()
  replacement.cancel().unwrap()
  assert_true(cleanup.confirm_missing_release().unwrap())
}

///|
test "native retained cleanup restoration denies reads and resumes missing unlink synchronization" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-cleanup-restore-" + @env.now().to_string()
  let (generation, cid) = sealed_restoration_fixture(root, occurrence)
  let owner = restore_native_retained_task_file(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  test_fail_root_sync(owner.root, 1)
  assert_true(owner.release() is Err(Filesystem(_)))
  assert_false(owner.release_confirmed())
  assert_true(owner.root.inspect_generation(owner.name) is Ok(None))
  assert_true(
    restore_native_retained_task_file(root, occurrence, generation, cid, 3L)
    is Err(_),
  )
  let cleanup = restore_native_retained_task_file_cleanup(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  assert_false(cleanup.available())
  assert_eq(cleanup.sealed_custody(), None)
  assert_true(cleanup.open_reader() is Err(InvalidState))
  assert_true(cleanup.append("x") is Err(InvalidState))
  test_fail_root_sync(cleanup.root, 1)
  assert_true(cleanup.release() is Err(Filesystem(_)))
  assert_false(cleanup.release_confirmed())
  cleanup.release().unwrap()
  assert_true(cleanup.release_confirmed())
  cleanup.release().unwrap()
}

///|
test "native retained cleanup restoration preserves a replacement until exact retry" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-cleanup-replacement-" + @env.now().to_string()
  let (generation, cid) = sealed_restoration_fixture(root, occurrence)
  let physical = @filesystem.open_root(root).unwrap()
  let pin = physical.open_reader("output-" + occurrence, generation).unwrap()
  physical.reclaim_generation("output-" + occurrence, generation).unwrap()
  let replacement = physical
    .create_writer("replacement-" + occurrence, 3L)
    .unwrap()
  replacement.append(b"xyz").unwrap()
  let changed = replacement.seal("output-" + occurrence).unwrap()
  let cleanup = restore_native_retained_task_file_cleanup(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  assert_true(
    cleanup.release() is Err(Filesystem(@filesystem.GenerationMismatch)),
  )
  assert_false(cleanup.release_confirmed())
  assert_true(physical.verify_generation("output-" + occurrence, changed))
  pin.close().unwrap()
  replacement.cancel().unwrap()
  cleanup.release().unwrap()
  assert_true(cleanup.release_confirmed())
}

///|
test "native retained task restoration reads original bytes without a new writer" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-restore-" + @env.now().to_string()
  let (generation, cid) = sealed_restoration_fixture(root, occurrence)
  let file = restore_native_retained_task_file(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  assert_eq(file.sealed_generation(), Some(generation))
  assert_eq(file.sealed_content(), Some((cid, 3L)))
  assert_true(file.root.inspect_generation("stage-" + occurrence) is Ok(None))
  assert_true(file.append("x") is Err(InvalidState))
  assert_true(file.seal(cid, 3) is Err(InvalidState))
  let reader = file.open_reader().unwrap()
  assert_true(file.release() is Err(InvalidState))
  assert_eq(reader.next(3).unwrap().bytes, b"abc")
  assert_true(reader.next(3).unwrap().eof)
  reader.finish().unwrap()
  file.release().unwrap()
  assert_true(file.release_confirmed())
  assert_eq(file.sealed_generation(), None)
  file.release().unwrap()
  assert_true(file.root.inspect_generation(file.name) is Ok(None))
}

///|
test "native retained task restoration refuses missing generation and capacity mismatch" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-restore-refusal-" + @env.now().to_string()
  let (generation, cid) = sealed_restoration_fixture(root, occurrence)
  assert_true(
    restore_native_retained_task_file(root, occurrence, generation, cid, 2L)
    is Err(InvalidLimit),
  )
  assert_true(
    restore_native_retained_task_file(root, occurrence, generation, "wrong", 3L)
    is Err(ContentMismatch),
  )
  assert_true(
    restore_native_retained_task_file(
      root,
      occurrence + "-missing",
      generation,
      cid,
      3L,
    )
    is Err(Filesystem(@filesystem.GenerationMismatch)),
  )
  let file = restore_native_retained_task_file(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  assert_true(file.available())
  file.release().unwrap()
  assert_true(
    restore_native_retained_task_file(root, occurrence, generation, cid, 3L)
    is Err(Filesystem(@filesystem.GenerationMismatch)),
  )
}

///|
test "native retained task restored cleanup preserves replacement and retries root sync" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-restore-cleanup-" + @env.now().to_string()
  let (generation, cid) = sealed_restoration_fixture(root, occurrence)
  let file = restore_native_retained_task_file(
    root, occurrence, generation, cid, 3L,
  ).unwrap()
  // Keep the unlinked inode alive so replacement identity differs
  // deterministically, independently of filesystem inode recycling.
  let pinned_generation = file.root.open_reader(file.name, generation).unwrap()
  file.root.reclaim_generation(file.name, generation).unwrap()
  let replacement = file.root
    .create_writer("replacement-" + occurrence, 3L)
    .unwrap()
  replacement.append(b"xyz").unwrap()
  let replacement_generation = replacement.seal(file.name).unwrap()
  assert_true(file.release() is Err(Filesystem(@filesystem.GenerationMismatch)))
  assert_false(file.release_confirmed())
  assert_true(file.root.verify_generation(file.name, replacement_generation))
  assert_true(
    restore_native_retained_task_file(root, occurrence, generation, cid, 3L)
    is Err(Filesystem(@filesystem.GenerationMismatch)),
  )
  pinned_generation.close().unwrap()
  replacement.cancel().unwrap()
  test_fail_root_sync(file.root, 1)
  assert_true(file.release() is Err(Filesystem(_)))
  assert_false(file.release_confirmed())
  file.release().unwrap()
  assert_true(file.release_confirmed())
  file.release().unwrap()
}

///|
test "native retained task restored input remains provisional until complete hash verification" {
  guard native_retained_test_root() is Some(root) else { return }
  let occurrence = "task-file-restore-integrity-" + @env.now().to_string()
  let (generation, _) = sealed_restoration_fixture(root, occurrence)
  let wrong = "sha256:" + @sha256.hex(b"abd")
  let file = restore_native_retained_task_file(
    root, occurrence, generation, wrong, 3L,
  ).unwrap()
  let reader = file.open_reader().unwrap()
  assert_eq(reader.next(3).unwrap().bytes, b"abc")
  assert_true(reader.next(3).unwrap().eof)
  assert_true(reader.finish() is Err(ContentMismatch))
  assert_false(file.available())
  assert_eq(file.sealed_generation(), None)
  assert_true(file.open_reader() is Err(InvalidState))
  reader.close().unwrap()
  file.release().unwrap()
  assert_true(file.release_confirmed())
}
