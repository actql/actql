///|
// A static command uses the SAME existing Request facility as its compiler,
// without admitting an intent/Run or constructing a module/provider/Engine.
fn LocalCommandPreparationOriginal::prepare_static_request(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  root : String,
  child : @argparse.Matches,
) -> LocalCheckInput raise ClientStop {
  let producer : LocalCommandBusinessInput = {
    root,
    operation: "check",
    arguments: child,
    retained_intent: None,
  }
  command_preparation_result(
    self.prepare_business_request_capacity(capture, producer),
  )
  self.begin_business_request(capture)
  self.with_business_request(capture, () => {
    let format = @frontend.select_format(required(child, "format")).unwrap_or_else(() => {
        stop("UnsupportedLocalSourceFormat")
      },
    )
    // Raw malformed Parameters and Programs belong to the checker report.
    // The Reader observes each generation before its original construction;
    // there is no JSON precheck, whole-intent capture or fixed64KiB support gate.
    let parameters = optional(child, "parameters-file").map(name => {
      self.business_input_text(producer, name, false)
    })
    let declarations = optional(child, "parameter-declarations-file").map(name => {
      self.business_input_text(producer, name, false)
    })
    if declarations is Some(_) && format != Sql && format != Text {
      stop("external declarations require aql-text or sql")
    }
    {
      document: self.business_input_text(
        producer,
        required(child, "program-file"),
        false,
      ),
      format,
      declarations,
      parameters,
    }
  })
}

