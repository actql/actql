///|
test "empty public human Summary DATA does not change unsigned answer preimages" {
  let summary = answer_fixture_summary().replace(
    old="Independent fixture",
    new="",
  )
  let prepared = prepare_answer_fixture(summary).unwrap()
  // Independent corpus prepare-run constants, not expectations derived from
  // the previous constructor. Display text is absent from both signed bodies.
  assert_eq(
    answer_candidate_approval_preimage(prepared),
    Some(
      "sha256:c9e85bacb9f463bc44d5f72817045fa25343e4aa42ae2128f49003d5dd41cb80",
    ),
  )
  let resolution = prepare_answer_resolution(
    prepared,
    Some(
      "IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==",
    ),
  ).unwrap()
  assert_eq(
    answer_resolution_preimage(resolution),
    "sha256:5af4a3c2df6d91856ccc3b26ff2d1c1c80dc4af13e3f61146bb78a50e7799abe",
  )
  assert_true(
    prepare_answer_fixture(
      answer_fixture_summary().replace(
        old="\"Independent fixture\"",
        new="null",
      ),
    )
    is Err(InvalidField("humanSummary")),
  )
}
