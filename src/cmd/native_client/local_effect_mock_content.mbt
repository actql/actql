///|
fn native_mock_effect_record_bytes(
  installation : LocalRunInstallation,
) -> Int raise ClientStop {
  guard installation.store_record_bytes > 0L &&
    installation.store_record_bytes <= 2147483647L else {
    stop("LocalOriginalStoreRecordCodecUnavailable")
  }
  installation.store_record_bytes.to_int()
}

///|
// Open only the Store selected by the same adopted installation, and bind its
// actual location to the accepted Run BEFORE first physical start. The existing
// Store operation retains every partial Root/SQLite/return responsibility.
fn LocalCommandBusinessPreparation::prepare_mock_effect_store(
  self : LocalCommandBusinessPreparation,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    self.original.host is Some(host) &&
    self.original.pair is Some(pair) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  let library = match host.borrow_local_host_sqlite(pair) {
    Ok(value) => value
    Err(issue) => {
      self.original.retain_primary(CommandPair(issue))
      stop("LocalOriginalStoreLibraryUnavailable")
    }
  }
  let managed = match self.capture.managed_root_path_in_original_read() {
    Ok(Some(value)) => value
    Ok(None) => stop("LocalManagedRootRequired")
    Err(issue) => {
      self.original.retain_primary(CommandAdoption(issue))
      stop("LocalManagedRootRequired")
    }
  }
  let store = self.open_store(library, managed, installation)
  let publication = match
    @local_host.install_native_client_cancellation_publication(
      store,
      installation.namespace_id,
      native_mock_effect_record_bytes(installation),
      8192,
      64,
    ) {
    Ok(value) => value
    Err(issue) => {
      self.original.retain_primary(
        CommandBusinessEffectAcceptance(@local_host.Journal(issue)),
      )
      stop("LocalPublicationBindingUnavailable")
    }
  }
  match
    self.capture.bind_installed_publication_in_original_read(
      self.principal,
      self.connection,
      state.first.request,
      publication,
    ) {
    Ok(_) => ()
    Err(issue) => {
      self.original.retain_primary(CommandAdoption(issue))
      stop("LocalPublicationBindingUnavailable")
    }
  }
}

///|
// Existing installed-local policy identities, not grants or evidence that an
// I/O completed. Actual Store persistence/confirmation supplies availability.
fn native_mock_content_binding(
  installation : LocalRunInstallation,
  first : LocalEffectFirstCompilation,
  keyed : @run_host.ClientKeyedAcquisition,
) -> String raise ClientStop {
  let scope = @run_host.client_request_authority_scope_cid(first.request)
  let definition = @decode.open_object(
    local_input_cursor(@publication.publication_contract_json(first.definition)),
  ).unwrap_or_else(() => stop("LocalOriginalContentBindingUnavailable"))
  let until = run_text(definition, "valid_until")
  let facts = @run_host.client_keyed_acquisition_source_evidence_facts(keyed).unwrap_or_else(() => {
      stop("LocalOriginalContentBindingUnavailable")
    },
  )
  let availability = local_project_mock_relation_wire({
    "version": "actql-installed-local-policy/0.1",
    "name": "content-availability",
    "storeAuthorityCid": Json::string(installation.store_authority_cid),
    "runDefinitionCid": Json::string(
      @publication.publication_contract_identity(first.definition),
    ),
    "expiresAt": Json::string(until),
  }).unwrap_or_else(() => stop("LocalOriginalContentBindingUnavailable"))
  let issuer = local_project_mock_relation_wire({
    "version": "actql-installed-local-policy/0.1",
    "name": "content-issuer",
    "storeAuthorityCid": Json::string(installation.store_authority_cid),
    "authorityScopeCid": Json::string(scope),
  }).unwrap_or_else(() => stop("LocalOriginalContentBindingUnavailable"))
  local_project_mock_relation_wire({
    "content_store_id": Json::string(installation.namespace_id),
    "content_store_cid": Json::string(installation.store_authority_cid),
    "workspace_scope_cid": Json::string(scope),
    "storage_scope": "workspace",
    "retention_class": "local-content",
    "expires_at": Json::string(until),
    "availability_evidence_cid": Json::string(
      "sha256:" + @sha.hex(@utf8.encode(availability)),
    ),
    "effective_data_policy_cid": Json::string(facts.source_data_policy_cid),
    "data_classification": Json::string(facts.data_classification),
    "issuer_contract_cid": Json::string(
      "sha256:" + @sha.hex(@utf8.encode(issuer)),
    ),
    "capture_authority_cid": Json::string(scope),
  }).unwrap_or_else(() => stop("LocalOriginalContentBindingUnavailable"))
}

