///|
pub enum TemplateConstructionIssue {
  BudgetExceeded
  Capacity(@environment.CapacityIssue)
  Semantics(@references.ProgramSemanticsIssue)
  Definition(@encode.EncodeFailure)
  Orders(Int, @context.Issue)
  Profiles(Int, @context.PipelineOperationProfilesIssue)
  Values(Int, Int, @context.ValuesPublicationIssue)
  Pipeline(Int, @context.PipelineAuthoringIssue)
  Context(Int, @context.PipelineAuthoringContextIssue)
  Publication(Int, @context.AuthoringPublicationIssue)
  Contracts(@context.AuthoringCoreContractIssue)
  ConsumerDeclaration(Int, Int)
}

///|
/// Complete static closure under the originally selected template scope. The
/// retained runtime resource/publication owners still require actual binding
/// and enforcement. This is deliberately not a CheckedProgram or executable
/// Units: it cannot authorize execution, a Submission or automatic resending.
struct TemplateCheckedProgram {
  declarations : TemplateDeclarationPreparation
  capacity : @environment.Capacity
  definition : @references.ProgramDefinition
  contracts : @context.AuthoringCoreContracts
  inputs : Array[InputRequest]
  conditions : Array[TemplateParameterCondition]
  work : Int
  bytes : Int
  nodes : Int
}

///|
priv suberror TemplateStop {
  TemplateStop(TemplateConstructionIssue)
}

///|
fn template_charge(b : IdentityBudget, work : Int) -> Unit raise TemplateStop {
  if work < 0 || work > b.work {
    raise TemplateStop(BudgetExceeded)
  }
  b.work -= work
}

///|
fn template_artifacts(
  b : IdentityBudget,
  bytes : Int,
  nodes : Int,
) -> Unit raise TemplateStop {
  if bytes < 0 || nodes < 0 || bytes > b.bytes || nodes > b.nodes {
    raise TemplateStop(BudgetExceeded)
  }
  b.bytes -= bytes
  b.nodes -= nodes
}

