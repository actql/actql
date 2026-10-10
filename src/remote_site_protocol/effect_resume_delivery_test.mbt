///|
test "Effect resume delivery preserves original report Resolution and claim" {
  let (report, auth, reviewers, verified_wire, fixed) = effect_resume_fixture()
  let resolution = @checkpoint.admit_attested_effect_resolution(
      remote_effect_checkpoint_report_checkpoint(report),
      verified_wire,
      auth,
      reviewers,
      review_limits(),
    ).unwrap().resolution
  let claim : @checkpoint.ResumeClaim = {
    claimant: "original-coordinator",
    generation: 1L,
  }
  let prepared = prepare_remote_effect_resume_delivery(
    report,
    resolution,
    claim,
    review_limits(),
  ).unwrap()
  assert_eq(remote_effect_resume_delivery_json(prepared), fixed)
  let admitted = admit_remote_effect_resume_delivery_json(
    fixed,
    report,
    auth,
    reviewers,
    review_limits(),
  ).unwrap()
  assert_eq(remote_effect_resume_delivery_resolution(admitted), resolution)
  assert_eq(remote_effect_resume_delivery_claim(admitted), claim)
  assert_eq(remote_effect_resume_delivery_json(admitted), fixed)
}

///|
test "Effect resume delivery rejects substituted identities and alternate wire" {
  let (report, auth, reviewers, _, fixed) = effect_resume_fixture()
  for
    field in [
      "checkpoint_cid", "dispatch_request_cid", "report_cid", "resolution_cid", "resume_intent_id",
    ] {
    let wire = fixed.replace(
      old="\"" + field + "\":\"",
      new="\"" + field + "\":\"foreign-",
    )
    assert_true(
      admit_remote_effect_resume_delivery_json(
        wire,
        report,
        auth,
        reviewers,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  for
    wire in [
      fixed + "\n",
      fixed.replace(old="\"generation\":\"1\"", new="\"generation\":\"0\""),
      fixed.replace(old="\"generation\":\"1\"", new="\"generation\":\"01\""),
      fixed.replace(
        old="\"generation\":\"1\"",
        new="\"generation\":\"9223372036854775808\"",
      ),
      fixed.replace(
        old="\"claimant\":\"original-coordinator\"",
        new="\"claimant\":\"\"",
      ),
      fixed.replace(
        old="\"claimant\":\"original-coordinator\"",
        new="\"claimant\":\"original-coordinator\",\"claimant\":\"original-coordinator\"",
      ),
      fixed.replace(
        old="{\"checkpoint_cid\"",
        new="{\"unknown\":\"value\",\"checkpoint_cid\"",
      ),
    ] {
    assert_true(
      admit_remote_effect_resume_delivery_json(
        wire,
        report,
        auth,
        reviewers,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  assert_true(
    admit_remote_effect_resume_delivery_json(
      fixed,
      report,
      { ..auth, reviewer_id: "another-reviewer", },
      reviewers,
      review_limits(),
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_effect_resume_delivery_json(
      fixed,
      report,
      auth,
      [],
      review_limits(),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "Effect resume delivery rejects invalid claim and bounded body" {
  let (report, auth, reviewers, verified_wire, fixed) = effect_resume_fixture()
  let resolution = @checkpoint.admit_attested_effect_resolution(
      remote_effect_checkpoint_report_checkpoint(report),
      verified_wire,
      auth,
      reviewers,
      review_limits(),
    ).unwrap().resolution
  let invalid : Array[@checkpoint.ResumeClaim] = [
    { claimant: "", generation: 1L, },
    { claimant: "original-coordinator", generation: 0L, },
    { claimant: "original-coordinator", generation: -1L, },
    { claimant: "x".repeat(257), generation: 1L, },
  ]
  for claim in invalid {
    assert_true(
      prepare_remote_effect_resume_delivery(
        report,
        resolution,
        claim,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  let bounded = { ..review_limits(), max_wire_bytes: 1, }
  assert_true(
    admit_remote_effect_resume_delivery_json(
      fixed, report, auth, reviewers, bounded,
    )
    is Err(InvalidDispatch),
  )
}
