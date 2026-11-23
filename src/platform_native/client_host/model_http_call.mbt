///|
pub(all) enum NativeClientModelHttpIssue {
  ForeignOriginal
  Original(NativeLocalAdoptionIssue)
  Library(NativeLocalModelHttpIssue)
  Execution(@host.ClientInferPlanGraphIssue)
  Dependencies(@environment.ModelDependencyIssue)
  Dispatch(@model.ModelExecutionIssue)
  RawPolicy(@host.ClientModelRawCaptureIssue)
  Raw(@model.ModelRawCaptureSaveIssue)
  RawStore(NativeClientModelRawIssue)
  Http(@http.NativeHttpIssue)
}

///|
// One Client and one consumed Entry. The Native command uses its existing
// outer loop to pump the socket on the Read which owns the Library. Core
// callbacks only register custody, observe the result or request local stop.
struct NativeClientModelHttpCall {
  capture : NativeLocalJournalCapture
  request : @model.ModelRequest
  prepared : @model.PreparedModelHttpChatRequest
  raw_registration : @host.ClientModelRawCaptureRegistration
  endpoint : String
  credential : @filesystem.PrivateFileProjection
  expires_at : Int64
  wire : Bytes
  mut original : @model.ModelPhysicalCall?
  mut next_in_runtime : NativeClientModelHttpCall?
  mut client : @http.Client?
  mut client_create_failure : @http.NativeHttpClientCreateFailure?
  mut cancelled : Bool
  mut started : Bool
  mut start_refusal : NativeClientModelHttpIssue?
  mut advancing : Bool
  mut stop_scope_pending : Bool
  transfer_sizes : FixedArray[Int64]
  mut response : @http.NativeHttpResponse?
  mut raw : @model.ModelRawCaptureSave?
  mut raw_store : NativeClientModelRawCapture?
  mut decode_attempted : Bool
  mut outcome : @model.ModelPhysicalCallPoll?
}

///|
struct NativeModelHttpInstallation {
  capture : NativeLocalJournalCapture
  runtime : NativeLocalPackagedRuntime
  execution : @environment.ModelExecutionContract
  implementation : @model.ModelProvider
  binding : @publication.RunEvidenceValue
  provider : @model.AdmittedStructuredModelProvider
  response : @environment.ModelResponseProfile
  profile : @environment.ModelResponseProfileInstallation
  credential : @filesystem.PrivateFileProjection
  run_policy : NativeModelHttpRunPolicy
}

///|
/// Locators for the nonsecret originals in the already adopted settings.
/// The credential remains the original private file chosen by the setting.
pub(all) struct NativeModelHttpConfigurationFiles {
  setting : String
  installation_revision : String
  configuration_contract : String
  response_profile : String
}

///|
struct NativeModelHttpExecution {
  configuration : NativeModelHttpConfiguration
  contract : @environment.ModelExecutionContract
  dependencies : @environment.SingleAttemptModelDependencies
}

///|
/// The exact Common contract to use for this occurrence's Request Graph.
pub fn NativeModelHttpExecution::execution_contract(
  self : Self,
) -> @environment.ModelExecutionContract {
  self.contract
}

///|
// Checked configuration DATA borrowed by Task normalization and installation.
// It retains the one existing adoption and the exact canonical Provider.
struct NativeModelHttpConfiguration {
  capture : NativeLocalJournalCapture
  settings : NativeLocalConfigurationSelection
  setting : NativeLocalSelectedFile
  provider_file : NativeLocalSelectedFile
  selected : NativeLocalPreparationInstallationSelection
  defaults : @host.ClientModelProviderDefaults
  provider_wire : String
  route : @model.ResolvedStructuredModel
  response : @environment.ModelResponseProfile
  execution_file : String?
  policy_file : String?
}

///|
/// The same configured defaults used by the later physical admission.
pub fn NativeModelHttpConfiguration::provider_defaults(
  self : Self,
) -> @host.ClientModelProviderDefaults {
  self.defaults
}

///|
fn NativeLocalJournalCapture::require_model_http_runtime_in_original_read(
  self : NativeLocalJournalCapture,
  runtime : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeClientModelHttpIssue] {
  if self.check_original_read_lifetime() is Err(issue) {
    return Err(Original(issue))
  }
  guard self.original_resources is Some(original) &&
    runtime.original_resources is Some(pair) &&
    physical_equal(pair, original.pair) &&
    runtime.original_read is Some((host, read)) &&
    physical_equal(host, original.host) &&
    physical_equal(read, original.read) &&
    runtime.ready &&
    !runtime.closed else {
    return Err(ForeignOriginal)
  }
  if runtime.command_model_http_member is None {
    return Err(Library(Unavailable))
  }
  Ok(())
}

///|
fn NativeLocalJournalCapture::require_loaded_model_http_in_original_read(
  self : NativeLocalJournalCapture,
  runtime : NativeLocalPackagedRuntime,
) -> Result[NativeLocalLoadedModelHttp, NativeClientModelHttpIssue] {
  self
  .require_model_http_runtime_in_original_read(runtime)
  .bind(_ => {
    guard runtime.model_http_load is Some(Ok(loaded)) && !loaded.stopping else {
      return Err(ForeignOriginal)
    }
    Ok(loaded)
  })
}