///|
/// Continue genuine shared owners with one cumulative budget. Limits and
/// prefixes come from the retained preparation; callers cannot credit arbitrary
/// work, replace its environment or complete it under a different restriction.
pub fn complete_template_check(
  prepared : TemplateDeclarationPreparation,
) -> Result[TemplateCheckedProgram, TemplateConstructionIssue] {
  let limits = prepared.limits.compilation
  let b : IdentityBudget = {
    work: limits.work - prepared.work,
    bytes: limits.artifacts.bytes - prepared.bytes,
    nodes: limits.artifacts.nodes - prepared.nodes,
    depth: limits.artifacts.depth,
  }
  let environment = prepared.environment
  let source = prepared.source
  let wiring = @context.sourceview_declaration_wiring(source)
  let stages = @results.wiring_source(wiring)
  try {
    template_charge(b, 1)
    let capacity = match
      @environment.read_capacity(environment.wire, {
        max_bytes: limits.policy.bytes.min(b.bytes),
        max_nodes: limits.policy.nodes.min(b.nodes).min(b.work),
        max_depth: limits.policy.depth.min(b.depth),
      }) {
      Ok(value) => value
      Err(issue) => raise TemplateStop(Capacity(issue))
    }
    let (bytes, nodes) = @environment.capacity_usage(capacity)
    template_charge(b, nodes)
    template_artifacts(b, bytes, nodes)
    let usage = @context.sourceview_declaration_usage(source)
    let usage_prefix = @references.usage_work(usage)
    let semantics = match
      @references.prepare_program_semantics(usage, {
        max_work: usage_prefix + b.work,
        max_stages: limits.structure.stages,
        max_hash_bytes: b.bytes.min(b.work),
        max_hash_nodes: b.nodes.min(b.work),
        max_depth: b.depth,
      }) {
      Ok(value) => value
      Err(issue) => raise TemplateStop(Semantics(issue))
    }
    template_charge(
      b,
      @references.program_semantics_work(semantics) - usage_prefix,
    )
    let (bytes, nodes) = @references.program_semantics_hash_usage(semantics)
    template_charge(b, bytes)
    template_charge(b, nodes)
    template_artifacts(b, bytes, nodes)
    let definition = @references.prepare_program_definition(
      semantics,
      b.bytes.min(b.work),
      b.nodes.min(b.work),
      b.depth,
    ) catch {
      issue => raise TemplateStop(Definition(issue))
    }
    let (bytes, nodes) = @references.program_definition_hash_usage(definition)
    template_charge(b, bytes)
    template_charge(b, nodes)
    template_artifacts(b, bytes, nodes)
    let publications : Array[@context.AuthoringPublicationChecks] = []
    let inputs : Array[InputRequest] = []
    let conditions : Array[TemplateParameterCondition] = []
    let declarations = @stages.declarations(stages)
    let count = @parameters.declaration_count(declarations)
    template_charge(b, count)
    let mut remaining_requirements = limits.structure.requirements
    for index in 0..<count {
      let declaration = @parameters.declaration_at(declarations, index).unwrap()
      // Defaults were admitted by the existing declaration owner. They are
      // neither replaced with invented execution values nor missing inputs.
      if !@parameters.has_default(declaration) {
        if remaining_requirements == 0 {
          raise TemplateStop(BudgetExceeded)
        }
        remaining_requirements -= 1
        inputs.push({
          program: prepared.program,
          environment,
          kind: ParameterValue(declaration),
        })
      }
    }
    for stage in 0..<@stages.stage_count(stages) {
      template_charge(b, 1)
      let ports = @results.stage_port_publications(
        @results.wiring_stage_at(wiring, stage).unwrap(),
      )
      let pipeline = @parameter_slots.pipeline(
        @stages.collection(
          @results.stage_port_source(
            @results.wiring_stage_at(wiring, stage).unwrap(),
          ),
        ),
      )
      let profiles = match
        @context.check_pipeline_operation_profiles(
          pipeline,
          environment.operations,
          environment.expressions,
          b.work,
          graph=environment.graph,
        ) {
        Ok(value) => value
        Err(issue) => raise TemplateStop(Profiles(stage, issue))
      }
      let prefix = @context.pipeline_operation_profiles_work(profiles)
      let mut resource_work = prefix
      let mut resource_bytes = 0
      let mut resource_nodes = 0
      let resources : Array[@context.AuthoringValuesPublicationCheck] = []
      for step in 0..<@pipeline.step_count(pipeline) {
        if resource_work == b.work {
          raise TemplateStop(BudgetExceeded)
        }
        resource_work += 1
        if @pipeline.step_at(pipeline, step).unwrap().operation
          is @pipeline.Values(_) {
          let resource = match
            @context.resolve_authoring_values_resources(
              profiles,
              step,
              capacity,
              {
                max_work: prefix + (b.work - resource_work),
                max_values: limits.structure.steps,
                max_payload_bytes: limits.values.text_bytes.min(
                  b.bytes - resource_bytes,
                ),
                max_payload_nodes: limits.values.nodes.min(
                  b.nodes - resource_nodes,
                ),
                max_depth: limits.values.depth.min(b.depth),
                metadata: {
                  max_bytes: b.bytes - resource_bytes,
                  max_nodes: b.nodes - resource_nodes,
                  max_depth: b.depth,
                  max_candidates: 2,
                },
              },
              total_limits=Some({
                max_bytes: b.bytes - resource_bytes,
                max_nodes: b.nodes - resource_nodes,
                max_depth: b.depth,
              }),
            ) {
            Ok(value) => value
            Err(issue) => raise TemplateStop(Values(stage, step, issue))
          }
          resource_work += @context.authoring_values_work(resource) - prefix
          let (payload_bytes, payload_nodes) = @context.authoring_values_payload_usage(
            resource,
          )
          let (metadata_bytes, metadata_nodes) = @context.authoring_values_metadata_usage(
            resource,
          )
          resource_bytes += payload_bytes + metadata_bytes
          resource_nodes += payload_nodes + metadata_nodes
          resources.push(resource)
        }
      }
      // The scan is independent new work. Resource/profile work belongs to
      // close_pipeline_authoring and is counted through that owner once.
      let scan_work = @pipeline.step_count(pipeline)
      template_charge(b, scan_work)
      template_artifacts(b, resource_bytes, resource_nodes)
      let authoring = match
        @context.close_pipeline_authoring(
          profiles,
          capacity,
          resources,
          b.work,
          limits.structure.slots,
          remaining_requirements,
        ) {
        Ok(value) => value
        Err(issue) => raise TemplateStop(Pipeline(stage, issue))
      }
      let runtime = @context.pipeline_authoring_runtime_count(authoring)
      if runtime > remaining_requirements {
        raise TemplateStop(BudgetExceeded)
      }
      remaining_requirements -= runtime
      for index in 0..<runtime {
        template_charge(b, 1)
        let retained = @context.pipeline_authoring_runtime_at(authoring, index).unwrap()
        let requirement = @pipeline.operation_obligations_at(
          retained.owner,
          retained.index,
        ).unwrap()
        if @pipeline.operation_scalar_demand(requirement)
          is Some(@pipeline.SafeInteger(name, minimum~)) {
          let mut selected = None
          for declaration_index in 0..<count {
            template_charge(b, 1)
            let declaration = @parameters.declaration_at(
              declarations, declaration_index,
            ).unwrap()
            if declaration.name == name {
              selected = Some(declaration)
              break
            }
          }
          guard selected is Some(declaration) else {
            raise TemplateStop(ConsumerDeclaration(stage, retained.step))
          }
          conditions.push({
            program: prepared.program,
            declaration,
            stage,
            step: retained.step,
            owner: retained.owner,
            index: retained.index,
            minimum,
            ordinal: conditions.length(),
          })
        }
      }
      let orders = match
        @context.prepare_pipeline_orders(
          @publication.ports_orders(ports),
          max_work=@publication.checked_orders_usage(
              @publication.ports_orders(ports),
            ).0 +
            (b.work - @context.pipeline_authoring_work(authoring)),
          max_text_bytes=limits.traversal.text_bytes,
        ) {
        Ok(value) => value
        Err(issue) => raise TemplateStop(Orders(stage, issue))
      }
      let order_prefix = @publication.checked_orders_usage(
          @publication.ports_orders(ports),
        ).0
      let context = match
        @context.prepare_pipeline_authoring_context(
          authoring,
          orders,
          {
            max_work: order_prefix + b.work,
            max_text_bytes: limits.traversal.text_bytes,
            max_name_bytes: limits.traversal.name_bytes,
            max_input_work: b.work,
            max_operand_work: b.work,
          },
          {
            max_bytes: b.bytes,
            max_nodes: b.nodes.min(b.work),
            max_depth: b.depth,
          },
        ) {
        Ok(value) => value
        Err(issue) => raise TemplateStop(Context(stage, issue))
      }
      let order_count = @context.pipeline_authoring_context_order_count(context)
      if order_count > remaining_requirements {
        raise TemplateStop(BudgetExceeded)
      }
      remaining_requirements -= order_count
      let (_, bytes, nodes) = @context.pipeline_authoring_context_usage(context)
      template_artifacts(b, bytes, nodes)
      let port_prefix = @publication.ports_usage(ports).work
      let publication = match
        @context.prepare_authoring_publications(
          context,
          ports,
          port_prefix + b.work,
          remaining_requirements,
        ) {
        Ok(value) => value
        Err(issue) => raise TemplateStop(Publication(stage, issue))
      }
      template_charge(
        b,
        @context.authoring_publication_work(publication) - port_prefix,
      )
      for index in 0..<@context.authoring_publication_count(publication) {
        let selection = @context.authoring_publication_at(publication, index).unwrap()
        // One port plus its pending total-order obligation and two genuine
        // Host ceilings. Retained row candidates are counted separately.
        let pending = @publication.pending_validations(
          @publication.port_result(
            @context.authoring_publication_port(selection),
          ),
        ).length()
        let used = 3 +
          pending +
          @context.authoring_publication_candidate_count(selection)
        if used > remaining_requirements {
          raise TemplateStop(BudgetExceeded)
        }
        remaining_requirements -= used
      }
      publications.push(publication)
    }
    let contracts = match
      @context.collect_authoring_core_contracts(
        source,
        semantics,
        publications,
        {
          max_work: b.work,
          max_roots: b.work,
          max_bodies: b.work,
          max_edges: b.work,
        },
      ) {
      Ok(value) => value
      Err(issue) => raise TemplateStop(Contracts(issue))
    }
    template_charge(b, @context.authoring_core_contract_usage(contracts).0)
    Ok({
      declarations: prepared,
      capacity,
      definition,
      contracts,
      inputs,
      conditions,
      work: limits.work - b.work,
      bytes: limits.artifacts.bytes - b.bytes,
      nodes: limits.artifacts.nodes - b.nodes,
    })
  } catch {
    TemplateStop(issue) => Err(issue)
  }
}

