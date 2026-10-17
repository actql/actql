///|
// These are actual nonempty namespace/Source/Host preparation counters. They
// issue no installed target, Reference, captured-input proof, permit or send.
fn selected_command_source_preparation(
  environment : @check.CheckEnvironment,
  mode : String,
  format : @frontend.Format,
) -> (@frontend.Lowered, CommandTargetPublication) raise {
  let wire = command_source_publication(environment)
  let publication = @source_publication.published_command_targets(
      environment, wire,
    )
    .unwrap()
    .unwrap()
  let selected = resolve_command_target_binding(
    publication,
    command_publication_alias().name,
    1000,
  ).unwrap()
  assert_eq(
    resolved_command_target(selected),
    ("connector://example/mailbox", "command:mail.send.v1"),
  )
  let text = "SELECT 'row-1' AS key, 'original body' AS text |> EFFECT COMMAND mail.send" +
    (if mode == "identifier" { " TARGET 'box-A'" } else { "" }) +
    " ID key INPUT (body = text)"
  let context = @source_publication.bind_published_query_context(
    environment,
    wire,
    None,
  ).unwrap()
  let lowered = @frontend.lower(
    text,
    format,
    Some(context),
    command_targets=Some(publication),
  ).unwrap()
  (lowered, publication)
}

///|
// Closed test diagnostics retain the first typed Owner boundary. They never
// inspect original payloads or make a refusal into execution evidence.
fn selected_command_preparation_issue(
  issue : @publication_host.ClientEffectComputationIssue,
) -> String {
  match issue {
    Syntax(_) => "Syntax"
    Candidate(Computation(cause)) =>
      match cause {
        @check.LocalConstructionFailure::InvalidLimits =>
          "Candidate.Computation.InvalidLimits"
        Program(_) => "Candidate.Computation.Program"
        CapacityInputs(_) => "Candidate.Computation.CapacityInputs"
        Environment(_) => "Candidate.Computation.Environment"
        Source(source) =>
          "Candidate.Computation.Source." +
          match source {
            @check.SourceFailure::DeclarationWorkLimit => "DeclarationWorkLimit"
            CapacityMetadataBudget => "CapacityMetadataBudget"
            UnsupportedBindings(_) => "UnsupportedBindings"
            UnsupportedEffects(_) => "UnsupportedEffects"
            Requests(_) => "Requests"
            RequestForm(_) => "RequestForm"
            Checks(_) => "Checks"
            Identity(_) => "Identity"
            Declarations(_) => "Declarations"
            Registration(_) => "Registration"
            SourceView(_) => "SourceView"
          }
        Closure(_) => "Candidate.Computation.Closure"
        Units(_) => "Candidate.Computation.Units"
        Template(_, _) => "Candidate.Computation.Template"
      }
    Candidate(_) => "Candidate"
    Mapping(_) => "Mapping"
    Static(Results(cause)) => "Static.Results." + @debug.to_string(cause.kind)
    Static(CommandTargets(cause)) =>
      "Static.CommandTargets." + @debug.to_string(cause.kind)
    Static(CommandInputs(cause)) =>
      "Static.CommandInputs." + @debug.to_string(cause.kind)
    Static(_) => "Static"
    Stage(_) => "Stage"
    Graph(cause) => "Graph." + @debug.to_string(cause)
    TargetSelection(_) => "TargetSelection"
  }
}

///|
test "selected short COMMAND Source reaches the actual Host with the same original publication and input occurrence" {
  for mode in ["installation", "identifier"] {
    for format in [@frontend.Sql, @frontend.Text] {
      let environment = command_source_environment(mode)
      let (lowered, publication) = selected_command_source_preparation(
        environment, mode, format,
      )
      let parsed = lowered.program.unwrap()
      let header = store_capture_header(parsed)
      assert_eq(@program.effect_header_command_input_key(header), Some("key"))
      assert_true(
        @program.effect_header_published_command_target(header) is Some(_),
      )
      assert_true(physical_equal(lowered.command_targets.unwrap(), publication))
      let prepared_result = @publication_host.prepare_parsed_client_effect_computation(
        parsed,
        environment,
        None,
        [],
        @publication_host.client_standard_effect_computation_limits(),
        command_targets=lowered.command_targets,
      )
      let prepared = match prepared_result {
        Ok(value) => value
        Err(issue) => fail(selected_command_preparation_issue(issue))
      }
      assert_true(
        physical_equal(
          @publication_host.prepared_client_effect_computation_source(prepared),
          parsed,
        ),
      )
      assert_true(
        physical_equal(
          @publication_host.prepared_client_effect_command_target_publication(
            prepared,
          ).unwrap(),
          publication,
        ),
      )
      // The ordinary structured entrance receives the same retained namespace,
      // without resolving the authoring alias against a new/current Catalog.
      let structured = @publication_host.prepare_client_effect_computation(
        lowered.document,
        lowered.format,
        environment,
        None,
        [],
        @publication_host.client_standard_effect_computation_limits(),
        command_targets=Some(publication),
      ).unwrap()
      assert_true(
        physical_equal(
          @publication_host.prepared_client_effect_command_target_publication(
            structured,
          ).unwrap(),
          publication,
        ),
      )
    }
  }
}

///|
test "selected short COMMAND refuses the equal-CID foreign publication at the actual parsed Host boundary" {
  let environment = command_source_environment("installation")
  let (lowered, original) = selected_command_source_preparation(
    environment,
    "installation",
    @frontend.Sql,
  )
  let foreign_environment = command_source_environment("installation")
  assert_eq(
    @check.checking_environment_cid(environment),
    @check.checking_environment_cid(foreign_environment),
  )
  let foreign = @source_publication.published_command_targets(
      foreign_environment,
      command_source_publication(foreign_environment),
    )
    .unwrap()
    .unwrap()
  assert_false(physical_equal(original, foreign))
  assert_true(
    @publication_host.prepare_parsed_client_effect_computation(
      lowered.program.unwrap(),
      environment,
      None,
      [],
      @publication_host.client_standard_effect_computation_limits(),
      command_targets=Some(foreign),
    )
    is Err(TargetSelection(ForeignEnvironment)),
  )
}
