///|
test "commit diagnostics separate original Store evidence refusal from uncertain fence without wire data" {
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = fields.get(tag).unwrap_or(0L) + value
  local_publication_commit_failure_tags(
    @local_publication.Store(
      PublicationCommit(CommitEvidence(EvidenceEncoding)),
    ),
    emit,
  )
  assert_eq(fields.get(10), Some(11L))
  assert_eq(fields.get(11), Some(9005L))
  assert_eq(fields.get(12), Some(1101L))
  assert_eq(fields.get(15), None)
  fields.clear()
  local_publication_commit_failure_tags(
    @local_publication.CommitFenceUnavailable,
    emit,
  )
  assert_eq(fields.get(11), Some(9004L))
  assert_eq(fields.get(12), Some(0L))
  fields.clear()
  local_publication_commit_failure_tags(
    @local_publication.Store(Database(BodyTooLarge)),
    emit,
  )
  assert_eq(fields.get(11), Some(9005L))
  assert_eq(fields.get(12), Some(1L))
  assert_eq(fields.get(15), Some(10L))
  fields.clear()
  local_publication_commit_failure_tags(
    @local_publication.Issuance(CommitIssuanceEncoding),
    emit,
  )
  assert_eq(fields.get(11), Some(9006L))
  assert_eq(fields.get(12), Some(5L))
  fields.clear()
  local_publication_commit_failure_tags(
    @local_publication.Store(
      PublicationCommit(
        CommitEvidence(EvidenceEmbeddedIdentity("authoring_context_cid")),
      ),
    ),
    emit,
  )
  assert_eq(fields.get(11), Some(9005L))
  assert_eq(fields.get(12), Some(2064L))
}
