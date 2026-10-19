///|
// These fixtures exercise CLI exit projection only, not Check admission or
// Program validity. Actual portable Check outputs are asserted separately.
fn check_exit_projection_fixture(
  verdict : String,
  runnable : String,
) -> String raise ClientStop {
  let (reason, outcome) = @preparation.client_program_check_reporting_schema_cids()
  encode_request_json(
    Json::object(
      Map([
        ("version", Json::string("actql-check-outcome/0.1")),
        ("reason_schema_cid", Json::string(reason)),
        ("outcome_schema_cid", Json::string(outcome)),
        ("outcome", Json::string("completed")),
        (
          "report",
          Json::object(
            Map([
              ("verdict", Json::string(verdict)),
              (
                "runnable",
                Json::object(Map([("verdict", Json::string(runnable))])),
              ),
              ("message", Json::string("invalid is text, not the verdict")),
            ]),
          ),
        ),
      ]),
    ),
    65536,
  )
}

///|
test "Check exit follows only the original invalid verdict" {
  assert_true(
    local_check_invalid_exit(check_exit_projection_fixture("invalid", "no")),
  )
  assert_false(
    local_check_invalid_exit(check_exit_projection_fixture("verified", "yes")),
  )
  assert_false(
    local_check_invalid_exit(check_exit_projection_fixture("verified", "no")),
  )
  assert_false(
    local_check_invalid_exit(
      check_exit_projection_fixture("undetermined", "no"),
    ),
  )
}

///|
test "Check exit refuses a foreign outcome without treating arbitrary state as a check" {
  let refused = try {
    ignore(
      local_check_invalid_exit(
        "{\"version\":\"actql-run-state/0.1\",\"status\":\"failed\"}",
      ),
    )
    false
  } catch {
    ClientStop(message) => message == "LocalCheckOutcomeUnavailable"
  }
  assert_true(refused)
}
