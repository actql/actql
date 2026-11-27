///|
/// One exact checked receiving port and producing Model occurrence. This
/// declaration is authenticated with its selected settings file and carries
/// no successful attempt, typed result, input-read, or exchange authority.
priv struct NativeModelOutputDeclaration {
  input : Int
  stage : Int
  step : Int
  task : String
  binding : String
  profile : String
  schema : String
  receiving_binding : String
  classification : @environment.DataClassification
}

///|
priv struct NativeModelHttpPendingEgress {
  selection : @host.ClientInferPendingEgress
  settings : NativeLocalConfigurationSelection
  original : NativeLocalSelectedFile
  receiving_task : String
  receiving_profile : String
  declarations : Array[NativeModelOutputDeclaration]
}

///|
priv enum NativeModelHttpEgressSelection {
  NativeEgressReady(@host.ClientInferEgressAdmission)
  NativeEgressPending(NativeModelHttpPendingEgress)
}

///|
fn native_model_output_policy_cid(
  fields : @decode.ObjectView,
  field : String,
) -> String? {
  guard native_model_http_policy_text(fields, field, 71) is Some(cid) &&
    cid.length() == 71 &&
    cid.has_prefix("sha256:") else {
    return None
  }
  for index in 7..<71 {
    let digit = cid[index].to_int()
    if !((48 <= digit && digit <= 57) || (97 <= digit && digit <= 102)) {
      return None
    }
  }
  Some(cid)
}

///|
fn native_model_output_declaration(
  cursor : @decode.Cursor,
) -> NativeModelOutputDeclaration? {
  guard @decode.closed_object(cursor, [
      "classification", "input_index", "producer_binding_cid", "producer_profile_cid",
      "producer_schema_cid", "producer_stage", "producer_step", "producer_task_cid",
      "receiving_binding_cid",
    ])
    is Ok(fields) &&
    native_model_http_policy_integer(fields, "input_index", 0L, 2147483647L)
    is Some(input) &&
    native_model_http_policy_integer(fields, "producer_stage", 0L, 2147483647L)
    is Some(stage) &&
    native_model_http_policy_integer(fields, "producer_step", 0L, 2147483647L)
    is Some(step) &&
    native_model_output_policy_cid(fields, "producer_task_cid") is Some(task) &&
    native_model_output_policy_cid(fields, "producer_binding_cid")
    is Some(binding) &&
    native_model_output_policy_cid(fields, "producer_profile_cid")
    is Some(profile) &&
    native_model_output_policy_cid(fields, "producer_schema_cid")
    is Some(schema) &&
    native_model_output_policy_cid(fields, "receiving_binding_cid")
    is Some(receiving_binding) else {
    return None
  }
  let classification : @environment.DataClassification = match
    native_model_http_policy_text(fields, "classification", 16) {
    Some("public") => Public
    Some("internal") => Internal
    Some("confidential") => Confidential
    Some("restricted") => Restricted
    _ => return None
  }
  Some({
    input: input.to_int(),
    stage: stage.to_int(),
    step: step.to_int(),
    task,
    binding,
    profile,
    schema,
    receiving_binding,
    classification,
  })
}

///|
fn admit_native_model_http_output_policy(
  cursor : @decode.Cursor,
  pending : @host.ClientInferPendingEgress,
  settings : NativeLocalConfigurationSelection,
  original : NativeLocalSelectedFile,
  binding : @publication.RunEvidenceValue,
  response : @environment.ModelResponseProfile,
) -> NativeModelHttpPendingEgress? {
  guard @decode.closed_object(cursor, [
      "inputs", "receiving_profile_cid", "receiving_task_cid", "version",
    ])
    is Ok(fields) &&
    native_model_output_policy_cid(fields, "receiving_task_cid")
    is Some(receiving_task) &&
    receiving_task == @environment.model_response_profile_task_cid(response) &&
    native_model_output_policy_cid(fields, "receiving_profile_cid")
    is Some(receiving_profile) &&
    receiving_profile == @environment.model_response_profile_identity(response) &&
    native_model_http_policy_text(fields, "version", 64) ==
    Some("actql-local-model-output-policy/0.1") &&
    @decode.lookup(fields, "inputs") is Some(inputs) &&
    @decode.array_length(inputs) is Some(count) &&
    count > 0 &&
    count == @host.client_infer_pending_egress_result_count(pending) else {
    return None
  }
  let declarations = Array(capacity=count)
  let receiving = @publication.run_evidence_value_identity(binding)
  let mut previous = (-1, -1, -1)
  for index in 0..<count {
    guard @decode.element_at(inputs, index).bind(
        native_model_output_declaration,
      )
      is Some(declaration) &&
      declaration.receiving_binding == receiving &&
      @host.client_infer_pending_egress_accepts_classification(
        pending,
        declaration.classification,
      ) else {
      return None
    }
    let current = (declaration.input, declaration.stage, declaration.step)
    if current <= previous {
      return None
    }
    previous = current
    declarations.push(declaration)
  }
  Some({
    selection: pending,
    settings,
    original,
    receiving_task,
    receiving_profile,
    declarations,
  })
}

