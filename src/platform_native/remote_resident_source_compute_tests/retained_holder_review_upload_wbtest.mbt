///|
/// Physical HTTPS upload of this original holder's confirmed review. The test
/// server acknowledges artifact transport only; it is not a Cloud Run Owner.
fn retained_holder_upload_original_review(
  work : @effect_provider.NativeResidentEffectReview,
) -> Unit raise {
  let required = name => @env.get_env_var(name).unwrap()
  let http = @http.load_library(required("ACTQL_TEST_NATIVE_HTTP_LIBRARY")).unwrap()
  let client = http
    .create_authenticated_client(
      required("ACTQL_TEST_NATIVE_HTTP_CA"),
      Bearer(required("ACTQL_TEST_NATIVE_HTTP_SECRET")),
      262144L,
      2000,
      5000,
    )
    .unwrap()
  let url = required("ACTQL_TEST_EFFECT_REVIEW_UPLOAD_FIXTURE_URL")
  let (before_report, before_wire) = work
    .review_projection(() => true, 65536)
    .unwrap()
  assert_true(
    work.upload_review_projection(client, url, () => false) is Err(Review(_)),
  )
  assert_true(
    work.upload_review_projection(client, url, () => true)
    is Err(HttpStatus(503)),
  )
  let reads = Ref(0)
  assert_true(
    work.upload_review_projection(client, url, () => {
      reads.val += 1
      reads.val < 3
    })
    is Err(Review(_)),
  )
  assert_eq(reads.val, 3)
  work.upload_review_projection(client, url, () => true).unwrap()
  let (after_report, after_wire) = work
    .review_projection(() => true, 65536)
    .unwrap()
  assert_eq(after_wire, before_wire)
  assert_eq(
    @remote.remote_effect_checkpoint_report_identity(after_report),
    @remote.remote_effect_checkpoint_report_identity(before_report),
  )
  assert_true(client.close())
}
