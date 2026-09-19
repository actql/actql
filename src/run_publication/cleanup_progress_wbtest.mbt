///|
test "prepared publication cleanup releases in reverse owner order" {
  assert_eq(
    prepare_publication_prepared_release_step(2, 3, false, false, false),
    PublicationInspectPreparedRelease,
  )
  assert_eq(
    prepare_publication_prepared_release_step(2, 3, true, true, false),
    PublicationReleasePrepared,
  )
  assert_eq(
    prepare_publication_prepared_release_step(2, 3, true, true, true),
    PublicationAdvancePreparedRelease,
  )
  assert_eq(
    prepare_publication_prepared_release_step(1, 3, true, false, false),
    PublicationAdvancePreparedRelease,
  )
  assert_eq(
    prepare_publication_prepared_release_step(-1, 3, false, false, false),
    PublicationPreparedReleaseFinished,
  )
  assert_eq(
    prepare_publication_prepared_release_step(3, 3, false, false, false),
    PublicationPreparedReleaseInvalid,
  )
}

///|
test "publication cleanup retries each live owner independently" {
  assert_eq(
    prepare_publication_cleanup_owner_step(0, 2, false, false, false, false),
    PublicationInspectCleanupOwner,
  )
  assert_eq(
    prepare_publication_cleanup_owner_step(0, 2, true, true, true, false),
    PublicationRetryCleanupOwner,
  )
  assert_eq(
    prepare_publication_cleanup_owner_step(0, 2, true, true, true, true),
    PublicationAdvanceCleanupOwner,
  )
  assert_eq(
    prepare_publication_cleanup_owner_step(1, 2, true, false, true, false),
    PublicationAdvanceCleanupOwner,
  )
  assert_eq(
    prepare_publication_cleanup_owner_step(2, 2, false, false, false, false),
    PublicationCleanupOwnersFinished,
  )
  assert_eq(
    prepare_publication_cleanup_owner_step(3, 2, false, false, false, false),
    PublicationCleanupOwnerInvalid,
  )
}
