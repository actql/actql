///|
test "managed advance bridge retains only the typed failed-result work cause" {
  assert_eq(
    local_managed_advance_control_work_limit(
      Err(@local_driver.ControlWorkLimit(100000)),
    ),
    Some(100000),
  )
  assert_eq(
    local_managed_advance_control_work_limit(
      Err(
        @local_driver.Execution(@strategy.Physical(@resources.ExecutionLimit)),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_control_work_limit(
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Rows(0, @execution.RowLimit)),
        ),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_control_work_limit(
      Ok({
        complete: false,
        waiting: false,
        settlement: None,
        progress: 1L,
        work: 1L,
      }),
    ),
    None,
  )
}

///|
test "managed resource bridge retains the original failed-result dimension" {
  assert_eq(
    local_managed_advance_resource_dimension(
      Err(
        @local_driver.Execution(@strategy.Physical(@resources.RetentionLimit)),
      ),
    ),
    Some("retained_bytes"),
  )
  assert_eq(
    local_managed_advance_resource_dimension(
      Err(@local_driver.Execution(@strategy.Physical(@resources.ForeignOwner))),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_resource_dimension(
      Ok({
        complete: false,
        waiting: false,
        settlement: None,
        progress: 1L,
        work: 1L,
      }),
    ),
    None,
  )
}

///|
test "managed advance Capture bridge keeps the SAME Result typed step and allowance only" {
  assert_eq(
    local_managed_advance_capture_work(
      Err(
        @local_driver.Configuration(
          @connector.Execution(
            @execution.Capture(41, @execution.CaptureWorkLimit(100000)),
          ),
        ),
      ),
    ),
    Some([41, 100000]),
  )
  assert_eq(
    local_managed_advance_capture_work(
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Capture(41, @execution.CaptureLimit)),
        ),
      ),
    ),
    None,
  )
  assert_eq(
    local_managed_advance_capture_work(
      Ok({
        complete: false,
        waiting: false,
        settlement: None,
        progress: 1L,
        work: 1L,
      }),
    ),
    None,
  )
}

///|
#cfg(target="js")
extern "js" fn original_budget_option_abi(
  value : (String, Bool, Int64, Int64, Int64)?,
  dimension : String,
  exact : Bool,
  requested : Int64,
  remaining : Int64,
  policy : Int64,
) -> Bool =
  #|(value, dimension, exact, requested, remaining, policy) =>
  #| value !== undefined && value !== null && typeof value === 'object' &&
  #| value._0 === dimension && value._1 === exact &&
  #| value._2 === requested && value._3 === remaining && value._4 === policy

///|
#cfg(target="js")
test "original budget bridge returns the actual compiler Option tuple unchanged to Node" {
  assert_true(
    original_budget_option_abi(
      local_managed_advance_budget(
        Err(
          @local_driver.ExecutionCapacityRefusal(
            @resources.RetentionLimit,
            19L,
            7L,
            512L,
          ),
        ),
      ),
      "retained_bytes",
      true,
      19L,
      7L,
      512L,
    ),
  )
  assert_true(
    original_budget_option_abi(
      local_managed_advance_budget(
        Err(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Capture(41, @execution.CaptureWorkRefusal(100, 7)),
            ),
          ),
        ),
      ),
      "value_capture_work",
      false,
      8L,
      7L,
      100L,
    ),
  )
  assert_true(
    local_managed_advance_budget(
      Err(@local_driver.Execution(@strategy.Stopped)),
    )
    is None,
  )
}
