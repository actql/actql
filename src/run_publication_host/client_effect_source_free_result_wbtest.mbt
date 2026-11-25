///|
test "Source-free Effect Result accepts only the canonical empty acquisition scope" {
  let empty = @publication.seal_publication_contract(
    "acquisition_scope", source_free_effect_result_scope_body, 4096, 64, 8,
  ).unwrap()
  let nonempty = @publication.issue_single_source_acquisition_scope(
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    4096,
    64,
    8,
  ).unwrap()
  assert_true(source_free_effect_result_scope_matches(empty))
  assert_false(source_free_effect_result_scope_matches(nonempty))
}
