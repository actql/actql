///|
#cfg(target="js")
extern "js" fn original_unit_finalization_node_diagnostic(
  original : Result[Unit, @local_driver.LocalDispatchIssue],
  completed : Result[
    @execution.ManagedCompletedOutput[Int],
    @local_driver.LocalDispatchIssue,
  ],
  carrier : Result[
    @execution.CarrierManagedCompletedOutput,
    @local_driver.LocalDispatchIssue,
  ],
  success : Result[String, @local_driver.LocalDispatchIssue],
  foreign : Result[Unit, @resources.LedgerIssue],
  resource : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> String?,
  budget : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> (String, Bool, Int64, Int64, Int64)?,
  control : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> Int?,
  capture : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> Array[Int]?,
  cause : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> String?,
  step : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> Int,
) -> Bool =
  #|(original, completed, carrier, success, foreign, resource, budget, control, capture, cause, step) => {
  #|  const require = process.getBuiltinModule('module').createRequire(process.cwd() + '/package.json');
  #|  const {checkedLocalManagedAdvance} = require('./adapters/local-node/managed-advance-diagnostic.mjs');
  #|  const {checked} = require('./adapters/host-common/runtime-result.mjs');
  #|  const {publicBudgetFailureMessage} = require('./adapters/host-node/client-dispatch-diagnostic.mjs');
  #|  for (const result of [original, completed, carrier]) {
  #|    let primary;
  #|    const moon = {
  #|      strategyModule_local_ManagedAdvanceResourceDimension(value) {
  #|        if (value !== result) throw new Error('ForeignOriginalResult');
  #|        return resource(value);
  #|      },
  #|      strategyModule_local_ManagedAdvanceBudget: budget,
  #|    };
  #|    try {
  #|      checkedLocalManagedAdvance(moon, result, value => {
  #|        try { return checked(value); } catch (error) { primary = error; throw error; }
  #|      }, 7);
  #|      return false;
  #|    } catch (error) {
  #|      if (!(error === primary && error.code === 'MoonBitHostFailure' &&
  #|        error.primaryDiagnostic?.task === 7 && error.primaryDiagnostic?.dimension === 'execution_bytes' &&
  #|        publicBudgetFailureMessage(error).includes('requested_delta=unavailable; remaining=unavailable; policy=unavailable; unit=logical_bytes; setting=installation.requestMemory.executionBytes'))) return false;
  #|    }
  #|  }
  #|  try {
  #|    checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceResourceDimension: resource,
  #|      strategyModule_local_ManagedAdvanceBudget: budget,
  #|      strategyModule_local_ManagedAdvanceControlWorkLimit: control,
  #|      strategyModule_local_ManagedAdvanceCaptureWork: capture,
  #|      strategyModule_local_ManagedAdvanceCause: cause,
  #|      strategyModule_local_ManagedAdvanceRowStep: step}, foreign, checked, 7);
  #|    return false;
  #|  } catch (error) {
  #|    if (error.code !== 'MoonBitHostFailure' || error.primaryDiagnostic !== undefined) return false;
  #|  }
  #|  return checkedLocalManagedAdvance({strategyModule_local_ManagedAdvanceResourceDimension() {
  #|    throw new Error('SuccessCannotProjectFailure');
  #|  }}, success, checked, 7) === 'original';
  #|}

///|
#cfg(target="js")
test "original typed Unit finalization Result reaches the imported Node diagnostic unchanged" {
  let original : Result[Unit, @local_driver.LocalDispatchIssue] = Err(
    @local_driver.Execution(@strategy.Physical(@resources.ExecutionLimit)),
  )
  assert_true(
    original_unit_finalization_node_diagnostic(
      original,
      Err(
        @local_driver.Execution(@strategy.Physical(@resources.ExecutionLimit)),
      ),
      Err(
        @local_driver.Execution(@strategy.Physical(@resources.ExecutionLimit)),
      ),
      Ok("original"),
      Err(@resources.ForeignOwner),
      local_managed_advance_resource_dimension,
      local_managed_advance_budget,
      local_managed_advance_control_work_limit,
      local_managed_advance_capture_work,
      local_managed_advance_cause,
      local_managed_advance_row_step,
    ),
  )
}

///|
#cfg(target="js")
extern "js" fn original_row_failure_option_abi(
  value : String?,
  step : Int,
) -> Bool =
  #|(value, step) => value === 'rows.row_limit' && step === 42

///|
#cfg(target="js")
test "original row failure bridge returns the actual compiler closed cause and step unchanged" {
  let original = Err(
    @local_driver.Configuration(
      @connector.Execution(@execution.Rows(42, @execution.RowLimit)),
    ),
  )
  assert_true(
    original_row_failure_option_abi(
      local_managed_advance_cause(original),
      local_managed_advance_row_step(original),
    ),
  )
  let yielded : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ] = Ok({
    complete: false,
    waiting: false,
    settlement: None,
    progress: 1L,
    work: 1L,
  })
  assert_eq(local_managed_advance_cause(yielded), None)
  assert_eq(local_managed_advance_row_step(yielded), -1)
}

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

