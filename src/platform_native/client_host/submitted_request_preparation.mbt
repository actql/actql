///|
/// Original body borrow selected by the SAME Request checker/compiler. Neither
/// variant creates another preparation, body, permission or cleanup Owner.
pub enum NativeClientSubmittedRequestBody {
  Program(@resources.PreparationBodyBorrow[@host.PreparedClientProgram])
  Effect(
    @resources.PreparationBodyBorrow[@host.PreparedClientEffectComputation]
  )
}

///|
/// Return the original typed borrow, preserving the Resource result. This is
/// neither physical retirement nor permission to abort a live child.
pub fn return_native_client_submitted_request_body(
  body : NativeClientSubmittedRequestBody,
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  match body {
    Program(original) => @resources.return_preparation_body_borrow(original)
    Effect(original) => @resources.return_preparation_body_borrow(original)
  }
}

///|
/// Borrow only the SAME completed Request's original Plan input. Static
/// explanation and submitted execution share this existing typed custody;
/// this does not manufacture an intent, preparation identity or Run.
pub fn[I] borrow_native_client_request_plan_input(
  owner : @local.ClientRequestPreparation[I],
  input : I,
) -> Result[
  NativeClientSubmittedRequestBody,
  NativeClientSubmittedPreparationIssue,
] {
  match @local.request_prepared_computation_kind(owner, input) {
    Err(issue) => Err(RequestPreparation(issue))
    Ok(@local.Pure) =>
      @local.borrow_request_program_plan_input(owner, input)
      .map(value => Program(value))
      .map_err(issue => RequestPreparation(issue))
    Ok(@local.Effect) =>
      @local.borrow_request_effect_plan_input(owner, input)
      .map(value => Effect(value))
      .map_err(issue => RequestPreparation(issue))
  }
}

///|
/// Select the Model Plan phase of the same checked Request and retain its
/// borrow in the existing Native cleanup carrier.
pub fn[I] borrow_native_client_model_plan_input(
  owner : @local.ClientRequestPreparation[I],
  input : I,
) -> Result[
  NativeClientSubmittedRequestBody,
  @local.ClientRequestPreparationIssue,
] {
  @local.borrow_request_model_plan_input(owner, input).map(value => {
    Program(value)
  })
}

///|
/// Select the original terminal Content Plan input in the same Native request
/// cleanup carrier that retains the checker and Model Plan borrows.
pub fn[I] borrow_native_client_content_plan_input(
  owner : @local.ClientRequestPreparation[I],
  input : I,
) -> Result[
  NativeClientSubmittedRequestBody,
  @local.ClientRequestPreparationIssue,
] {
  @local.borrow_request_content_plan_input(owner, input).map(value => {
    Program(value)
  })
}

///|
/// The ordinary Native command's SAME intent and retained Request. The shared
/// source preflight funds original native decoding before this caller enters
/// it; the shared checker/compiler then consumes that original input once.
/// Failure leaves all Request/physical duties on the already retained parent.
pub fn prepare_native_client_submitted_request(
  owner : @local.ClientRequestPreparation[@host.ClientSubmittedIntent],
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Result[
  (NativeClientSubmittedPreparation, NativeClientSubmittedRequestBody),
  NativeClientSubmittedPreparationIssue,
] {
  prepare_native_client_submitted_request_input(
    owner, intent, intent, environment, publication,
  )
}

///|
/// SAME original producer input, selected and backed before its file/intent
/// constructor. The existing typed intent remains actual input DATA; this
/// overload changes no issuer, permission, checker/compiler or cleanup owner.
pub fn[I] prepare_native_client_submitted_request_input(
  owner : @local.ClientRequestPreparation[I],
  input : I,
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  verify_request_value_policy? : ((String) -> String?)? = None,
  before_program_borrow? : (() -> Result[
    Unit,
    NativeClientSubmittedPreparationIssue,
  ])? = None,
) -> Result[
  (NativeClientSubmittedPreparation, NativeClientSubmittedRequestBody),
  NativeClientSubmittedPreparationIssue,
] {
  match
    check_native_client_submitted_request_input(
      owner,
      input,
      intent,
      environment,
      publication,
      verify_request_value_policy~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let kind = match
    @local.finish_request_checked_computation(
      owner, input, environment, publication,
    ) {
    Err(issue) => return Err(Request(issue))
    Ok(value) => value
  }
  // Common already compiled and continued to the selected body capacity.
  // Do not check, compile or continue it a second time at this Native handoff.
  match kind {
    @local.Pure => {
      // Finish the caller's same-Request constructor before retaining the
      // original Plan input. The callback receives no replacement authority.
      if before_program_borrow is Some(prepare) {
        match prepare() {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
      let borrow = match
        @local.borrow_request_program_plan_input(owner, input) {
        Err(issue) => return Err(RequestPreparation(issue))
        Ok(value) => value
      }
      let original = @resources.preparation_body_borrow_value(borrow).unwrap()
      Ok(
        (
          {
            intent_cid: @host.client_submitted_intent_cid(intent),
            preparation: Computation(original),
            lowered_effect_query: false,
          },
          Program(borrow),
        ),
      )
    }
    @local.Effect => {
      let borrow = match @local.borrow_request_effect_plan_input(owner, input) {
        Err(issue) => return Err(RequestPreparation(issue))
        Ok(value) => value
      }
      let original = @resources.preparation_body_borrow_value(borrow).unwrap()
      let lowered_effect_query = @local.prepared_request_query_lowering(
          owner, input,
        )
        is Ok((lowered, _, _)) &&
        lowered.program is Some(program) &&
        physical_equal(
          program,
          @host.prepared_client_effect_computation_source(original),
        )
      Ok(
        (
          {
            intent_cid: @host.client_submitted_intent_cid(intent),
            preparation: EffectComputation(original),
            lowered_effect_query,
          },
          Effect(borrow),
        ),
      )
    }
  }
}

///|
/// Same original Request intake and semantic checker, before compilation or
/// eventual body selection. Static check/explain callers keep this parent and
/// its original outcome; neither a second parser nor a Run is issued here.
pub fn[I] check_native_client_submitted_request_input(
  owner : @local.ClientRequestPreparation[I],
  input : I,
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  verify_request_value_policy? : ((String) -> String?)? = None,
) -> Result[Unit, NativeClientSubmittedPreparationIssue] {
  let program_limits = match
    @local.check_request_retained_submitted_intent(
      owner,
      input,
      intent,
      environment,
      publication,
      public_primary=false,
    ) {
    Ok(limits) => limits
    Err(InvalidInput) => return Err(InvalidSubmittedInput)
    Err(Preparation(issue)) => return Err(RequestPreparation(issue))
    Err(Request(issue)) => return Err(Request(issue))
  }
  if verify_request_value_policy is Some(verify) {
    // The original semantic check is complete; no compiler has run yet.
    // Retain the same funded subject inventory through every Host callback.
    // An explicit decline still consumes its own original index. Core's
    // binder observes reentry/currentness before admitting that exact answer.
    let count = match
      @local.prepare_request_computation_policy_subjects(
        owner,
        input,
        environment,
        program_limits.checking.compilation,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Request(issue))
    }
    for index in 0..<count {
      let subject = match
        @local.request_computation_policy_subject(
          owner, input, environment, index,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Request(issue))
      }
      let policy = verify(subject)
      match
        @local.bind_request_computation_policy_subject(
          owner, input, environment, index, policy,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Request(issue))
      }
    }
    match
      @local.finish_request_computation_policy_subjects(
        owner, input, environment,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Request(issue))
    }
  }
  Ok(())
}