///|
fn LocalCheckContext::project_request(
  self : LocalCheckContext,
  original : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  input : LocalCheckInput,
  explain : Bool,
  installed_contracts? : @local_values.ClientInstalledSequenceContracts? = None,
  explanation_current? : (() -> Bool)? = None,
) -> String raise ClientStop {
  guard original.business is Some(business) &&
    business.request_input is Some(producer) &&
    business.request_parent is Some(parent) else {
    stop("LocalRequestPreparationUnavailable")
  }
  // Trusted Host metadata stays bound to the original Read/current boundary.
  if !self.current() {
    stop("LocalCheckContextUnavailable")
  }
  if explanation_current is Some(current) && (!explain || !current()) {
    stop("LocalRunStateReadAuthorizationDenied")
  }
  let (publication, publication_wire) = local_command_project_publication(
    self.environment,
    checking=if explain { None } else { Some((capture, self.audience)) },
  )
  let correlation = "corr:" +
    local_check_hex(
      self.crypto
      .random_bytes(16)
      .unwrap_or_else(() => stop("LocalCheckContextUnavailable")),
    )
  let reference = self.reference(
    input,
    visible_publication=if explain { None } else { Some(publication_wire) },
  )
  let kind = if input.format == Json || input.format == Yaml {
    "program"
  } else {
    "text"
  }
  let revision = self.revision(
    if kind == "program" {
      "program"
    } else {
      "source"
    },
    input.document,
  )
  let declarations_revision = if kind == "program" {
    Some(revision)
  } else {
    input.declarations.map(body => self.revision("parameter_declarations", body))
  }
  let parameters_revision = input.parameters.map(body => {
    self.revision("parameters", body)
  })
  let bytes = @utf8.encode(input.document).length()
  let declaration_bytes = input.declarations
    .map(body => @utf8.encode(body).length())
    .unwrap_or(0)
  let parameter_bytes = input.parameters
    .map(body => @utf8.encode(body).length())
    .unwrap_or(0)
  let report = original.with_business_request(capture, () => {
    let checked = @local_values.prepare_request_native_document_check(
      parent,
      producer,
      input.document,
      input.format,
      input.parameters,
      input.declarations,
      self.environment,
      publication,
      static_check=!explain,
    )
    if explain {
      match checked {
        Err(issue) =>
          local_stop_submitted_preparation(@local_host.Request(issue))
        Ok(_) => ()
      }
      let kind = match
        @local_values.finish_request_checked_computation(
          parent,
          producer,
          self.environment,
          publication,
        ) {
        Err(issue) =>
          local_stop_submitted_preparation(@local_host.Request(issue))
        Ok(value) => value
      }
      if explanation_current is Some(_) && kind != @local_values.Effect {
        stop("LocalStaticExplanationNotProjected")
      }
      let view = if kind == @local_values.Effect {
        guard business.request_body is None else {
          stop("LocalBusinessOriginalUnavailable")
        }
        let body = match
          @local_host.borrow_native_client_request_plan_input(parent, producer) {
          Err(issue) => local_stop_submitted_preparation(issue)
          Ok(value) => value
        }
        // Retain before any Graph constructor. Existing command cleanup owns
        // this same token on failure/current loss or an unacknowledged return.
        business.request_body = Some(body)
        guard body is @local_host.Effect(borrow) &&
          @initial_resources.preparation_body_borrow_value(borrow)
          is Some(prepared) else {
          stop("LocalBusinessOriginalUnavailable")
        }
        let occurrences = @run_host.prepared_client_effect_infer_occurrences(
          prepared,
        ).unwrap_or_else(() => stop("LocalOriginalModelUnavailable"))
        let models = if occurrences.is_empty() {
          []
        } else {
          guard original.project is Some(project) &&
            project.mock_declarations is Some(mock) &&
            installed_contracts is Some(contracts) else {
            stop("LocalOriginalModelUnavailable")
          }
          match
            mock.prepare_effect_models(
              parent,
              producer,
              occurrences,
              self.environment,
              contracts,
            ) {
            Ok(value) => value
            Err(issue) => {
              original.retain_primary(CommandBusinessModelGraph(issue))
              stop("LocalOriginalModelGraphUnavailable")
            }
          }
        }
        let infers = models.map(value => value.graph)
        let view = if explanation_current is Some(_) {
          // The original Journal Read is suspended during compiler work.
          // Account calls stay on the entered Read outside this callback.
          let policy = @local_values.client_local_preparation_initial_limits(
            @local_values.client_local_resource_policy(),
          ).unwrap_or_else(() => stop("LocalStaticExplanationUnavailable"))
          match
            @local_values.request_prepared_static_effect_explanation_wire(
              parent,
              producer,
              native_request_manifests,
              65536,
              8192,
              64,
              policy.planning_work,
              infers~,
            ) {
            Err(@local_values.Preparation(issue)) =>
              local_stop_submitted_preparation(
                @local_host.RequestPreparation(issue),
              )
            Err(@local_values.Encoding(_)) =>
              stop("LocalStaticExplanationLimit")
            Err(_) => stop("LocalStaticExplanationUnavailable")
            Ok(value) => value
          }
        } else {
          match
            @local_values.request_prepared_static_plan_view(
              parent,
              producer,
              native_request_manifests,
              65536,
              8192,
              64,
              infers~,
            ) {
            Err(issue) =>
              local_stop_submitted_preparation(@local_host.Request(issue))
            Ok(value) => value
          }
        }
        @local_host.return_native_client_submitted_request_body(body).unwrap_or_else(() => {
            stop("LocalRequestBodyReturnPending")
          },
        )
        |> ignore
        business.request_body = None
        view
      } else {
        match
          @local_values.request_prepared_static_plan_view(
            parent, producer, native_request_manifests, 65536, 8192, 64,
          ) {
          Err(issue) =>
            local_stop_submitted_preparation(@local_host.Request(issue))
          Ok(value) => value
        }
      }
      if explanation_current is Some(_) {
        return view
      }
      return local_explain_reply(
        view,
        producer.arguments.flags.get("json").unwrap_or(false),
        verbose=producer.arguments.flags.get("verbose").unwrap_or(false),
      )
    }
    let wire = match checked {
      Ok(_) =>
        @local_values.project_request_completed_check_outcome(
          parent,
          producer,
          publication_wire,
          reference,
          kind,
          revision,
          bytes,
          declarations_revision,
          declaration_bytes,
          parameters_revision,
          parameter_bytes,
          correlation,
          None,
          original_parameters=input.parameters,
          original_document=if kind == "program" {
            Some(input.document)
          } else {
            None
          },
          document_format=if input.format == Yaml {
            @syntax.Yaml
          } else {
            @syntax.Json
          },
        )
        .unwrap_or_else(() => stop("LocalCheckReportUnavailable"))
        .unwrap_or_else(() => stop("LocalCheckReportUnavailable"))
      Err(issue) => {
        let input_issue = match issue {
          @local_values.Preparation(@local_values.ParameterDeclarations(value)) =>
            Some(@preparation.OriginalParameterDeclarationInput(value))
          @local_values.Preparation(@local_values.ParameterSource(value)) =>
            Some(@preparation.OriginalDeclarationInput(value))
          @local_values.Preparation(@local_values.Parameters(value)) =>
            Some(@preparation.OriginalParametersIssue(value))
          @local_values.Preparation(
            @local_values.ProgramJson(@local_values.Syntax(value))
          ) => Some(@preparation.OriginalProgramIssue(value))
          @local_values.Publication(
            @source_publication.Publication(@source_publication.Declarations)
          ) => Some(@preparation.OriginalDeclarationsIssue)
          _ => None
        }
        match input_issue {
          Some(value) => {
            @local_values.reserve_request_native_static_observation(
              parent,
              producer,
              publication_wire,
              input.document.length().to_int64() +
              input.parameters
              .map(body => body.length().to_int64())
              .unwrap_or(0L) +
              input.declarations
              .map(body => body.length().to_int64())
              .unwrap_or(0L),
            ).unwrap_or_else(() => stop("LocalCheckReportCapacityUnavailable"))
            @preparation.client_program_project_original_input_issue(
              value,
              input.document,
              if input.format == Yaml {
                @syntax.Yaml
              } else {
                @syntax.Json
              },
              reference,
              revision,
              bytes,
              declarations_revision,
              declaration_bytes,
              parameters_revision,
              parameter_bytes,
              correlation,
              structured_program=kind == "program",
            )
          }
          None =>
            @local_values.project_request_check_outcome(
              parent,
              producer,
              issue,
              publication_wire,
              reference,
              kind,
              revision,
              bytes,
              declarations_revision,
              declaration_bytes,
              parameters_revision,
              parameter_bytes,
              correlation,
              None,
              original_parameters=input.parameters,
              original_document=if kind == "program" {
                Some(input.document)
              } else {
                None
              },
              document_format=if input.format == Yaml {
                @syntax.Yaml
              } else {
                @syntax.Json
              },
            )
            .unwrap_or_else(() => stop("LocalCheckReportUnavailable"))
            .unwrap_or_else(() => stop("LocalCheckReportUnavailable"))
        }
      }
    }
    wire
  })
  if !self.current() {
    stop("LocalCheckContextUnavailable")
  }
  if explanation_current is Some(current) && !current() {
    stop("LocalRunStateReadAuthorizationDenied")
  }
  report
}
