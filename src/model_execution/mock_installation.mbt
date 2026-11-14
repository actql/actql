///|
pub(all) enum ModelMockInstallationIssue {
  ForeignOriginal
  Retired
  Busy
  MissingAnswer
  Answers(ModelMockAnswerIssue)
} derive(Eq, Debug)

///|
/// The existing Model owner retains the actual declaration, checked Environment
/// Task and every typed answer. This is a local fixture implementation, not a
/// remote Provider, key, grant or resource supplier. Execution still consumes
/// the original Host call scope, dispatch and startup custody.
struct ModelMockInstallation {
  mut original : ModelMockInstallation?
  mut profile : @environment.ModelMockProfile?
  mut declaration : @environment.PublicModelTaskDeclaration?
  mut normalized : @environment.NormalizedPublicModelTask?
  mut task : @environment.ModelTaskContract?
  mut answers : ModelMockAnswers?
  mut provider : ModelProvider?
  mut closing : Bool
  mut users : Int
  mut now : (() -> String)?
}

///|
pub fn install_original_model_mock(
  profile : @environment.ModelMockProfile,
  declaration : @environment.PublicModelTaskDeclaration,
  normalized : @environment.NormalizedPublicModelTask,
  answers : ModelMockAnswers,
  now : () -> String,
) -> Result[ModelMockInstallation, ModelMockInstallationIssue] {
  if !@environment.normalized_public_mock_model_task_original_for(
      normalized, declaration, profile,
    ) {
    return Err(ForeignOriginal)
  }
  match answers.require_original(declaration) {
    Err(issue) => return Err(Answers(issue))
    Ok(_) => ()
  }
  Ok(
    make_original_model_mock(
      profile,
      declaration,
      normalized,
      Some(answers),
      now,
    ),
  )
}

///|
/// Prepare the SAME immutable Task/provider declaration without reading answer
/// DATA. This grants no call, Scope, dispatch, resource or answer availability.
pub fn prepare_original_model_mock(
  profile : @environment.ModelMockProfile,
  declaration : @environment.PublicModelTaskDeclaration,
  normalized : @environment.NormalizedPublicModelTask,
  now : () -> String,
) -> Result[ModelMockInstallation, ModelMockInstallationIssue] {
  if !@environment.normalized_public_mock_model_task_original_for(
      normalized, declaration, profile,
    ) {
    return Err(ForeignOriginal)
  }
  Ok(make_original_model_mock(profile, declaration, normalized, None, now))
}

///|
// One original owner and provider shape for both eager callers and a declared
// local input whose physical answer DATA is not needed until Model dispatch.
fn make_original_model_mock(
  profile : @environment.ModelMockProfile,
  declaration : @environment.PublicModelTaskDeclaration,
  normalized : @environment.NormalizedPublicModelTask,
  answers : ModelMockAnswers?,
  now : () -> String,
) -> ModelMockInstallation {
  let original : ModelMockInstallation = {
    original: None,
    profile: Some(profile),
    declaration: Some(declaration),
    normalized: Some(normalized),
    task: None,
    answers,
    provider: None,
    closing: false,
    users: 0,
    now: Some(now),
  }
  original.original = Some(original)
  original.provider = Some({
    invocation: OriginalMock(original),
    provider_id: "mock",
  })
  original
}