///|
/// Read the adopted nonsecret Provider originals before Task normalization.
/// The existing Read funds these Common readers and the retained selection.
pub fn NativeLocalJournalCapture::read_model_http_configuration_in_original_read(
  self : NativeLocalJournalCapture,
  files : NativeModelHttpConfigurationFiles,
  provider_id : String,
  response_profile_cid : String,
  limits : @environment.ModelTaskLimits,
  execution_file? : String? = None,
  policy_file? : String? = None,
) -> Result[NativeModelHttpConfiguration, NativeClientModelHttpIssue] {
  self
  .with_current_adoption_material_in_original_read((host, _, operations) => {
    let adopted = host.session.settings
    let settings = adopted.files
    guard settings.iter().find_first(file => file.name == files.setting)
      is Some(file) else {
      return Err(CustodyLost)
    }
    guard native_model_http_configuration_parse(file.body.length(), 8192, 16, 4)
      is Some(setting_working) else {
      return Err(ConfigurationLimit)
    }
    // The decoder returns the two names and the selected record. Its indexed
    // tree, source, key maps and closed-object checks stay in this peak.
    if fund_native_model_http_configuration(
        operations,
        {
          record_headers: 3L,
          reference_slots: 2L,
          scalar_words: 0L,
          owned_utf16_units: Int::min(256, file.body.length()).to_int64(),
          owned_wire_bytes: 0L,
        },
        setting_working,
      )
      is Err(issue) {
      return Err(issue)
    }
    guard local_preparation_installation_selection(file.body) is Ok(selected) &&
      settings.iter().find_first(file => file.name == selected.provider_file)
      is Some(provider_file) &&
      settings
      .iter()
      .find_first(file => file.name == files.installation_revision)
      is Some(revision_file) &&
      settings
      .iter()
      .find_first(file => file.name == files.configuration_contract)
      is Some(contract_file) &&
      settings.iter().find_first(file => file.name == files.response_profile)
      is Some(response_file) &&
      !settings.any(candidate => candidate.name == selected.credential_file) &&
      selected.credential_file != host.session.source_name else {
      return Err(CustodyLost)
    }
    for selection in [execution_file, policy_file] {
      if selection is Some(name) &&
        (
          name == file.name ||
          name == provider_file.name ||
          name == revision_file.name ||
          name == contract_file.name ||
          name == response_file.name ||
          !settings.any(candidate => candidate.name == name)
        ) {
        return Err(CustodyLost)
      }
    }
    if policy_file is Some(_) && policy_file == execution_file {
      return Err(CustodyLost)
    }
    let bodies = limits.bodies
    let p = provider_file.body.length()
    let r = revision_file.body.length()
    let c = contract_file.body.length()
    if p > 65536 || r == 0 || r > 65536 || c == 0 || c > 65536 {
      return Err(ConfigurationLimit)
    }
    guard native_model_http_configuration_parse(
        provider_file.body.length(),
        bodies.max_bytes,
        bodies.max_nodes,
        bodies.max_depth,
      )
      is Some(provider_working) else {
      return Err(ConfigurationLimit)
    }
    // The route holder and its parser strings survive while the same body is
    // read as canonical wire for the Common binding and selected defaults.
    let route_bound : @execution.PreparationRepresentationUnits = {
      record_headers: 5L,
      reference_slots: 6L,
      scalar_words: 0L,
      owned_utf16_units: p.to_int64(),
      owned_wire_bytes: 0L,
    }
    guard @execution.compose_preparation_representation([
        provider_working, route_bound,
      ])
      is Some(route_working) else {
      return Err(ConfigurationLimit)
    }
    if fund_native_model_http_configuration(
        operations,
        {
          ..route_bound,
          record_headers: 0L,
          reference_slots: 0L,
          owned_utf16_units: 0L,
        },
        route_working,
      )
      is Err(issue) {
      return Err(issue)
    }
    guard @model.read_portable_model_http_chat_file_route(
        provider_file.body,
        provider_id,
        revision_file.content_cid,
        contract_file.content_cid,
        response_profile_cid,
        selected.credential_file,
        bodies,
      )
      is Some(route) else {
      return Err(CustodyLost)
    }
    let route_retained = {
      ..route_bound,
      owned_utf16_units: route.selector.length().to_int64() +
      route.model_id.length().to_int64() +
      route.endpoint.length().to_int64(),
    }
    let wire_retained : @execution.PreparationRepresentationUnits = {
      ..route_retained,
      record_headers: route_retained.record_headers + 1L,
      owned_utf16_units: route_retained.owned_utf16_units + p.to_int64(),
    }
    // The selected route stays live alongside the Provider wire and the peer
    // UTF8 strings. Only the route and the Provider wire escape this phase.
    guard @execution.compose_preparation_representation([
        route_retained,
        native_model_http_utf8_configuration_working(
          provider_file.body,
          revision_file.body,
          contract_file.body,
        ),
      ])
      is Some(wire_working) else {
      return Err(ConfigurationLimit)
    }
    if fund_native_model_http_configuration(
        operations, wire_retained, wire_working,
      )
      is Err(issue) {
      return Err(issue)
    }
    let (wire, revision, contract) = (
      @utf8.decode(provider_file.body),
      @utf8.decode(revision_file.body),
      @utf8.decode(contract_file.body),
    ) catch {
      _ => return Err(Encoding)
    }
    guard @host.client_model_provider_defaults_construction_extent(
        provider_id, revision, contract, wire, bodies,
      )
      is Some(defaults_working) &&
      @host.client_model_provider_defaults_retained_bound(
        p,
        Int::min(p, bodies.max_nodes),
        16384,
      )
      is Some(defaults_retained) else {
      return Err(ConfigurationLimit)
    }
    let defaults_phase = native_model_http_metadata_units(defaults_working)
    if fund_native_model_http_configuration(
        operations,
        native_model_http_metadata_units(defaults_retained),
        {
          ..defaults_phase,
          record_headers: defaults_phase.record_headers + 2L,
          owned_utf16_units: defaults_phase.owned_utf16_units +
          revision.length().to_int64() +
          contract.length().to_int64(),
        },
      )
      is Err(issue) {
      return Err(issue)
    }
    guard @host.read_client_model_provider_defaults(
        provider_id,
        revision,
        contract,
        wire,
        bodies,
        limits.max_work,
      )
      is Ok(defaults) else {
      return Err(CustodyLost)
    }
    guard native_model_http_profile_construction(response_file.body, bodies)
      is Some((profile_retained, profile_working)) else {
      return Err(ConfigurationLimit)
    }
    if fund_native_model_http_configuration(
        operations, profile_retained, profile_working,
      )
      is Err(issue) {
      return Err(issue)
    }
    guard @environment.read_model_response_profile(
        response_file.body,
        response_profile_cid,
        limits.bodies,
        limits.max_work,
      )
      is Ok(response) else {
      return Err(CustodyLost)
    }
    Ok({
      capture: self,
      settings: adopted,
      setting: file,
      provider_file,
      selected,
      defaults,
      provider_wire: wire,
      route,
      response,
      execution_file,
      policy_file,
    })
  })
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
}

