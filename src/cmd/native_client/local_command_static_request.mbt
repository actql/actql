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
  let (publication, publication_wire) = local_command_project_publication(
    self.environment,
  )
  let correlation = "corr:" +
    local_check_hex(
      self.crypto
      .random_bytes(16)
      .unwrap_or_else(() => stop("LocalCheckContextUnavailable")),
    )
  let reference = self.reference(input)
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
      let view = @local_values.request_native_static_plan_view(
        parent,
        producer,
        self.environment,
        publication,
        native_request_manifests,
      ).unwrap_or_else(() => stop("LocalStaticCompilationUnavailable"))
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
  report
}