///|
pub fn template_checked_program(v : TemplateCheckedProgram) -> @syntax.Program {
  v.declarations.program
}

///|
pub fn template_checked_environment(
  v : TemplateCheckedProgram,
) -> CheckEnvironment {
  v.declarations.environment
}

///|
pub fn template_checked_declarations(
  v : TemplateCheckedProgram,
) -> TemplateDeclarationPreparation {
  v.declarations
}

///|
pub fn template_checked_contracts(
  v : TemplateCheckedProgram,
) -> @context.AuthoringCoreContracts {
  v.contracts
}

///|
pub fn template_checked_definition(
  v : TemplateCheckedProgram,
) -> @references.ProgramDefinition {
  v.definition
}

///|
pub fn template_checked_capacity(
  v : TemplateCheckedProgram,
) -> @environment.Capacity {
  v.capacity
}

///|
pub fn template_checked_input_count(v : TemplateCheckedProgram) -> Int {
  v.inputs.length()
}

///|
pub fn template_checked_input_at(
  v : TemplateCheckedProgram,
  index : Int,
) -> InputRequest? {
  v.inputs.get(index)
}

///|
pub fn template_checked_usage(v : TemplateCheckedProgram) -> (Int, Int, Int) {
  (v.work, v.bytes, v.nodes)
}