///|
/// Persist the selected file projection at the end of explicit adoption.
/// Model preparation restores this row through its read-only entry below.
pub fn NativeLocalJournalCapture::adopt_model_http_configuration_in_original_read(
  self : NativeLocalJournalCapture,
  configuration : NativeModelHttpConfiguration,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !physical_equal(configuration.capture, self) || self.session.existing_only {
    return Err(CustodyLost)
  }
  let written = Ref(false)
  self.with_current_adoption_material_in_original_read(
    (host, _, operations) => {
      if !physical_equal(host.session.settings, configuration.settings) {
        return Err(CustodyLost)
      }
      host.journal
      .transaction_with_reads(
        () => {
          host
          .installation_original_locked(
            configuration.setting,
            configuration.provider_file,
            configuration.selected,
            true,
            () => self.check_original_read_lifetime().map_err(_ => CustodyLost),
            capture=Some(self),
            operations=Some(operations),
          )
          .map(_ => ())
        },
        reads=Some(operations.reads),
      )
      .map_err(issue => {
        match issue {
          TransactionUnknown => NativeLocalAdoptionIssue::TransactionUnknown
          _ => NativeLocalAdoptionIssue::Journal(issue)
        }
      })
    },
    installation_written=Some(written),
  )
}

///|
/// Bind nonsecret material from this same adoption to the checked occurrence.
/// The existing Common readers own Task identity and dependency verification.
pub fn NativeLocalJournalCapture::prepare_model_http_execution_in_original_read(
  self : NativeLocalJournalCapture,
  configuration : NativeModelHttpConfiguration,
  occurrence : @host.ClientInferOccurrence,
  limits : @environment.ModelTaskLimits,
) -> Result[NativeModelHttpExecution, NativeClientModelHttpIssue] {
  guard physical_equal(configuration.capture, self) &&
    configuration.execution_file is Some(name) else {
    return Err(ForeignOriginal)
  }
  self
  .with_current_adoption_material_in_original_read((host, _, operations) => {
    if !physical_equal(host.session.settings, configuration.settings) {
      return Err(CustodyLost)
    }
    guard configuration.settings.files
      .iter()
      .find_first(file => file.name == name)
      is Some(materials) else {
      return Err(CustodyLost)
    }
    let bodies = limits.bodies
    guard native_model_http_configuration_parse(
        materials.body.length(),
        bodies.max_bytes,
        bodies.max_nodes,
        bodies.max_depth,
      )
      is Some(bundle_peak) else {
      return Err(ConfigurationLimit)
    }
    if fund_native_model_http_configuration(
        operations,
        {
          record_headers: 0L,
          reference_slots: 0L,
          scalar_words: 0L,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        },
        bundle_peak,
      )
      is Err(issue) {
      return Err(issue)
    }
    guard @model.read_portable_model_http_execution_wires(
        materials.body,
        bodies,
      )
      is Some((cid, execution, prompt, retry, backoff)) else {
      return Err(CustodyLost)
    }
    guard native_model_http_execution_construction(
        [execution, prompt, retry, backoff],
        materials.body.length(),
        bodies,
      )
      is Some((retained, working)) else {
      return Err(ConfigurationLimit)
    }
    if fund_native_model_http_configuration(operations, retained, working)
      is Err(issue) {
      return Err(issue)
    }
    Ok(
      @host.read_client_infer_occurrence_model_execution(
        occurrence,
        @utf8.encode(execution),
        cid,
        bodies,
        limits.max_work,
      )
      .map_err(issue => NativeClientModelHttpIssue::Execution(issue))
      .bind(contract => {
        @environment.read_single_attempt_model_dependencies(
          contract,
          Some(@utf8.encode(prompt)),
          Some(@utf8.encode(retry)),
          Some(@utf8.encode(backoff)),
          bodies,
          limits.max_work,
        )
        .map_err(issue => NativeClientModelHttpIssue::Dependencies(issue))
        .map(dependencies => { configuration, contract, dependencies, })
      }),
    )
  })
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  .bind(value => value)
}