///|
fn native_model_http_output_declaration_matches(
  declaration : NativeModelOutputDeclaration,
  installation : NativeModelHttpInstallation,
) -> Bool {
  let task = @environment.model_execution_task(installation.execution)
  let (_, _, task_cid) = @environment.model_task_identity(task)
  let (_, schema) = @environment.model_task_schema_cids(task)
  task_cid == declaration.task &&
  schema == declaration.schema &&
  @publication.run_evidence_value_identity(installation.binding) ==
  declaration.binding &&
  @environment.model_response_profile_identity(installation.response) ==
  declaration.profile
}

///|
/// Before accepting the compiled Run, bind every declaration to an installed
/// producing occurrence and the exact checked receiving import. The applied
/// settlement and live Reader for these pairs are checked at runtime.
pub fn native_model_http_output_policies_match(
  capture : NativeLocalJournalCapture,
  installations : Array[NativeModelHttpInstallation],
  plans : Array[@host.ClientInferPlanGraph],
) -> Bool {
  if installations.length() != plans.length() {
    return false
  }
  for index, installation in installations {
    guard physical_equal(installation.capture, capture) &&
      installation.originals_for(
        @host.client_infer_plan_graph_execution_contract(plans[index]),
      )
      is Some(_) else {
      return false
    }
    guard installation.run_policy.egress is NativeEgressPending(pending) else {
      continue
    }
    if capture.check_original_read_lifetime() is Err(_) ||
      !physical_equal(capture.session.settings, pending.settings) ||
      @environment.model_response_profile_task_cid(installation.response) !=
      pending.receiving_task ||
      @environment.model_response_profile_identity(installation.response) !=
      pending.receiving_profile {
      return false
    }
    let receiving = plans[index]
    if !@host.client_infer_pending_egress_matches(pending.selection, receiving) ||
      @host.check_client_infer_pending_egress_current(pending.selection)
      is Err(_) ||
      !pending.settings.files.any(file => physical_equal(file, pending.original)) {
      return false
    }
    for declaration in pending.declarations {
      let mut matched = false
      for producer_index, producer in plans {
        let (_, stage, step) = @host.client_infer_occurrence_coordinates(
          producer.occurrence,
        )
        if stage != declaration.stage || step != declaration.step {
          continue
        }
        let upstream = installations[producer_index]
        if matched ||
          producer_index >= index ||
          !@host.client_infer_pending_egress_result_matches(
            pending.selection,
            receiving,
            declaration.input,
            producer,
          ) ||
          !native_model_http_output_declaration_matches(declaration, upstream) {
          return false
        }
        matched = true
      }
      if !matched {
        return false
      }
    }
    if capture.check_original_read_lifetime() is Err(_) {
      return false
    }
  }
  true
}

///|
priv struct NativeRetainedModelDependencyPort {
  declaration : NativeModelOutputDeclaration
  producer_index : Int
  producer : NativeClientMockModelWork
  held : @infer.OutputUse
  artifact : @host.ClientWholeLocalResultArtifact
  manifest : @host.ClientWholeLocalResultManifest
  position : Int
  read : @execution.ProducerRead
  mut reader : @host.ClientInferWholeResultReaderOriginal?
}

