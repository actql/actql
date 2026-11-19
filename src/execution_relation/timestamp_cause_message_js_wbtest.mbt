///|
#cfg(target="js")
extern "js" fn imported_timestamp_cause_message(
  cause : String?,
  rejected : String,
  describe : (String) -> String?,
) -> Bool =
  #|(cause, rejected, describe) => {
  #| const require=process.getBuiltinModule('module').createRequire(process.cwd()+'/package.json');
  #| const {runtimeCore}=require('./adapters/host-common/runtime-core.mjs');
  #| const {publicBudgetFailureMessage,retainedBudgetFailureMessage}=require('./adapters/host-node/client-dispatch-diagnostic.mjs');
  #| if(cause!=='evaluation.timestamp_canonical_required') return false;
  #| let reads=0;
  #| const moon={strategyRemoteManagedOutputEvidenceKind:()=> 'unused',strategyModule_local_ManagedFailureExplanation(code){
  #|   if(this!==moon) throw Error('foreign receiver');reads++;return describe(code);
  #| }};
  #| const control=runtimeCore(moon).publicationControl;
  #| moon.strategyModule_local_ManagedFailureExplanation=()=>{throw Error('replaced export');};
  #| const before=reads;
  #| const generic=Object.assign(new Error(cause),{cause:{code:cause}});
  #| if(publicBudgetFailureMessage(generic,control.executionFailureExplanation)!==undefined || reads!==before) return false;
  #| // Explicit typed-diagnostic DTO port; the cause itself came from the
  #| // original Core CAST below, not JS exception-text classification.
  #| const error=Object.assign(new Error('MoonBitHostFailure'),{code:'MoonBitHostFailure'});
  #| Object.defineProperty(error,'primaryDiagnostic',{value:Object.freeze({code:'MoonBitHostFailure',
  #|   phase:'local_managed_advance',kind:'row_failure',task:2147483647,step:2147483647,cause})});
  #| const message=publicBudgetFailureMessage(error,control.executionFailureExplanation);
  #| const description=control.executionFailureExplanation(cause);
  #| if(typeof message!=='string' || message.length>512 || !message.endsWith(' '+description) ||
  #|   !message.includes('2026-01-02T03:04:05.123Z') || !message.includes('3-9 fractional digits') ||
  #|   message.includes(rejected)) return false;
  #| const bare=publicBudgetFailureMessage(error);
  #| if(publicBudgetFailureMessage(error,()=> 'x'.repeat(1000))!==bare ||
  #|   publicBudgetFailureMessage(error,()=>{throw Error('foreign renderer');})!==bare) return false;
  #| const stop={physical_stop:'confirmed',revision:3};
  #| const state={run_id:'catalog-component',status:'failed',result_available:false,next_action:{kind:'none'},
  #|   terminal_error:{code:'ACTQL_E_UNPUBLISHED_RUN',message},control:stop};
  #| const key=JSON.stringify(state);
  #| if(retainedBudgetFailureMessage(key,state,'catalog-component',stop,control.executionFailureExplanation)!==message ||
  #|   retainedBudgetFailureMessage(key,state,'foreign',stop,control.executionFailureExplanation)!==undefined ||
  #|   retainedBudgetFailureMessage(key,state,'catalog-component',{...stop,physical_stop:'unknown'},control.executionFailureExplanation)!==undefined ||
  #|   retainedBudgetFailureMessage(key,state,'catalog-component',stop)!==undefined) return false;
  #| const tampered={...state,terminal_error:{...state.terminal_error,message:message.replace('Expected','Unexpected')}};
  #| if(retainedBudgetFailureMessage(JSON.stringify(tampered),tampered,'catalog-component',stop,control.executionFailureExplanation)!==undefined) return false;
  #| const old={...state,terminal_error:{...state.terminal_error,message:bare}};
  #| return retainedBudgetFailureMessage(JSON.stringify(old),old,'catalog-component',stop,control.executionFailureExplanation)===bare &&
  #|   control.executionFailureExplanation('evaluation.invalid_operand')===undefined;
  #| }

///|
#cfg(target="js")
test "original canonical CAST cause reaches Common catalogue and imported public cold message projection" {
  for rejected in ["2026-01-02T03:04:05Z", "2026-01-02 03:04:05+00"] {
    let original = lowered("\"CAST('" + rejected + "' AS TIMESTAMP)\"")
    guard evaluate_expression(original, {}, [], {
        remaining: 10000,
        max_frames: 100,
      })
      is Err(issue) else {
      fail("noncanonical original CAST accepted")
    }
    assert_true(physical_equal(issue.expression, original))
    assert_true(
      imported_timestamp_cause_message(
        row_failure_diagnostic_cause(Evaluation(0, 0, issue)),
        rejected,
        row_failure_diagnostic_explanation,
      ),
    )
  }
}
