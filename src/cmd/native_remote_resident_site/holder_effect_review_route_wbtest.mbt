///|
/// Route assembly uses a Checkpoint issued by its existing Owner. This fixture
/// does not prove Provider Preview, Store persistence, ACK or HTTP acceptance.
test "holder Review artifact URL keeps the installed Site generation and original sealed checkpoint" {
  let cid = "sha256:" + "a".repeat(64)
  let checkpoint = @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "original-review",
      continuation_state_cid: cid,
      subject: @checkpoint.RunUnit(
        run_id="original-run",
        unit_id="compute",
        run_definition_cid=cid,
      ),
      phase: @checkpoint.Commit,
      kind: @checkpoint.EffectSet,
      required_artifact_cid: cid,
      review_projection_cid: cid,
      requirements: [@checkpoint.EffectScopeApproved],
      reason_code: "effect_review_required",
      human_summary: "Original review",
      created_at: "2026-10-10T00:00:00.000Z",
      expires_at: "2099-01-01T00:00:00.000Z",
    },
    resident_checkpoint_report_limits(),
  ).unwrap()
  let original = "https://cloud.invalid/v1/sites/original-site/generations/7/outbound/observations"
  let selected = holder_effect_review_artifact_url(original, checkpoint).unwrap()
  assert_true(
    selected.has_prefix(
      "https://cloud.invalid/v1/sites/original-site/generations/7/effect-reviews/",
    ),
  )
  assert_true(selected.has_suffix(checkpoint.checkpoint_cid))
  for
    invalid in [
      "http://cloud.invalid/v1/sites/original-site/generations/7/outbound/observations",
      "https://cloud.invalid/v1/sites/original-site/generations/7/outbound/poll",
      original + "?route=other",
    ] {
    assert_true(holder_effect_review_artifact_url(invalid, checkpoint) is None)
  }
}

///|
/// Use the same configured Site/generation route as observations. Only a
/// sealed Checkpoint from the original report supplies the final path member;
/// no candidate URL, future checkpoint identity or new hash is accepted.
fn holder_effect_review_artifact_url(
  observation_url : String,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> String? {
  let suffix = "/outbound/observations"
  if !observation_url.has_prefix("https://") ||
    !observation_url.has_suffix(suffix) {
    return None
  }
  Some(
    observation_url.unsafe_substring(
      start=0,
      end=observation_url.length() - suffix.length(),
    ) +
    "/effect-reviews/" +
    checkpoint.checkpoint_cid,
  )
}