///|
// Retain the actual two-Source prefix and each keyed child on the original Run.
// Counts come from its completed left read. Nominal ResourceRef resolution is
// performed by the SAME file Source; names or observed text cannot replace it.
fn LocalCommandBusinessPreparation::capture_mock_effect_content(
  self : LocalCommandBusinessPreparation,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    business.request_run is Some(run) &&
    business.store is Some(store) &&
    business.model_work.length() == 1 &&
    state.scope is Some(scope) &&
    state.prefix is None &&
    state.lookup is None &&
    self.original.host is Some(arena) &&
    business.execution is Some(physical) &&
    self.original.project is Some(project) &&
    project.mock_declarations is Some(mock) &&
    mock.file_sources is Some(files) &&
    state.first._retained_models.length() == 1 else {
    stop("LocalOriginalModelContentUnavailable")
  }
  let first = state.first
  let limits = first._retained_models[0]._retained_limits
  let compiled = first.model_compiled.unwrap_or_else(() => {
    stop("LocalOriginalModelContentUnavailable")
  })
  let work = business.model_work[0]
  let keyed = self.original.with_business_request(self.capture, () => {
    let keyed = @run_host.select_client_effect_composed_model_keyed_acquisition(
        state._retained_prepared,
        state.graph,
      )
      .unwrap_or_else(() => stop("LocalOriginalModelContentUnavailable"))
      .unwrap_or_else(() => stop("LocalOriginalModelContentUnavailable"))
    let prefix = @local_values.start_installed_original_composed_keyed_input_prefix(
      run,
      scope,
      compiled,
      first.definition,
      state.graph,
      keyed,
      state.captured_inputs,
      limits.input,
      limits.measurement,
    ).unwrap_or_else(() => stop("LocalOriginalModelPrefixUnavailable"))
    state.prefix = Some(prefix)
    keyed
  })
  let authorize = (
    source : LocalProjectMockSourceDeclaration,
    view : @row_host.RowDeclaredView,
  ) => {
    match
      work.require_source_in_original_read(
        self.connection,
        source._retained_connection,
        view.resource,
      ) {
      Ok(_) => ()
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop("LocalSourceAuthorizationUnavailable")
      }
    }
  }
  let prefix = state.prefix.unwrap()
  let mut done = false
  while !done {
    // The prefix may call the original captured producer. Observe ALL actual
    // Source permissions outside the bounded Core batch, not a cached Allow.
    for selected in first._retained_sources {
      match selected._retained_reader {
        Rows(binding) => authorize(selected._retained_source, binding.view)
        Files(file, listing) => {
          let binding = file._retained_listings
            .iter()
            .find_first(pair => physical_equal(pair.0, listing))
            .unwrap_or_else(() => stop("LocalOriginalSourceUnavailable")).1
          authorize(selected._retained_source, binding.listing)
        }
      }
    }
    done = self.original.with_business_request(self.capture, () => {
      match
        @local_values.advance_client_original_composed_keyed_prefix(prefix, 31).unwrap_or_else(() => {
            stop("LocalOriginalModelPrefixUnavailable")
          },
        ) {
        @local_compute.Complete(_, ..) => true
        @local_compute.Continue(..) => false
        _ => stop("LocalOriginalModelPrefixUnavailable")
      }
    })
  }
  let (lookup, rows, binding_wire, response_bytes) = self.original.with_business_request(
    self.capture,
    () => {
      let left = @local_values.complete_client_original_composed_keyed_prefix(
        prefix,
        limits.input.rows.operation_entries,
        limits.identity.wire.max_bytes,
      ).unwrap_or_else(() => stop("LocalOriginalModelKeyedLeftUnavailable"))
      let rows = @run_host.client_keyed_left_read_rows(left).unwrap_or_else(() => {
        stop("LocalOriginalModelKeyedLeftUnavailable")
      })
      let capacity = @sourceviews.keyed_source_capacity(
        @run_host.client_keyed_acquisition_facts(keyed),
      )
      let response_bytes = @compiler_environment.lookup_capacity_response_bytes_per_page(
        capacity,
      )
      guard response_bytes > 0L && response_bytes <= 2147483647L else {
        stop("LocalOriginalModelKeyedCapacityUnavailable")
      }
      // Preserve the original finite whole-input codec policy. A number of
      // future keys times their per-page maxima is neither current material
      // nor an input limit. The SAME lookup grows its actual construction.
      let lookup = @run_host.start_client_original_composed_keyed_lookup_input(
        left,
        limits.identity.wire.max_bytes,
        limits.output_work,
      ).unwrap_or_else(() => stop("LocalOriginalModelKeyedLookupUnavailable"))
      state.lookup = Some(lookup)
      match
        @run_host.prepare_client_keyed_native_left_identity(
          lookup,
          limits.identity.rows,
          limits.output_values,
          limits.identity.wire,
          limits.identity.logical_wire,
          limits.identity.schema,
          limits.identity.work,
          limits.identity.workspace,
        ) {
        Ok(_) => ()
        Err(issue) => {
          self.original.retain_primary(
            CommandBusinessSource(@row_file.Lookup(issue)),
          )
          stop("LocalOriginalLookupLeftIdentityUnavailable")
        }
      }
      (
        lookup,
        rows,
        native_mock_content_binding(installation, first, keyed),
        response_bytes.to_int(),
      )
    },
  )
  self.original.with_business_request(self.capture, () => {
    let profile = @run_host.client_infer_plan_native_keyed_read_profile(
      state.graph,
    ).unwrap_or_else(() => stop("LocalOriginalModelKeyedPlanUnavailable"))
    @run_host.start_client_keyed_lookup_request_plan(
      lookup,
      native_read_profile=Some(profile),
    ).unwrap_or_else(() => stop("LocalOriginalModelKeyedPlanUnavailable"))
  })
  for row in 0..<rows {
    self.original.with_business_request(self.capture, () => {
      let preparation = @run_host.start_client_keyed_lookup_request(lookup, row).unwrap_or_else(() => {
          stop("LocalOriginalModelKeyedRequestUnavailable")
        },
      )
      let mut request = None
      while request is None {
        match
          @run_host.advance_client_keyed_lookup_request(lookup, preparation) {
          @run_host.ClientKeyedRequestContinue(..) => ()
          @run_host.ClientKeyedRequestComplete(value, ..) =>
            request = Some(value)
          _ => stop("LocalOriginalModelKeyedRequestUnavailable")
        }
      }
      @run_host.retain_client_keyed_lookup_planned_request(
        lookup,
        request.unwrap(),
      ).unwrap_or_else(() => stop("LocalOriginalModelKeyedPlanUnavailable"))
    })
  }
  self.original.with_business_request(self.capture, () => {
    @run_host.finish_client_keyed_lookup_request_plan(lookup, 16384, 1024, 20).unwrap_or_else(() => {
        stop("LocalOriginalModelKeyedPlanUnavailable")
      },
    )
    |> ignore
    @run_host.prepare_client_keyed_native_batch_plan(lookup, 16384, 1024, 20).unwrap_or_else(() => {
        stop("LocalOriginalModelKeyedBatchPlanUnavailable")
      },
    )
    |> ignore
  })
  for _ in 0..<rows {
    let (request, file, binding) = self.original.with_business_request(
      self.capture,
      () => {
        let row = @run_host.client_keyed_lookup_next_planned_row(lookup).unwrap_or_else(() => {
            stop("LocalOriginalModelKeyedBatchPlanUnavailable")
          },
        )
        let request = @run_host.client_keyed_lookup_planned_request(lookup, row).unwrap_or_else(() => {
            stop("LocalOriginalModelKeyedRequestUnavailable")
          },
        )
        let original = @run_host.client_keyed_request_value(request, keyed).unwrap_or_else(() => {
            stop("LocalOriginalModelKeyedRequestUnavailable")
          },
        )
        guard @sourceviews.keyed_row_request_field(original, "resource")
          is Some(field) &&
          field.value is @admitted.Reference(reference) else {
          stop("LocalOriginalContentResourceUnavailable")
        }
        let mut selected = None
        for file in files {
          for pair in file._retained_listings {
            let binding = pair.1
            if (file._retained_resolve_identity)(binding, reference) is Some(_) {
              guard selected is None else {
                stop("LocalOriginalContentResourceUnavailable")
              }
              selected = Some((file, binding))
            }
          }
        }
        let (file, binding) = selected.unwrap_or_else(() => {
          stop("LocalOriginalContentResourceUnavailable")
        })
        (request, file, binding)
      },
    )
    authorize(file._retained_original, binding.content)
    let cached = self.original.with_business_request(self.capture, () => {
      @run_host.find_client_keyed_lookup_response(lookup, request).unwrap_or_else(() => {
          stop("LocalOriginalContentCacheUnavailable")
        },
      )
    })
    if cached >= 0 {
      self.original.with_business_request(self.capture, () => {
        @run_host.reuse_client_keyed_lookup_response(lookup, request, cached).unwrap_or_else(() => {
            stop("LocalOriginalContentCacheUnavailable")
          },
        )
        let mut copied = false
        while !copied {
          copied = @run_host.advance_client_keyed_lookup_input(lookup, 31).unwrap_or_else(() => {
              stop("LocalOriginalContentAssemblyUnavailable")
            },
          )
        }
      })
      continue
    }
    let (content, activation) = self.original.with_business_request(
      self.capture,
      () => {
        let physical_provider = binding._retained_provider
        // Keyed limits reuse the admitted file policy. The full typed catalogue
        // still owns the exact request keys, cardinality and response schema.
        let file_limits = local_project_mock_file_limits()
        let read = @local_values.begin_installed_managed_model_keyed_source_read(
          run,
          keyed,
          request,
          file._retained_original._retained_declaration,
          {
            page: {
              max_bytes: response_bytes,
              max_nodes: file_limits.page.max_nodes,
              max_depth: file_limits.page.max_depth,
              max_rows: 1,
            },
            retention: {
              max_nodes: file_limits.page.max_nodes,
              max_depth: file_limits.page.max_depth,
              max_text_bytes: file_limits.page.max_bytes,
              max_work: file_limits.max_work,
            },
            request: {
              max_work: file_limits.max_work,
              max_pairs: file_limits.page.max_nodes,
              values: {
                max_nodes: file_limits.page.max_nodes,
                max_depth: file_limits.page.max_depth,
                max_text_bytes: file_limits.page.max_bytes,
              },
            },
            wire: {
              max_bytes: file_limits.page.max_bytes,
              max_nodes: file_limits.page.max_nodes,
              max_depth: file_limits.page.max_depth,
              max_columns: binding.content.fields.length(),
              max_order_work: file_limits.max_work,
            },
          },
        ).unwrap_or_else(() => stop("LocalOriginalModelKeyedReadUnavailable"))
        state.keyed_reads.push(read)
        let acquisition = @local_values.installed_keyed_source_read_acquisition(
          read,
        ).unwrap_or_else(() => stop("LocalOriginalModelKeyedReadUnavailable"))
        let input = @row_file.prepare_native_relation_file_content_input(
          compiled,
          first.definition,
          keyed,
          request,
          store,
          {
            name: binding._retained_name,
            version: binding._retained_version,
            media_type: binding._retained_media_type,
            path: binding._retained_path,
          },
          binding._retained_content_utf8,
          binding_wire,
          {
            max_bytes: file_limits.page.max_bytes,
            max_nodes: file_limits.page.max_nodes,
            max_depth: file_limits.page.max_depth,
            max_text_units: file_limits.page.max_bytes,
          },
          file_limits.page.max_bytes,
          local_status_watch_now_ffi,
          local_utc_now,
          reference => (file._retained_resolve_identity)(binding, reference),
          read_profile=Some(binding._retained_read_profile),
        ).unwrap_or_else(() => stop("LocalOriginalContentInputUnavailable"))
        let content = match
          @row_file.prepare_native_managed_relation_file_keyed_capture(
            arena,
            physical,
            file._retained_original._retained_declaration,
            binding.content.source_ref,
            read,
            acquisition,
            physical_provider,
            file._retained_issuer,
            "native-mock-content",
            content=Some(input),
          ) {
          Ok(value) => {
            state.sources.push(value)
            value
          }
          Err(issue) => {
            state.source_failures.push(issue)
            self.original.retain_primary(CommandBusinessSource(issue.issue()))
            stop("LocalOriginalContentCaptureUnavailable")
          }
        }
        content
        .bind_lookup_raw_retention(installation.retention)
        .unwrap_or_else(() => stop("LocalOriginalRawRetentionUnavailable"))
        let activation = @run_host.prepare_client_keyed_native_activation(
          lookup,
          request,
          first.request,
          self.host.adoption_cid(),
          local_utc_now(),
          local_status_watch_now_ffi(),
          16384,
          1024,
          20,
        ).unwrap_or_else(() => stop("LocalOriginalLookupActivationUnavailable"))
        (content, activation)
      },
    )
    match work.persist_lookup_activation_in_original_read(activation) {
      Ok(_) => ()
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop("LocalOriginalLookupActivationUnavailable")
      }
    }
    let mut complete = false
    while !complete {
      authorize(file._retained_original, binding.content)
      complete = self.original.with_business_request(self.capture, () => {
        match content.advance(31) {
          Ok(value) => value
          Err(issue) => {
            state.source_failures.push(issue)
            self.original.retain_primary(CommandBusinessSource(issue.issue()))
            stop("LocalOriginalContentAdvanceUnavailable")
          }
        }
      })
    }
    self.original.with_business_request(self.capture, () => {
      let captured = content
        .keyed_capture()
        .unwrap_or_else(() => stop("LocalOriginalContentCaptureUnavailable"))
      @local_values.begin_client_original_keyed_lookup_response(
        keyed, lookup, request, captured,
      ).unwrap_or_else(() => stop("LocalOriginalContentResponseUnavailable"))
      let mut copied = false
      while !copied {
        copied = @run_host.advance_client_keyed_lookup_input(lookup, 31).unwrap_or_else(() => {
            stop("LocalOriginalContentAssemblyUnavailable")
          },
        )
      }
    })
  }
  self.original.with_business_request(self.capture, () => {
    @run_host.finish_client_keyed_lookup_publication_input(
      lookup,
      16384,
      1024,
      20,
      retain_body=true,
    ).unwrap_or_else(() => stop("LocalOriginalContentAssemblyUnavailable"))
    |> ignore
  })
}
