///|
// Caller-held public evidence and the original bounded export/issuance
// continuations. They reuse the same captured Run and grant no durable save,
// waiting, approval, mutation or physical cleanup acknowledgement.
priv struct LocalNativeMockEffectComputation {
  outputs : Array[@run_host.PublicationOutputExport]
  managed_outputs : Array[@local_values.LocalValuesResultExport]
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
  snapshots : Array[@publication.CapturedResultSnapshot]
  mut _retained_manifest : @publication.PublicationContract?
  mut _retained_receipt : @publication.PublicationContract?
  mut issuer : @publication.CapturedRunIssuancePreparation?
  mut _retained_captured : @publication.PublicationContract?
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_computation(
  self : Self,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    state.effect_capture is Some(captured) &&
    state.proposals is Some(proposals) &&
    proposals.materials is Some(materials) &&
    proposals.acquired is Some(acquired) &&
    state.preview is Some(preview) &&
    preview._retained_dependency_inventory is Some(inventory) &&
    state.suffix is Some(execution) &&
    proposals.construction is Some(construction) &&
    state.computation is None else {
    stop("LocalOriginalEffectComputationUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let limits = state.first._retained_models[0]._retained_limits
    let wire = limits.identity.wire
    let policy = @run_host.client_standard_effect_computation_limits()
    let max_bytes = native_mock_effect_record_bytes(installation)
    let max_nodes = policy.effects.max_admission_nodes
    let max_depth = policy.effects.max_admission_depth
    let held : LocalNativeMockEffectComputation = {
      outputs: [],
      managed_outputs: [],
      definitions: [],
      artifacts: [],
      snapshots: [],
      _retained_manifest: None,
      _retained_receipt: None,
      issuer: None,
      _retained_captured: None,
    }
    state.computation = Some(held)
    let run = @strategy.captured_effect_run_dag(captured)
    // Keep every checked Named Result, in original graph order. Each wrapper
    // retains its own captured pin and any managed bridge before further work.
    let bridge = proposals.bridge_limits
    let row = bridge.row
    for
      index in 0..<@strategy.graph_result_count(
        @strategy.captured_dag_graph(run),
      ) {
      let output = execution
        .prepare_captured_result_export(
          run,
          index,
          row,
          bridge.entries,
          bridge.name_bytes,
          {
            max_result_fields: wire.max_columns,
            max_result_mapping_work: wire.max_order_work,
            max_result_order_work: wire.max_order_work,
            max_result_workspace_entries: limits.output_workspace,
            max_rows: limits.output_rows,
            values: limits.output_values,
            payload_wire: wire,
            logical_wire: limits.identity.logical_wire,
            schema: limits.identity.schema,
            max_batch_bytes: Int::min(wire.max_bytes, 16384),
          },
          before_row=Some(text => {
            construction.prepare_row(self.original, text, row)
          }),
        )
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::ManagedPublicExport(issue)
        })
        .native_effect_proposal(self.original)
      held.managed_outputs.push(output)
      held.outputs.push(output.output_export())
    }
    for index, output in held.outputs {
      // Public Named Results include the complete Model Unit, not only the
      // subset consumed by an Effect member. Select by the same checked
      // occurrence; neither equal rows nor an export failure chooses a source.
      let consumed = proposals.members
        .iter()
        .find_first(entry => {
          entry._retained_artifact
          .map(artifact => {
            @run_host.client_effect_local_result_artifact_matches_public_result(
              materials.prepared,
              proposals.inputs,
              artifact,
              index,
            )
          })
          .unwrap_or(false)
        })
        .bind(entry => entry._retained_artifact)
      let original = match consumed {
        Some(artifact) => artifact
        None =>
          proposals.unit_results
          .iter()
          .find_first(entry => {
            entry.artifact
            .map(artifact => {
              @run_host.client_effect_local_result_artifact_matches_public_result(
                materials.prepared,
                proposals.inputs,
                artifact,
                index,
              )
            })
            .unwrap_or(false)
          })
          .bind(entry => entry.artifact)
          .unwrap_or_else(() => {
            stop("LocalOriginalEffectComputationResultUnavailable")
          })
      }
      let (computation, relations, scope, data_policy, authority) = @run_host.client_effect_model_public_result_evidence_refs(
          materials,
          proposals.inputs,
          acquired,
          original,
          index,
          preview._retained_invocation,
          preview._retained_observation,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Artifact(issue))
        .native_effect_proposal(self.original)
      while true {
        match
          output
          .next()
          .map_err(issue => {
            LocalNativeMockEffectProposalIssue::PublicExport(issue)
          })
          .native_effect_proposal(self.original) {
          Some(_) => ()
          None => break
        }
      }
      output
      .finish()
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal(self.original)
      |> ignore
      output
      .issue_result_evidence(
        computation, relations, scope, data_policy, authority, max_bytes, max_nodes,
        max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicExport(issue))
      .native_effect_proposal(self.original)
      |> ignore
      held.definitions.push(
        output
        .definition()
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PublicExport(issue)
        })
        .native_effect_proposal(self.original),
      )
      held.artifacts.push(
        output
        .issue_artifact(
          preview._retained_invocation,
          @run_host.client_effect_local_result_retention(original),
          max_bytes,
          max_nodes,
          max_depth,
        )
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PublicExport(issue)
        })
        .native_effect_proposal(self.original),
      )
      held.snapshots.push(
        output
        .admit_captured_snapshot(max_bytes, max_nodes, max_depth)
        .map_err(issue => {
          LocalNativeMockEffectProposalIssue::PublicExport(issue)
        })
        .native_effect_proposal(self.original),
      )
    }
    let manifest = @publication.issue_result_manifest(
        materials.run_definition,
        preview._retained_invocation,
        held.definitions,
        held.artifacts,
        max_bytes,
        max_nodes,
        max_depth,
      )
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::PublicManifest(issue)
      })
      .native_effect_proposal(self.original)
    held._retained_manifest = Some(manifest)
    let journal = @run_host.restore_client_effect_run_normalization(materials)
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::PublicNormalization(issue)
      })
      .native_effect_proposal(self.original)
    // This existing Owner admits only the original finite empty binding
    // inventory and matches the actual compiler Template before Receipt use.
    @run_host.client_effect_run_receipt_bindings(
      materials, max_bytes, max_nodes, max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::PublicBindings(issue))
    .native_effect_proposal(self.original)
    |> ignore
    let receipt = @publication.issue_effect_free_run_receipt(
        @run_host.client_effect_allowed_run_admission(materials.allowed),
        materials.run_definition,
        preview._retained_invocation,
        preview._retained_observation,
        held.definitions,
        held.artifacts,
        manifest,
        journal,
        [],
        [],
        preview._retained_source_observations,
        preview._retained_models,
        [],
        max_bytes,
        max_nodes,
        max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicReceipt(issue))
      .native_effect_proposal(self.original)
    held._retained_receipt = Some(receipt)
    let issuer = @run_host.prepare_client_effect_captured_run(
        materials,
        proposals.inputs,
        preview.inputs,
        preview.proofs,
        preview._retained_invocation,
        held.definitions,
        held.artifacts,
        manifest,
        receipt,
        held.snapshots,
        preview._retained_captured_sources,
        preview._retained_local_sources,
        inventory,
        preview._retained_authoring,
        wire.max_columns,
        policy.effects.max_work,
        max_bytes,
        max_nodes,
        max_depth,
        limits.output_workspace,
        models=preview._retained_models,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::PublicCapture(issue))
      .native_effect_proposal(self.original)
    held.issuer = Some(issuer)
    while !issuer
          .advance(64)
          .map_err(issue => {
            LocalNativeMockEffectProposalIssue::CapturedSource(issue)
          })
          .native_effect_proposal(self.original).0 {
      ()
    }
    held._retained_captured = Some(
      issuer
      .finish_retained()
      .map_err(issue => {
        LocalNativeMockEffectProposalIssue::CapturedSource(issue)
      })
      .native_effect_proposal(self.original),
    )
  })
}
