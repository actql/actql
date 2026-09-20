///|
test "Result access progression owns the authorized delivery order" {
  let progress = begin_result_access_progress()
  assert_eq(
    result_access_progress_action(progress),
    ResultAccessAuthorizeRequest,
  )
  record_result_access_request_authorization(progress, true).unwrap()
  assert_eq(
    result_access_progress_action(progress),
    ResultAccessResolveCommittedResult,
  )
  record_result_access_resolution(progress, true).unwrap()
  assert_eq(
    result_access_progress_action(progress),
    ResultAccessCheckInitialAvailability,
  )
  record_result_access_initial_availability(progress, true).unwrap()
  assert_eq(result_access_progress_action(progress), ResultAccessAdmitRead)
  record_result_access_read_admission(progress, true).unwrap()
  assert_eq(result_access_progress_action(progress), ResultAccessIssueGrant)
  record_result_access_grant(progress, true).unwrap()
  assert_eq(result_access_progress_action(progress), ResultAccessStartDelivery)
}

///|
test "Result access rejection is terminal at every protected boundary" {
  let authorization = begin_result_access_progress()
  record_result_access_request_authorization(authorization, false).unwrap()
  assert_eq(result_access_progress_action(authorization), ResultAccessReject)
  assert_true(
    record_result_access_request_authorization(authorization, true)
    is Err(ResultAccessInvalidState),
  )

  let resolution = begin_result_access_progress()
  record_result_access_request_authorization(resolution, true).unwrap()
  record_result_access_resolution(resolution, false).unwrap()
  assert_eq(result_access_progress_action(resolution), ResultAccessReject)

  let availability = begin_result_access_progress()
  record_result_access_request_authorization(availability, true).unwrap()
  record_result_access_resolution(availability, true).unwrap()
  record_result_access_initial_availability(availability, false).unwrap()
  assert_eq(result_access_progress_action(availability), ResultAccessReject)

  let admission = begin_result_access_progress()
  record_result_access_request_authorization(admission, true).unwrap()
  record_result_access_resolution(admission, true).unwrap()
  record_result_access_initial_availability(admission, true).unwrap()
  record_result_access_read_admission(admission, false).unwrap()
  assert_eq(result_access_progress_action(admission), ResultAccessReject)

  let grant = begin_result_access_progress()
  record_result_access_request_authorization(grant, true).unwrap()
  record_result_access_resolution(grant, true).unwrap()
  record_result_access_initial_availability(grant, true).unwrap()
  record_result_access_read_admission(grant, true).unwrap()
  record_result_access_grant(grant, false).unwrap()
  assert_eq(result_access_progress_action(grant), ResultAccessReject)
}