///|
fn ModelMockInstallation::require_declaration(
  self : Self,
) -> Result[Unit, ModelMockInstallationIssue] {
  guard self.original is Some(original) &&
    self.profile is Some(profile) &&
    self.declaration is Some(declaration) &&
    self.normalized is Some(normalized) &&
    self.now is Some(_) else {
    return Err(Retired)
  }
  if !physical_equal(original, self) ||
    !@environment.normalized_public_mock_model_task_original_for(
      normalized, declaration, profile,
    ) {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
fn ModelMockInstallation::require_original(
  self : Self,
) -> Result[Unit, ModelMockInstallationIssue] {
  match self.require_declaration() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.answers is Some(answers) else { return Err(MissingAnswer) }
  answers
  .require_original(self.declaration.unwrap())
  .map_err(issue => Answers(issue))
}

///|
// A prepared provider declaration can precede physical answer intake. Once
// answers are bound, retain their complete original/current checks unchanged.
fn ModelMockInstallation::require_provider_original(
  self : Self,
) -> Result[Unit, ModelMockInstallationIssue] {
  match self.answers {
    Some(_) => self.require_original()
    None => self.require_declaration()
  }
}

///|
/// Metadata-only getter from the same live original declaration. It supplies
/// neither an answer, call admission nor a replacement currentness verdict.
pub fn original_model_mock_declaration(
  original : ModelMockInstallation,
) -> Result[@environment.NormalizedPublicModelTask, ModelMockInstallationIssue] {
  match original.require_provider_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if original.closing {
    Err(Retired)
  } else {
    Ok(original.normalized.unwrap())
  }
}

///|
/// Complete only this declared original during its live Model preparation.
/// The caller retains its physical read/close and resource duties separately.
pub fn bind_original_model_mock_answers(
  original : ModelMockInstallation,
  answers : ModelMockAnswers,
) -> Result[Unit, ModelMockInstallationIssue] {
  match original.require_declaration() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if original.closing {
    return Err(Retired)
  }
  if original.answers is Some(retained) {
    if !physical_equal(retained, answers) {
      return Err(ForeignOriginal)
    }
    return original.require_original()
  }
  match answers.require_original(original.declaration.unwrap()) {
    Err(issue) => return Err(Answers(issue))
    Ok(_) => ()
  }
  original.answers = Some(answers)
  Ok(())
}

///|
pub fn original_model_mock_provider(
  original : ModelMockInstallation,
) -> Result[ModelProvider, ModelMockInstallationIssue] {
  match original.require_provider_original() {
    Err(issue) => Err(issue)
    Ok(_) =>
      if original.closing {
        Err(Retired)
      } else {
        Ok(original.provider.unwrap())
      }
  }
}

///|
/// Only this live installation can select the no-transport dependency purpose.
/// The returned DATA remains tied to the same execution and checked Task;
/// this supplies no physical attachment, permission or resource reservation.
pub fn read_original_model_mock_dependencies(
  original : ModelMockInstallation,
  execution : @environment.ModelExecutionContract,
  prompt : Bytes?,
  retry : Bytes?,
  backoff : Bytes?,
  limits : @environment.Limits,
  max_work : Int,
) -> Result[
  @environment.SingleAttemptModelDependencies,
  @environment.ModelDependencyIssue,
] {
  if original.closing ||
    original.require_provider_original() is Err(_) ||
    !original_mock_provider_matches(
      original,
      original.provider.unwrap(),
      @environment.model_execution_task(execution),
    ) {
    return Err(
      @environment.Body(@environment.ModelPrompt, {
        kind: @environment.ReferenceMismatch,
        source: None,
      }),
    )
  }
  @environment.read_original_mock_model_dependencies(
    original.profile.unwrap(),
    original.normalized.unwrap(),
    execution,
    prompt,
    retry,
    backoff,
    limits,
    max_work,
  )
}

///|
fn original_mock_provider_matches(
  original : ModelMockInstallation,
  provider : ModelProvider,
  task : @environment.ModelTaskContract,
) -> Bool {
  !original.closing &&
  original.require_provider_original() is Ok(_) &&
  original.provider is Some(retained) &&
  physical_equal(provider, retained) &&
  (match original.task {
    Some(retained_task) => physical_equal(task, retained_task)
    None =>
      @environment.normalized_public_mock_model_task_matches_task(
        original.normalized.unwrap(),
        original.declaration.unwrap(),
        original.profile.unwrap(),
        task,
      )
  })
}

///|
// This installed typed-answer purpose consumes opaque, checked input values.
// Its same live original and Task remain mandatory; no media bytes or egress
// are supplied by carrying a ContentRef through the bounded request encoder.
fn original_mock_accepts_opaque_references(
  provider : ModelProvider,
  task : @environment.ModelTaskContract,
) -> Bool {
  match provider.invocation {
    OriginalMock(original) =>
      original_mock_provider_matches(original, provider, task)
    SynchronousFixture(_) | AsynchronousPhysical => false
  }
}

///|
fn original_mock_scope_matches(
  original : ModelMockInstallation,
  scope : @publication.BoundModelInvocationScope,
) -> Bool {
  if original.require_provider_original() is Err(_) {
    return false
  }
  guard @environment.model_mock_profile_originals(original.profile.unwrap())
    is Some(originals) else {
    return false
  }
  let boundary = @publication.model_invocation_scope_boundary(scope)
  boundary.connection == "mock" &&
  boundary.installation_revision_cid == originals.1 &&
  boundary.configuration_contract_cid == originals.3 &&
  boundary.provider_configuration_cid == originals.5
}

///|
/// Closing prevents new calls immediately. The original execution retains its
/// aliases until existing Model cleanup releases them; this DATA retirement
/// never stands for a physical ACK or reservation settlement.
pub fn retire_original_model_mock(
  original : ModelMockInstallation,
) -> Result[Bool, ModelMockInstallationIssue] {
  guard original.original is Some(retained) else { return Err(Retired) }
  if !physical_equal(original, retained) {
    return Err(ForeignOriginal)
  }
  original.closing = true
  if original.users != 0 {
    return Ok(false)
  }
  original.now = None
  original.provider = None
  original.task = None
  original.answers = None
  original.normalized = None
  original.declaration = None
  original.profile = None
  original.original = None
  Ok(true)
}

///|
/// DATA selection only, called after original request/key admission below.
/// An object property names exactly one Text component. Default is explicit
/// and applies equally to valid non-Text and composite keys without conversion.
fn select_mock_answer(
  answers : ModelMockAnswers,
  declaration : @environment.PublicModelTaskDeclaration,
  key : Array[@admitted.CheckedValue],
) -> Result[@admitted.CheckedValue, ModelMockInstallationIssue] {
  match answers.require_original(declaration) {
    Err(issue) => return Err(Answers(issue))
    Ok(_) => ()
  }
  if key.length() == 1 && key[0].value is @admitted.Text(label) {
    for (name, value) in answers.entries {
      if label == name {
        return Ok(value)
      }
    }
  }
  match answers.fallback {
    Some(value) => Ok(value)
    None => Err(MissingAnswer)
  }
}

///|
fn original_mock_request_values_current(
  state : ModelState,
  request : ModelRequest,
) -> Bool {
  let infer = @relation.prepared_infer_rows_owner(state.rows)
  if request.key.length() != @infer.key_count(infer) ||
    request.inputs.length() != @infer.input_binding_count(infer) {
    return false
  }
  for index in 0..<request.key.length() {
    guard @relation.prepared_infer_rows_key(state.rows, request.slot, index)
      is Some(value) &&
      physical_equal(value, request.key[index]) else {
      return false
    }
  }
  for index in 0..<request.inputs.length() {
    guard @relation.prepared_infer_rows_value(state.rows, request.slot, index)
      is Some(value) &&
      @infer.input_binding_at(infer, index) is Some(binding) &&
      physical_equal(value, request.inputs[index].1) &&
      @infer.input_binding_role(binding) == request.inputs[index].0 else {
      return false
    }
  }
  true
}

///|
fn invoke_original_mock(
  original : ModelMockInstallation,
  provider : ModelProvider,
  state : ModelState,
  prepared : PreparedModelRequest,
  request : ModelRequest,
  reader : @bounded.Reader,
) -> Result[ModelResponse, ModelProviderFailure] {
  if original.require_original() is Err(_) ||
    !original_mock_provider_matches(original, provider, state.task) ||
    original.users <= 0 ||
    state.dispatch_admission is None ||
    !(state.prepared_call_set is Some(calls) &&
    calls.scope is Some(scope) &&
    original_mock_scope_matches(original, scope)) ||
    !original_mock_request_values_current(state, request) ||
    state.reclaimed ||
    !physical_equal(request, prepared.request) ||
    !physical_equal(request.task, state.task) ||
    request.fixed_request_cid != state.fixed_request_cid ||
    request.slot != state.progress.slot ||
    !(state.requests.get(request.slot) is Some(retained) &&
    physical_equal(prepared, retained)) {
    return Err(Refusal)
  }
  let observed_at = original.now.unwrap()()
  // Observe the Host clock/current callbacks before reading the original key
  // or selecting a fallback. No callback may mutate a request after its final
  // nominal/key checks and still obtain an answer.
  if observed_at.is_empty() ||
    !original_mock_provider_matches(original, provider, state.task) {
    return Err(Refusal)
  }
  if check_model_physical_start_current(state, reader) is Err(_) {
    return Err(Refusal)
  }
  if !original_mock_provider_matches(original, provider, state.task) ||
    !original_mock_request_values_current(state, request) {
    return Err(Refusal)
  }
  let value = match
    select_mock_answer(
      original.answers.unwrap(),
      original.declaration.unwrap(),
      request.key,
    ) {
    Ok(value) => value
    Err(_) => return Err(Refusal)
  }
  Ok({
    value: value.value,
    provider_model: "typed-answers",
    provider_request_id: request.slot_cid,
    input_tokens: 0L,
    output_tokens: 0L,
    observed_at,
  })
}