///|
#cfg(target="js")
extern "js" fn original_nonrow_failure_node_diagnostic(
  original : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ],
  cause : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> String?,
  step : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> Int,
) -> Bool =
  #|(original, cause, step) => {
  #|  const require = process.getBuiltinModule('module').createRequire(process.cwd() + '/package.json');
  #|  const {checkedLocalManagedAdvance} = require('./adapters/local-node/managed-advance-diagnostic.mjs');
  #|  const {checked} = require('./adapters/host-common/runtime-result.mjs');
  #|  const {dispatchFailureSnapshot, publicBudgetFailureMessage, retainedBudgetFailureMessage} = require('./adapters/host-node/client-dispatch-diagnostic.mjs');
  #|  let primary, reads = 0;
  #|  const moon = {strategyModule_local_ManagedAdvanceCause(value) {
  #|    if (this !== moon || value !== original) throw new Error('ForeignOriginal');
  #|    reads++; return cause(value);
  #|  }, strategyModule_local_ManagedAdvanceRowStep: step};
  #|  try { checkedLocalManagedAdvance(moon, original, value => {
  #|    try { return checked(value); } catch (error) { primary = error; throw error; }
  #|  }, 42); return false; } catch (error) {
  #|    const expected = 'Execution failed: phase=local_managed_advance; task=42; cause=capture.capture_limit. Original execution failure; resource quantities were not retained.';
  #|    if (error !== primary || reads !== 1 || error.primaryDiagnostic?.kind !== 'local_issue' ||
  #|        error.primaryDiagnostic?.cause !== 'capture.capture_limit' || Object.hasOwn(error.primaryDiagnostic, 'step') ||
  #|        publicBudgetFailureMessage(error) !== expected || dispatchFailureSnapshot({primaryFailure:error}).primaryDiagnostic?.cause !== 'capture.capture_limit') return false;
  #|    const control = {physical_stop:'confirmed',revision:1};
  #|    const state = {run_id:'original-fixture',status:'failed',result_available:false,next_action:{kind:'none'},
  #|      terminal_error:{code:'ACTQL_E_UNPUBLISHED_RUN',message:expected},control};
  #|    return retainedBudgetFailureMessage(JSON.stringify(state),state,'original-fixture',control) === expected &&
  #|      retainedBudgetFailureMessage(JSON.stringify(state),state,'foreign',control) === undefined &&
  #|      retainedBudgetFailureMessage(JSON.stringify(state),state,'original-fixture',{...control,physical_stop:'unknown'}) === undefined;
  #|  }
  #|}

///|
#cfg(target="js")
test "original nonrow cause ABI reaches imported Node and same failed Journal renderer without a fabricated row step" {
  assert_true(
    original_nonrow_failure_node_diagnostic(
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Capture(42, @execution.CaptureLimit)),
        ),
      ),
      local_managed_advance_cause,
      local_managed_advance_row_step,
    ),
  )
}

///|
#cfg(target="js")
extern "js" fn original_remaining_row_cause_node_abi(
  original : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ],
  cause : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> String?,
  step : (
    Result[@local_driver.LocalManagedAdvance, @local_driver.LocalDispatchIssue],
  ) -> Int,
  expected : String,
) -> Bool =
  #|(original, cause, step, expected) => {
  #|  const require = process.getBuiltinModule('module').createRequire(process.cwd() + '/package.json');
  #|  const {checkedLocalManagedAdvance} = require('./adapters/local-node/managed-advance-diagnostic.mjs');
  #|  const {checked} = require('./adapters/host-common/runtime-result.mjs');
  #|  const {dispatchFailureSnapshot,publicBudgetFailureMessage} = require('./adapters/host-node/client-dispatch-diagnostic.mjs');
  #|  let primary, calls = 0;
  #|  const moon = {strategyModule_local_ManagedAdvanceCause(value) {
  #|    if (this !== moon || value !== original) throw new Error('ForeignOriginalResult');
  #|    calls++; return cause(value);
  #|  }, strategyModule_local_ManagedAdvanceRowStep:step};
  #|  try { checkedLocalManagedAdvance(moon,original,value => {
  #|    try { return checked(value); } catch(error) {primary=error;throw error;}
  #|  },43);return false; } catch(error) {
  #|    const data=dispatchFailureSnapshot(error)?.primaryDiagnostic;
  #|    return error===primary && calls===1 && data?.kind==='row_failure' && data?.task===43 && data?.step===43 &&
  #|      data?.cause===expected && !Object.hasOwn(data,'dimension') && !Object.hasOwn(data,'budget') &&
  #|      publicBudgetFailureMessage(error)===`Execution failed: phase=local_managed_advance; task=43; step=43; cause=${expected}. Original execution failure; resource quantities were not retained.`;
  #|  }
  #|}

///|
#cfg(target="js")
test "remaining original typed row causes reach the actual imported Node ABI with the same original failure and step" {
  for
    (issue, expected) in [
      (
        @execution.LogicalRows(@execution.LiveValueLimit),
        "logical.live_value_limit",
      ),
      (@execution.LogicalRows(@execution.WorkLimit), "logical.work_limit"),
      (@execution.OwnerMismatch, "rows.owner_mismatch"),
      (
        @execution.MissingOrderedResourceContext,
        "rows.missing_ordered_resource_context",
      ),
      (
        @execution.AnalyticEnvelope(@execution.Measurement),
        "analytic.measurement",
      ),
    ] {
    assert_true(
      original_remaining_row_cause_node_abi(
        Err(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(43, issue)),
          ),
        ),
        local_managed_advance_cause,
        local_managed_advance_row_step,
        expected,
      ),
    )
  }
}