///|
priv struct NativeRetainedModelDependencies {
  inputs : NativeWholeModelResultInputs
  ports : Array[NativeRetainedModelDependencyPort]
  producers : Array[NativeCompletedModelDependencyOriginal?]
  mut scope : (
    @host.ClientInferCallScope,
    @publication.BoundModelInvocationScope,
  )?
  mut entry_dependency : NativeModelEntryDependency?
  mut egress : @host.ClientInferEgressAdmission?
  mut entered : NativeDependentModelEnteredOriginal?
}

///|
pub fn NativeClientMockModelWork::requires_model_output_dependencies(
  self : Self,
) -> Bool {
  self.provider_role is PortableHttp(http) &&
  http.installation.run_policy.egress is NativeEgressPending(_)
}

///|
fn native_retained_model_dependency_capacity(
  producers : Int,
  ports : Int,
) -> (Int64, Int64)? {
  let producers = producers.to_int64()
  let ports = ports.to_int64()
  guard producers > 0L &&
    ports > 0L &&
    @execution.preparation_array_representation(1L, producers, true)
    is Some(proof_array) &&
    @execution.preparation_array_representation(1L, ports, true)
    is Some(port_array) &&
    @execution.compose_preparation_representation([
      proof_array,
      port_array,
      proof_array,
      port_array,
      port_array,
      {
        record_headers: 20L + 7L * ports + 2L * producers,
        reference_slots: 39L + 23L * ports + 3L * producers,
        scalar_words: 12L + 9L * ports,
        owned_utf16_units: 142L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(bytes) else {
    return None
  }
  let (header, _, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
  @execution.checked_preparation_add_product(
    array_header,
    pointer,
    Int64::max(producers, ports),
  ).map(block => (bytes, Int64::max(block, header + 10L * pointer)))
}

///|
/// Authenticate selected producers at the old HostRead boundary. The
/// complete dependency inventory is held on B only after every original
/// point and every receiving port has been checked.
pub fn NativeClientMockModelWork::read_model_output_dependencies_in_original_read(
  self : Self,
  works : Array[NativeClientMockModelWork],
  completions : Array[@infer.OutputUse?],
  inputs : NativeWholeModelResultInputs,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.installation.run_policy.egress is NativeEgressPending(pending) &&
    !self.closing &&
    !self.closed &&
    !self.open_attempted &&
    !self.advancing &&
    receiver.dependencies is None &&
    works.length() == completions.length() &&
    physical_equal(receiver.installation.capture, self.capture) &&
    physical_equal(self.capture.session.settings, pending.settings) &&
    pending.settings.files.any(file => physical_equal(file, pending.original)) &&
    @host.client_infer_pending_egress_matches(pending.selection, self.graph) &&
    pending.declarations.length() ==
    @host.client_infer_pending_egress_result_count(pending.selection) else {
    return Err(Egress(ForeignOwner))
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let count = pending.declarations.length()
  guard native_retained_model_dependency_capacity(works.length(), count)
    is Some((bytes, block)) else {
    return Err(Original(ConfigurationLimit))
  }
  match self.capture.fund_model_http_material_in_original_read(bytes, block) {
    Ok(_) => ()
    Err(issue) => return Err(Transport(issue))
  }
  let ports : Array[NativeRetainedModelDependencyPort] = Array(capacity=count)
  // Snapshot all participants before observing any output or Reader.
  for declaration in pending.declarations {
    guard inputs.get(declaration.input)
      is Some((ordinal, artifact, manifest, position, read)) &&
      ordinal == declaration.input &&
      self.select_model_output_dependency_original(
        pending, declaration, receiver, works, completions,
      )
      is Some((producer_index, producer, held)) else {
      return Err(Egress(ForeignOwner))
    }
    ports.push({
      declaration,
      producer_index,
      producer,
      held,
      artifact,
      manifest,
      position,
      read,
      reader: None,
    })
  }
  let staged : NativeRetainedModelDependencies = {
    inputs,
    ports,
    producers: Array::make(works.length(), None),
    scope: None,
    entry_dependency: None,
    egress: None,
    entered: None,
  }
  let members : Array[
    (
      @host.ClientInferWholeResultReaderOriginal,
      @host.ClientWholeModelEgressOriginal,
      @environment.DataClassification,
    ),
  ] = Array(capacity=count)
  let limit = Int64::min(self.capture.max_snapshot_bytes, 1048576L).to_int()
  for port in ports {
    let producer_egress = match staged.producers[port.producer_index] {
      Some(original) => {
        let actual = match
          @infer.original_live_whole_model_egress(
            port.held,
            port.producer.compiled,
            port.producer.definition,
            port.producer.graph,
            port.artifact,
            port.manifest,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Egress(issue))
        }
        if @host.client_whole_model_egress_original_classification(actual) !=
          @host.client_whole_model_egress_original_classification(
            original.egress,
          ) {
          return Err(Egress(ChangedObservation))
        }
        actual
      }
      None =>
        match
          port.producer.read_completed_model_dependency_in_original_read(
            port.held,
            limit,
            port.artifact,
            port.manifest,
          ) {
          Err(issue) => return Err(issue)
          Ok(original) => {
            staged.producers[port.producer_index] = Some(original)
            original.egress
          }
        }
    }
    guard @host.prepare_client_infer_whole_result_reader(
        self.graph.occurrence,
        port.declaration.input,
        port.artifact,
        port.manifest,
        port.read,
      )
      is Some(reader) else {
      return Err(Egress(ForeignOwner))
    }
    port.reader = Some(reader)
    members.push((reader, producer_egress, port.declaration.classification))
  }
  let egress = match
    @host.resolve_client_infer_pending_egress(
      pending.selection,
      self.graph,
      members,
      () => self.model_output_dependency_egress_current(staged),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Egress(issue))
  }
  match self.capture.check_current_in_original_read() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  if self.closing ||
    self.closed ||
    self.open_attempted ||
    !native_retained_model_dependencies_match(
      staged, works, completions, inputs,
    ) {
    return Err(Egress(ForeignOwner))
  }
  staged.egress = Some(egress)
  receiver.dependencies = Some(staged)
  Ok(())
}

///|
// Reuse the current observed Account and clock from the receiving Work.
// Each producing Work keeps its original Raw registration and deadline.
fn NativeClientMockModelWork::model_output_dependency_issuers_current(
  self : Self,
  account : @authorization.AdmittedAccountConfiguration,
  at : String,
) -> Bool {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.installation.run_policy.egress is NativeEgressPending(_) else {
    return true
  }
  guard receiver.dependencies is Some(staged) else { return false }
  for item in staged.producers {
    guard item is Some(original) else { continue }
    let producer = original.producer
    guard producer.provider_role is PortableHttp(upstream) &&
      upstream.registration is Some(registration) &&
      producer.admission is Some(dispatch) &&
      @host.client_model_raw_capture_matches(
        registration,
        dispatch,
        original.scope,
      ) &&
      @host.check_client_model_raw_capture_at(registration, account, at)
      is Ok(_) else {
      return false
    }
  }
  true
}

///|
fn NativeClientMockModelWork::model_output_dependency_egress_current(
  self : Self,
  original : NativeRetainedModelDependencies,
) -> Bool {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.dependencies is Some(staged) &&
    physical_equal(staged, original) &&
    self.current_step() is Ok((account, at)) &&
    self.model_output_dependency_issuers_current(account, at) else {
    return false
  }
  staged.ports.all(port => {
    port.reader is Some(reader) &&
    @host.client_infer_whole_result_reader_retained(reader)
  }) &&
  native_retained_model_dependency_producers_current(staged)
}

///|
// Recheck all frozen pairs after the last callback. Earlier pairs may have
// been revoked during a later point read, even if their arrays are unchanged.
fn native_retained_model_dependencies_match(
  staged : NativeRetainedModelDependencies,
  works : Array[NativeClientMockModelWork],
  completions : Array[@infer.OutputUse?],
  inputs : NativeWholeModelResultInputs,
) -> Bool {
  if !physical_equal(staged.inputs, inputs) ||
    works.length() != staged.producers.length() ||
    works.length() != completions.length() {
    return false
  }
  for port in staged.ports {
    let ordinal = port.declaration.input
    guard works.get(port.producer_index) is Some(producer) &&
      physical_equal(producer, port.producer) &&
      completions.get(port.producer_index) is Some(Some(held)) &&
      physical_equal(held, port.held) &&
      inputs.get(ordinal) is Some((slot, artifact, manifest, position, read)) &&
      slot == ordinal &&
      position == port.position &&
      physical_equal(artifact, port.artifact) &&
      physical_equal(manifest, port.manifest) &&
      physical_equal(read, port.read) &&
      port.reader is Some(reader) &&
      @host.client_infer_whole_result_reader_retained(reader) else {
      return false
    }
  }
  native_retained_model_dependency_producers_current(staged)
}

///|
fn native_retained_model_dependency_producers_current(
  staged : NativeRetainedModelDependencies,
) -> Bool {
  for proof in staged.producers {
    guard proof is Some(original) else { continue }
    let producer = original.producer
    let held = original.held
    guard !producer.closing &&
      !producer.closed &&
      !producer.advancing &&
      producer.active is Some(active) &&
      physical_equal(active, held.owner) &&
      producer.scope is Some(scope) &&
      physical_equal(scope, original.scope) &&
      @infer.output(held) is Some(_) &&
      @infer.stopped_attempt_count(active) == Some(original.slots.length()) else {
      return false
    }
    for index, (slot, _, _, _) in original.slots {
      if @infer.stopped_attempt_slot(active, index) != Some(slot) {
        return false
      }
    }
  }
  true
}

///|
/// Lend the exact staged Reader to the existing completed-prefix issuer.
pub fn NativeClientMockModelWork::model_output_dependency_reader(
  self : Self,
  input : Int,
) -> @host.ClientInferWholeResultReaderOriginal? {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.dependencies is Some(staged) else {
    return None
  }
  for port in staged.ports {
    if port.declaration.input == input {
      return port.reader
    }
  }
  None
}

///|
fn native_retained_model_dependency_call_scope_matches(
  staged : NativeRetainedModelDependencies,
  scope : @host.ClientInferCallScope,
) -> Bool {
  @host.client_infer_result_input_inventory_current(scope) &&
  staged.ports.all(port => {
    port.reader is Some(reader) &&
    @host.client_infer_call_scope_matches_whole_result_reader(scope, reader)
  }) &&
  native_retained_model_dependency_producers_current(staged)
}

///|
fn NativeClientMockModelWork::bind_model_output_dependency_scope(
  self : Self,
  scope : @host.ClientInferCallScope,
  bound : @publication.BoundModelInvocationScope,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.installation.run_policy.egress is NativeEgressPending(_) else {
    return Ok(())
  }
  guard receiver.dependencies is Some(staged) &&
    staged.scope is None &&
    staged.entry_dependency is None &&
    native_retained_model_dependency_call_scope_matches(staged, scope) else {
    return Err(Egress(ForeignOwner))
  }
  let ports : Array[NativeModelEntryDependencyPort] = Array(
    capacity=staged.ports.length(),
  )
  for port in staged.ports {
    guard staged.producers.get(port.producer_index) is Some(Some(original)) else {
      return Err(Egress(ForeignOwner))
    }
    ports.push({
      input: port.declaration.input,
      stage: port.declaration.stage,
      step: port.declaration.step,
      artifact: @host.client_whole_local_result_artifact_cid(port.artifact),
      manifest: @host.client_whole_local_result_manifest_cid(port.manifest),
      producer_scope: @publication.model_invocation_scope_cid(original.scope),
    })
  }
  let producers : Array[NativeModelEntryDependencyProducer] = Array(
    capacity=staged.producers.length(),
  )
  for proof in staged.producers {
    if proof is Some(original) {
      producers.push({
        scope: @publication.model_invocation_scope_cid(original.scope),
        slots: original.slots,
      })
    }
  }
  staged.entry_dependency = Some({
    scope: @publication.model_invocation_scope_cid(bound),
    ports,
    producers,
  })
  staged.scope = Some((scope, bound))
  Ok(())
}

///|
// Settlement borrows the same immutable dependency original as Entry. A
// completed transfer does not have to reacquire its live dispatch permission.
fn NativeClientMockModelWork::model_entry_dependency(
  self : Self,
  scope_cid : String,
) -> Result[NativeModelEntryDependency?, NativeClientRunJournalIssue] {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.installation.run_policy.egress is NativeEgressPending(_) else {
    return Ok(None)
  }
  guard receiver.dependencies is Some(staged) &&
    staged.scope is Some((_, bound)) &&
    self.scope is Some(original) &&
    physical_equal(original, bound) &&
    staged.entry_dependency is Some(dependency) &&
    dependency.scope == scope_cid else {
    return Err(ForeignRun)
  }
  Ok(Some(dependency))
}

///|
// The existing dispatch observer calls this before Entry and the final
// transport start. Physical currentness still belongs to the original Read.
fn NativeClientMockModelWork::model_output_dependency_scope_current(
  self : Self,
) -> Bool {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.installation.run_policy.egress is NativeEgressPending(_) else {
    return true
  }
  receiver.dependencies is Some(staged) &&
  staged.scope is Some((scope, bound)) &&
  self.active is Some(active) &&
  @infer.call_scope(active) is Some(actual) &&
  physical_equal(actual, scope) &&
  self.scope is Some(current) &&
  physical_equal(bound, current) &&
  native_retained_model_dependency_call_scope_matches(staged, scope)
}

///|
pub fn NativeClientMockModelWork::check_model_output_dependency_ports(
  self : Self,
  works : Array[NativeClientMockModelWork],
  completions : Array[@infer.OutputUse?],
  inputs : NativeWholeModelResultInputs,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard self.provider_role is PortableHttp(receiver) &&
    receiver.installation.run_policy.egress is NativeEgressPending(_) else {
    return Ok(())
  }
  guard !self.closing &&
    !self.closed &&
    !self.open_attempted &&
    !self.advancing &&
    receiver.dependencies is Some(staged) &&
    native_retained_model_dependencies_match(staged, works, completions, inputs) else {
    return Err(Egress(ForeignOwner))
  }
  Ok(())
}

///|
fn NativeClientMockModelWork::select_model_output_dependency_original(
  self : Self,
  pending : NativeModelHttpPendingEgress,
  declaration : NativeModelOutputDeclaration,
  receiver : NativeClientModelHttpWork,
  works : Array[NativeClientMockModelWork],
  completions : Array[@infer.OutputUse?],
) -> (Int, NativeClientMockModelWork, @infer.OutputUse)? {
  let mut selected = None
  for index, producer in works {
    let (_, stage, step) = @host.client_infer_occurrence_coordinates(
      producer.graph.occurrence,
    )
    if stage != declaration.stage || step != declaration.step {
      continue
    }
    guard selected is None &&
      !physical_equal(producer, self) &&
      !producer.closing &&
      !producer.closed &&
      !producer.advancing &&
      physical_equal(producer.capture, self.capture) &&
      physical_equal(producer.request, self.request) &&
      physical_equal(producer.compiled, self.compiled) &&
      physical_equal(producer.definition, self.definition) &&
      producer.provider_role is PortableHttp(upstream) &&
      physical_equal(upstream.installation.capture, self.capture) &&
      physical_equal(upstream.store, receiver.store) &&
      upstream.output_used &&
      native_model_http_output_declaration_matches(
        declaration,
        upstream.installation,
      ) &&
      @host.client_infer_pending_egress_result_matches(
        pending.selection,
        self.graph,
        declaration.input,
        producer.graph,
      ) &&
      producer.active is Some(active) &&
      completions.get(index) is Some(Some(held)) &&
      physical_equal(held.owner, active) else {
      return None
    }
    selected = Some((index, producer, held))
  }
  selected
}

///|
/// The earlier Work retains Raw metadata only for an already selected
/// downstream use. This flag does not admit the downstream call.
fn native_model_http_output_is_used(
  installation : NativeModelHttpInstallation,
  plan : @host.ClientInferPlanGraph,
  receivers : Array[NativeModelHttpInstallation],
) -> Bool {
  let (_, stage, step) = @host.client_infer_occurrence_coordinates(
    plan.occurrence,
  )
  let task = @environment.model_execution_task(installation.execution)
  let (_, _, task_cid) = @environment.model_task_identity(task)
  let (_, schema) = @environment.model_task_schema_cids(task)
  let binding = @publication.run_evidence_value_identity(installation.binding)
  let profile = @environment.model_response_profile_identity(
    installation.response,
  )
  receivers.any(receiver => {
    physical_equal(receiver.capture, installation.capture) &&
    receiver.run_policy.egress is NativeEgressPending(pending) &&
    pending.declarations.any(declaration => {
      declaration.stage == stage &&
      declaration.step == step &&
      declaration.task == task_cid &&
      declaration.schema == schema &&
      declaration.binding == binding &&
      declaration.profile == profile
    })
  })
}