///|
// The Native runtime manifest identifies the compiled Common source and the
// exact packaged HTTP component together. Both portable codec stages are in
// that same installed build. The adopted Provider supplies the endpoint.
fn native_model_http_installation_profile(
  manifest_sha256 : String,
  endpoint : String,
) -> @environment.ModelResponseProfileInstallation {
  let artifact = "sha256:" + manifest_sha256
  {
    builder_id: "actql/native-portable-chat",
    builder_revision: "1",
    codec_id: "actql/openai-chat-envelope",
    codec_revision: "1",
    build_artifact_cid: artifact,
    sdk: None,
    endpoint,
    http_method: "POST",
    streaming: false,
    validator_id: "actql/openai-chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: artifact,
    completion_basis: "generation_finish",
  }
}

///|
/// Join the exact admitted configuration and checked execution to the
/// command's Runtime. Load the selected library only after successful Model
/// admission and restore its original private file projection without opening
/// a Client or reading credential bytes.
pub fn NativeLocalJournalCapture::admit_model_http_installation_in_original_read(
  self : NativeLocalJournalCapture,
  runtime : NativeLocalPackagedRuntime,
  prepared : NativeModelHttpExecution,
  occurrence : @host.ClientInferOccurrence,
  limits : @environment.Limits,
  diagnostic_ceiling : Int,
) -> Result[NativeModelHttpInstallation, NativeClientModelHttpIssue] {
  let configuration = prepared.configuration
  let execution = prepared.contract
  if !physical_equal(configuration.capture, self) || diagnostic_ceiling <= 0 {
    return Err(ForeignOriginal)
  }
  if self.require_model_http_runtime_in_original_read(runtime) is Err(issue) {
    return Err(issue)
  }
  guard runtime.selection is Some((_, _, _, manifest_sha256)) else {
    return Err(ForeignOriginal)
  }
  self
  .with_current_adoption_material_in_original_read((host, _, operations) => {
    if !physical_equal(host.session.settings, configuration.settings) {
      return Err(CustodyLost)
    }
    let task = @environment.model_execution_task(execution)
    let connection = @environment.model_task_connector(task)
    let binding = @host.client_model_provider_defaults_binding(
      configuration.defaults,
    )
    let wire = configuration.provider_wire
    let response = configuration.response
    let resolved = configuration.route
    let selected = configuration.selected
    let profile_layout : @execution.PreparationRepresentationUnits = {
      record_headers: 2L,
      reference_slots: 12L,
      scalar_words: 1L,
      owned_utf16_units: 71L,
      owned_wire_bytes: 0L,
    }
    guard native_model_http_capability_construction(binding, wire)
      is Some(capability_peak) &&
      @execution.compose_preparation_representation([
        capability_peak, profile_layout,
      ])
      is Some(capability_working) else {
      return Err(ConfigurationLimit)
    }
    // Installed physical Provider, capability, admitted provider and private
    // projection holders coexist with the installed profile and its digest.
    if fund_native_model_http_configuration(
        operations,
        {
          ..profile_layout,
          record_headers: profile_layout.record_headers + 12L,
          reference_slots: profile_layout.reference_slots + 45L,
          scalar_words: profile_layout.scalar_words + 10L,
        },
        capability_working,
      )
      is Err(issue) {
      return Err(issue)
    }
    let profile = native_model_http_installation_profile(
      manifest_sha256,
      resolved.endpoint,
    )
    guard @environment.check_model_response_profile_binding(
        response,
        task,
        profile,
        None,
      )
      is Ok(_) &&
      @model.install_async_model_provider(connection) is Ok(implementation) &&
      @model.register_structured_model_capability(
        implementation, binding, wire, resolved, response, true, true,
      )
      is Ok(capability) &&
      @model.admit_structured_model_provider(
        capability,
        resolved,
        execution,
        prepared.dependencies,
        profile,
        (_, prompt) => {
          @environment.model_openai_chat_instructions(prompt) is Some(_)
        },
      )
      is Ok(provider) &&
      @model.model_http_chat_installation_matches(provider, profile) &&
      @model.model_http_original_credential_reference(provider, wire)
      is Some(reference) &&
      reference == "file:" + selected.credential_file else {
      return Err(CustodyLost)
    }
    let run_policy = match
      read_native_model_http_run_policy(
        configuration, occurrence, execution, limits, operations,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    host.journal
    .transaction_with_reads(
      () => {
        host.installation_original_locked(
          configuration.setting,
          configuration.provider_file,
          selected,
          false,
          () => self.check_original_read_lifetime().map_err(_ => CustodyLost),
          capture=Some(self),
          operations=Some(operations),
        )
      },
      reads=Some(operations.reads),
    )
    .map_err(issue => NativeLocalAdoptionIssue::Journal(issue))
    .map(credential => {
      capture: self,
      runtime,
      execution,
      implementation,
      binding,
      provider,
      response,
      profile,
      credential,
      run_policy,
    })
  })
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  .bind(installation => {
    // The journal's same Read is still entered. The Runtime borrows this
    // frame, owns the first load result and keeps partial loads for close.
    runtime
    .borrow_model_http_library(diagnostic_ceiling)
    .map_err(issue => Library(issue))
    .bind(_ => {
      self
      .require_loaded_model_http_in_original_read(runtime)
      .map(_ => installation)
    })
  })
}

///|
/// Borrow the installed provider and binding only for their original checked
/// execution contract. The caller may use these at its Graph and Model Scope.
pub fn NativeModelHttpInstallation::originals_for(
  self : Self,
  execution : @environment.ModelExecutionContract,
) -> (
  @model.ModelProvider,
  @publication.RunEvidenceValue,
  @environment.ModelResponseProfile,
)? {
  if physical_equal(self.execution, execution) {
    Some((self.implementation, self.binding, self.response))
  } else {
    None
  }
}

///|
// One already funded preflight's handoff for the original request. The
// retained callback relinquishes this alias when Core adopts the Call; the
// Runtime separately owns cleanup for every actual physical constructor.
struct NativeClientModelHttpPlan {
  request : @model.ModelRequest
  original : @model.PreparedModelHttpChatRequest
  installation : NativeModelHttpInstallation
  mut attempted : Bool
  mut call : NativeClientModelHttpCall?
}

///|
/// Supply the exact preflight body to the Core Plan. The original execution
/// funds the plan and this fixed handoff control before issuing either.
/// Preparation creates no physical Client and reads no credential bytes.
fn prepare_native_model_http_plan(
  request : @model.ModelRequest,
  prepared : @model.PreparedModelHttpChatRequest,
  installation : NativeModelHttpInstallation,
  quantities : @resources.QuantityAmounts,
) -> Result[
  (@model.ModelPhysicalRequestPlan, NativeClientModelHttpPlan),
  @model.ModelExecutionIssue,
] {
  guard @model.prepared_model_http_chat_material(
      prepared,
      request,
      installation.provider,
    )
    is Some(_) else {
    return Err(@model.RequestIdentity)
  }
  let handoff : NativeClientModelHttpPlan = {
    request,
    original: prepared,
    installation,
    attempted: false,
    call: None,
  }
  @model.prepared_model_http_chat_plan(
    prepared,
    installation.profile,
    quantities,
    entry => {
      guard handoff.call is Some(call) else { return None }
      let started = call.start_for_entry(entry)
      if started is Some(_) {
        handoff.call = None
      }
      started
    },
    measured_transfer=true,
  ).map(plan => (plan, handoff))
}

///|
/// Install this exact portable projection as the Core's bounded preflight.
/// The caller reserves the original Read's codec, handoff and Plan overlap
/// before starting it. Only the selected installation drafts a request.
pub fn NativeModelHttpInstallation::start_model_http_preflight(
  self : NativeModelHttpInstallation,
  request : @model.ModelRequest,
  quantities : @resources.QuantityAmounts,
  max_frames : Int,
  retain : (NativeClientModelHttpPlan) -> Unit,
) -> Result[@model.ModelRequestPreflight, @model.ModelExecutionIssue] {
  let projection = match
    @model.start_model_http_chat_request_projection(
      self.provider,
      request,
      self.profile,
      max_frames,
    ) {
    Ok(value) => value
    Err(issue) => return Err(native_model_http_projection_issue(issue))
  }
  Ok({
    advance: () => {
      match @model.advance_model_http_chat_request_projection(projection) {
        Ok(None) => Ok(None)
        Ok(Some(original)) =>
          prepare_native_model_http_plan(request, original, self, quantities).map(pair => {
              retain(pair.1)
              Some(pair.0)
            },
          )
        Err(issue) => Err(native_model_http_projection_issue(issue))
      }
    },
    cleanup: () => {
      @model.retire_model_http_chat_request_projection(projection)
      true
    },
  })
}

///|
fn native_model_http_projection_issue(
  issue : @model.OpenAIChatProjectionIssue,
) -> @model.ModelExecutionIssue {
  match issue {
    @model.ForeignRequest => @model.RequestIdentity
    @model.Unsupported => @model.InvalidProvider
    @model.Limit => @model.RequestLimit
  }
}

///|
/// Prepare a dedicated Client on the original Runtime before any Entry.
/// The installed caller supplies the server trust path and the retained
/// codec output. Link the Call before acquiring the physical Client so a
/// partial constructor stays with the same Runtime's cleanup.
pub fn NativeLocalJournalCapture::prepare_model_http_call_in_original_read(
  self : NativeLocalJournalCapture,
  ca_path : String,
  connect_timeout_ms : Int,
  operation_timeout_ms : Int,
  handoff : NativeClientModelHttpPlan,
  raw_registration : @host.ClientModelRawCaptureRegistration,
  expires_at : Int64,
) -> Result[NativeClientModelHttpCall, NativeClientModelHttpIssue] {
  let installation = handoff.installation
  guard physical_equal(installation.capture, self) && !handoff.attempted else {
    return Err(ForeignOriginal)
  }
  let loaded = match
    self.require_loaded_model_http_in_original_read(installation.runtime) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @model.prepared_model_http_chat_material(
      handoff.original,
      handoff.request,
      installation.provider,
    )
    is Some((endpoint, profile, wire)) else {
    return Err(ForeignOriginal)
  }
  loaded.retire_settled_call_aliases()
  if expires_at < 1L ||
    ca_path.is_empty() ||
    ca_path.length() > 4096 ||
    ca_path.contains("\u{0}") ||
    connect_timeout_ms <= 0 ||
    operation_timeout_ms < connect_timeout_ms {
    return Err(ForeignOriginal)
  }
  let maximum_body = @environment.model_response_profile_limits(profile).response_bytes.to_int64()
  let (header, _, _, _, _) = @bootstrap.native_managed_value_layout()
  // The server trust path can be live both as temporary UTF-8 and as the
  // Client's native copy. The later managed body can overlap the native
  // response until the Client closes. Charge these on the same Read.
  let ca_bytes = 3L * ca_path.length().to_int64() + 1L
  guard header > 0L &&
    @execution.preparation_representation_cost({
      record_headers: 14L,
      reference_slots: 35L,
      scalar_words: 15L,
      owned_utf16_units: 0L,
      owned_wire_bytes: maximum_body + 1L + 2L * ca_bytes,
    })
    is Some(copy) else {
    return Err(Original(ConfigurationLimit))
  }
  self
  .fund_model_http_material_in_original_read(
    copy,
    header + Int64::max(Int64::max(maximum_body + 1L, ca_bytes), 16L),
  )
  .bind(_ => {
    let call : NativeClientModelHttpCall = {
      capture: self,
      request: handoff.request,
      prepared: handoff.original,
      raw_registration,
      endpoint,
      credential: installation.credential,
      expires_at,
      wire,
      original: None,
      next_in_runtime: loaded.calls,
      client: None,
      client_create_failure: None,
      cancelled: false,
      started: false,
      start_refusal: None,
      advancing: false,
      stop_scope_pending: false,
      transfer_sizes: FixedArray::make(2, -1L),
      response: None,
      raw: None,
      raw_store: None,
      decode_attempted: false,
      outcome: None,
    }
    loaded.calls = Some(call)
    handoff.attempted = true
    match
      loaded.library.create_projected_bearer_client_with_custody(
        ca_path, maximum_body, connect_timeout_ms, operation_timeout_ms,
      ) {
      Ok(client) => {
        call.client = Some(client)
        handoff.call = Some(call)
        Ok(call)
      }
      Err(@http.RefusedBeforeAcquisition(issue)) => Err(Http(issue))
      Err(@http.CleanupRequired(failure)) => {
        call.client_create_failure = Some(failure)
        Err(Http(failure.issue()))
      }
    }
  })
}

///|
fn NativeLocalJournalCapture::fund_model_http_material_in_original_read(
  self : NativeLocalJournalCapture,
  retained : Int64,
  contiguous : Int64,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard self.original_resources is Some(original) else {
    return Err(Original(OriginalResourceScopePending))
  }
  self
  .check_original_read_lifetime()
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  .bind(_ => {
    original.host
    .prepare_domain_original_read_retained_construction(
      original.read,
      retained,
      retained,
      contiguous,
    )
    .map_err(issue => Original(OriginalResources(@arena.Read(issue))))
  })
}

///|
/// Use as the fixed transport start of this request's original physical Plan.
/// The Core gate has consumed the Entry before this binding can succeed.
fn NativeClientModelHttpCall::start_for_entry(
  self : NativeClientModelHttpCall,
  entry : @model.ModelCallEntry,
) -> @model.ModelPhysicalCall? {
  guard self.original is None && self.client is Some(_) && !self.cancelled else {
    return None
  }
  let original = @model.register_model_physical_call_for_request(
    entry,
    self.request,
    () => {
      let result = if self.cancelled && !self.started {
        // Local stop of the original unsent Call, after the outer driver
        // retained its typed refusal. No provider result was observed.
        @model.PhysicalRejected(@model.Cancelled, {
          input_tokens: None,
          output_tokens: None,
        })
      } else {
        self.outcome.unwrap_or(@model.PhysicalPending)
      }
      guard self.original is Some(call) else { return result }
      if self.client is None && !self.stop_scope_pending {
        @model.PhysicalIoQuiescent(call, result)
      } else {
        @model.PhysicalIoPending(call, result)
      }
    },
    () => self.cancelled = true,
    _ => self.client is None && !self.stop_scope_pending,
  )
  self.original = original
  original
}

///|
fn NativeClientModelHttpCall::start_in_original_read(
  self : NativeClientModelHttpCall,
  call : @model.ModelPhysicalCall,
  client : @http.Client,
) -> Result[Unit, NativeClientModelHttpIssue] {
  @model.check_prepared_model_http_chat_dispatch_current(
    call,
    self.prepared,
    self.raw_registration,
  )
  .map_err(issue => {
    match issue {
      @model.Dispatch(issue) => NativeClientModelHttpIssue::Dispatch(issue)
      @model.Raw(issue) => RawPolicy(issue)
    }
  })
  .bind(_ => {
    self.capture
    .check_original_read_lifetime()
    .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  })
  .bind(_ => {
    if self.cancelled {
      return Err(ForeignOriginal)
    }
    client
    .start_projected_bearer_post(
      self.endpoint,
      self.wire,
      self.credential,
      self.expires_at,
    )
    .map_err(issue => Http(issue))
  })
}

///|
fn NativeClientModelHttpCall::observe_unknown(
  self : NativeClientModelHttpCall,
) -> Unit {
  self.outcome = Some(
    @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
  )
}

///|
/// The existing outer Native loop calls once per readiness step, outside the
/// Core poll. A failed physical close retains the same Client for its next
/// cleanup step. A missing response can never schedule a replacement send.
fn NativeClientModelHttpCall::drive_in_original_read(
  self : NativeClientModelHttpCall,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard self.original is Some(call) && !self.advancing else {
    return Err(ForeignOriginal)
  }
  if !self.cancelled && self.start_refusal is Some(original) {
    return Err(original)
  }
  guard self.client is Some(client) else { return Ok(()) }
  match self.capture.check_original_read_lifetime() {
    Ok(_) => ()
    Err(issue) => {
      let failure = NativeClientModelHttpIssue::Original(issue)
      if !self.started && !self.cancelled {
        self.start_refusal = Some(failure)
      }
      return Err(failure)
    }
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  if self.cancelled {
    return Err(ForeignOriginal)
  }
  if self.response is None && self.outcome is None {
    if !self.started {
      if self.start_in_original_read(call, client) is Err(issue) {
        // The managed preflight and the C setup return errors before multi
        // performs I/O. Cleanup can still be pending (for example, a failed
        // credential descriptor close). Keep the original cause and Client.
        self.start_refusal = Some(issue)
        return Err(issue)
      }
      self.started = true
    }
    match
      client.poll_measured_bearer_post(
        self.transfer_sizes,
        wait_milliseconds=50,
      ) {
      Ok(None) => return Ok(())
      Ok(Some(response)) => self.response = Some(response)
      Err(issue) => {
        self.observe_unknown()
        // Yield terminal loss only after the original Client closes. If that
        // close fails, keep its custody and return the first transport cause.
        match issue {
          @http.CapacityExceeded
          | @http.Cancelled
          | @http.DeadlineExpired
          | @http.Transport(_) =>
            return self
              .close_client_in_original_read(client)
              .map_err(_ => Http(issue))
          _ => return Err(Http(issue))
        }
      }
    }
  }
  self.close_client_in_original_read(client)
}

///|
/// The outer command retires physical children before the original Core
/// cleanup poll. This uses the same captured Read in cleanup mode, independent
/// of whether the Journal still authorizes dispatch, observation or disclosure.
pub fn NativeClientModelHttpCall::close_in_original_cleanup(
  self : NativeClientModelHttpCall,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard !self.advancing && self.capture.original_resources is Some(original) else {
    return Err(Original(OriginalResourceScopePending))
  }
  self.cancelled = true
  if self.started && self.outcome is None {
    self.observe_unknown()
  }
  // A completed Client has no claim on another child's pending Read leave.
  // Still finish the failed scope return from our own stop before ACK.
  if self.client is None &&
    self.client_create_failure is None &&
    !self.stop_scope_pending {
    return Ok(())
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  if original.interrupted {
    match original.finish_pending_leave() {
      Ok(_) => self.stop_scope_pending = false
      Err(issue) => return Err(Original(issue))
    }
  }
  if self.client is None && self.client_create_failure is None {
    return Ok(())
  }
  let stopped = original.stage(
    @arena.HostRead,
    () => Ok(self.retire_client_in_original_cleanup_read()),
    cleanup=true,
  )
  self.stop_scope_pending = original.interrupted
  stopped
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  .bind(result => result)
}

///|
fn NativeClientModelHttpCall::retire_client_in_original_cleanup_read(
  self : NativeClientModelHttpCall,
) -> Result[Unit, NativeClientModelHttpIssue] {
  if self.client_create_failure is Some(failure) {
    return failure
      .retry_cleanup()
      .map(_ => self.client_create_failure = None)
      .map_err(issue => Http(issue))
  }
  guard self.client is Some(client) else { return Ok(()) }
  client
  .close_bearer_post_in_original_scope()
  .map(_ => self.client = None)
  .map_err(issue => Http(issue))
}

///|
// Called in the original HostRead before the next Call is prepared. Core's
// settlement and retirement are separate facts and both must be present.
// Dropping these duplicate references does not refund the Read reservation.
fn NativeLocalLoadedModelHttp::retire_settled_call_aliases(
  self : NativeLocalLoadedModelHttp,
) -> Unit {
  let mut previous : NativeClientModelHttpCall? = None
  let mut pending = self.calls
  while pending is Some(call) {
    let next = call.next_in_runtime
    if call.original is Some(original) &&
      original.settlement_acknowledged &&
      original.retired &&
      call.client is None &&
      call.raw_store is None &&
      !call.stop_scope_pending {
      match previous {
        Some(older) => older.next_in_runtime = next
        None => self.calls = next
      }
      call.next_in_runtime = None
      call.response = None
      call.raw = None
      call.outcome = None
      call.original = None
    } else {
      previous = pending
    }
    pending = next
  }
}

///|
/// Retire physical HTTP clients before the business execution's Core cleanup.
/// A failed Raw Store child stays linked until its separate Store has closed.
pub fn NativeLocalPackagedRuntime::close_model_http_calls(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard self.model_http_load is Some(Ok(loaded)) else { return Ok(()) }
  loaded.stopping = true
  let mut previous : NativeClientModelHttpCall? = None
  let mut pending = loaded.calls
  while pending is Some(call) {
    let next = call.next_in_runtime
    if call.raw_store is Some(raw) {
      guard raw.child is Some(child) else { return Err(ForeignOriginal) }
      match child.reconcile_original_store_return() {
        Ok(true) => call.raw_store = None
        Ok(false) => ()
        Err(issue) => return Err(RawStore(Store(issue)))
      }
    }
    match call.close_in_original_cleanup() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    // A failed Store child has its own transaction and return obligations.
    // The original command closes that Store after physical and Core cleanup.
    if call.raw_store is Some(_) {
      previous = pending
    } else {
      match previous {
        Some(older) => older.next_in_runtime = next
        None => loaded.calls = next
      }
      call.next_in_runtime = None
    }
    pending = next
  }
  Ok(())
}

///|
fn NativeClientModelHttpCall::close_client_in_original_read(
  self : NativeClientModelHttpCall,
  client : @http.Client,
) -> Result[Unit, NativeClientModelHttpIssue] {
  client
  .close_checked()
  .map(_ => self.client = None)
  .map_err(issue => Http(issue))
}

///|
/// A discarded preflight may close its dedicated Client before an Entry
/// exists. Once registered, cleanup instead follows the same physical call.
pub fn NativeClientModelHttpCall::close_unentered_in_original_read(
  self : NativeClientModelHttpCall,
) -> Result[Unit, NativeClientModelHttpIssue] {
  if self.original is Some(_) || self.started || self.advancing {
    return Err(ForeignOriginal)
  }
  guard self.client is Some(client) else { return Ok(()) }
  match self.capture.check_original_read_lifetime() {
    Ok(_) => self.close_client_in_original_read(client)
    Err(issue) => Err(Original(issue))
  }
}

///|
/// Prepare the Store child from the exact completed HTTP response. The command
/// retains the returned child before persistence, including when Store or
/// Read return fails. A failed save cannot acquire another HTTP attempt.
fn NativeClientModelHttpCall::prepare_raw_save_in_original_read(
  self : NativeClientModelHttpCall,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  namespace_id : String,
  store : @publication_store.Store,
  observed_at : String,
) -> Result[NativeClientModelRawCapture, NativeClientModelHttpIssue] {
  match self.capture.check_original_read_lifetime() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  guard !self.cancelled &&
    !self.advancing &&
    self.client is None &&
    self.raw is None &&
    self.original is Some(call) &&
    self.response is Some(response) &&
    self.outcome is None else {
    return Err(ForeignOriginal)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let raw = match
    @model.observe_model_raw_capture(
      call,
      self.raw_registration,
      "sha256:" + @sha.hex(response.body),
      response.body.length(),
      response.status,
      true,
      observed_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Raw(issue))
  }
  self.raw = Some(raw)
  self.capture
  .prepare_model_raw_capture_in_original_read(
    request,
    compiled,
    definition,
    namespace_id,
    store,
    raw,
    response.body,
    self,
  )
  .map_err(issue => RawStore(issue))
}

///|
/// Borrow the confirmed receipt on the original Read. The decoded text stays
/// on that Read until the same original Model observes the settled Call.
fn NativeClientModelHttpCall::adopt_saved_chat(
  self : NativeClientModelHttpCall,
  saved : NativeClientModelRawCapture,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard !self.cancelled &&
    !self.advancing &&
    !self.decode_attempted &&
    self.client is None &&
    self.original is Some(_) &&
    self.raw is Some(raw) &&
    self.response is Some(response) &&
    self.outcome is None &&
    saved.phase is ReceiptReady &&
    physical_equal(saved.capture, self.capture) &&
    physical_equal(saved.view, raw) else {
    return Err(ForeignOriginal)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let units = response.body.length().to_int64()
  let (header, unit, terminator, _, _) = @bootstrap.native_managed_value_layout()
  // The pinned decoder fills one UInt16 array then presents its backing as a
  // String. Also reserve the measured poll and the Raw fact/binding views
  // that coexist when Core accepts the original Store receipt.
  guard header > 0L &&
    unit == 2L &&
    terminator == unit &&
    @execution.preparation_representation_cost({
      record_headers: 9L,
      reference_slots: 20L,
      scalar_words: 8L,
      owned_utf16_units: units + 1L,
      owned_wire_bytes: 0L,
    })
    is Some(decoded) else {
    return Err(Original(ConfigurationLimit))
  }
  self.decode_attempted = true
  if self.capture.fund_model_http_material_in_original_read(
      decoded,
      header + Int64::max(units * unit + terminator, 40L),
    )
    is Err(issue) {
    return Err(issue)
  }
  let receipt = match saved.acknowledge_saved() {
    Ok(value) => value
    Err(issue) => return Err(RawStore(issue))
  }
  if self.cancelled {
    return Err(ForeignOriginal)
  }
  if self.capture.check_original_read_lifetime() is Err(issue) {
    return Err(Original(issue))
  }
  let body = @utf8.decode(response.body, ignore_bom=true) catch {
    _ => {
      // The original Raw was confirmed even when the provider used
      // non-UTF8. An observed complete HTTP reply still has a known outcome.
      let failure = if response.status >= 200 && response.status < 300 {
        @model.SchemaInvalid
      } else {
        @model.ProviderError
      }
      self.outcome = Some(
        @model.PhysicalMeasuredHttp(
          receipt,
          self.transfer_sizes[0],
          self.transfer_sizes[1],
          @model.PhysicalRejected(failure, {
            input_tokens: None,
            output_tokens: None,
          }),
        ),
      )
      self.response = None
      self.raw = None
      return Ok(())
    }
  }
  @model.model_saved_raw_chat_response(receipt, body, None)
  .map(value => {
    self.outcome = Some(
      @model.PhysicalMeasuredHttp(
        receipt,
        self.transfer_sizes[0],
        self.transfer_sizes[1],
        @model.PhysicalChatResponse(value),
      ),
    )
    // The Store owns the confirmed bytes. The checked response now owns its
    // separate decoded text and exact receipt.
    self.response = None
    self.raw = None
  })
  .map_err(issue => Raw(issue))
}
