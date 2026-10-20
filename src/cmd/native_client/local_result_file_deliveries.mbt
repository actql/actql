///|
fn[T] local_result_read_value(
  value : Result[T, @local_host.NativeLocalReadBindingIssue],
) -> T raise ClientStop {
  match value {
    Ok(value) => value
    Err(issue) => stop(local_read_issue(issue))
  }
}

///|
// Private stable correlation, not a new identity domain or authority. The
// existing attempt Owner compares the actual saved request and durable facts.
fn local_result_file_attempt(
  selected : LocalOriginalRunSelection,
  principal : String,
  purpose : String,
  result_name : String,
  destination : LocalResultFileSelection,
) -> String raise ClientStop {
  let original_request = @run_host.client_request_identity_record_wire(
    selected.request,
  ).unwrap_or_else(() => stop("LocalOriginalRunReferenceMismatch"))
  let body = encode_request_json(
    Json::array([
      Json::string(original_request),
      Json::string(selected.namespace_id),
      Json::string(selected.run_definition_cid),
      Json::string(principal),
      Json::string(purpose),
      Json::string(result_name),
      Json::string(destination.format),
      Json::string(destination.path),
    ]),
    8192,
  )
  "file-" + @sha.hex(@sha.digest(@utf8.encode(body)))
}

///|
// Each delivery uses the same saved Run and Store, but its own independently
// selected File binding and actual exclusive Writer. Completed attempts are
// verified, never reopened; incomplete/Unknown attempts are never resent.
fn local_result_file_deliveries(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  child : @argparse.Matches,
  actual : LocalCommandResultOriginal,
  selected : LocalOriginalRunSelection,
  names : String,
  delivery : LocalResultDeliverySelection,
) -> String raise ClientStop {
  guard actual.owner.business is Some(business) && !delivery.files.is_empty() else {
    stop("LocalReadOriginalCustodyUnavailable")
  }
  // Resolve the entire name selection from the original Manifest before any
  // output acquisition. Neither current configuration nor policy supplies it.
  let selected_names = delivery.files.map(destination => {
    local_result_name(names, destination.result_name)
  })
  let receipts : Array[String] = []
  let reports : Array[Json] = []
  let mut failure : String? = None
  for index in 0..<delivery.files.length() {
    let destination = delivery.files[index]
    let result_name = selected_names[index]
    let mut attempt_id = ""
    let mut result_cid = ""
    let outcome = try {
      let binding = if index == 0 {
        actual.binding
      } else {
        actual.capture.bind_result_file_read_policy_for_run_in_original_read(
          actual.policy,
          actual.original.reference(),
          actual.original.request(),
          @env.now().to_double(),
          "file-read.json",
        )
        |> local_result_read_value
      }
      let parameters = binding.disclosure_parameters()
        |> local_result_read_value
      attempt_id = local_result_file_attempt(
        selected,
        settings.principal,
        parameters.purpose,
        result_name,
        destination,
      )
      let request : @local_result.NativeResultAccessRequest = {
        namespace_id: selected.namespace_id,
        authority_scope_cid: actual.scope,
        run_definition_cid: selected.run_definition_cid,
        principal_id: settings.principal,
        purpose: parameters.purpose,
        result_name,
        format: destination.format,
        attempt_id,
      }
      let current = () => {
        local_delivery_lookup_allowed(
          host,
          settings,
          crypto,
          actual.scope,
          result_name,
          capture=Some(actual.capture),
        )
      }
      if !current() {
        stop("LocalReadAuthorizationDenied")
      }
      // Public request metadata is taken from this same committed Artifact,
      // never a current declaration or a placeholder inferred from the path.
      let committed = match
        actual.store.resolve_committed_result(
          selected.namespace_id,
          actual.scope,
          selected.run_definition_cid,
          result_name,
          65536,
          8192,
          64,
        ) {
        Ok(Some(value)) => value
        Ok(None) => stop("LocalResultPublicationUnavailable")
        Err(_) => stop("LocalResultPublicationObservationUnavailable")
      }
      if !current() {
        stop("LocalReadAuthorizationDenied")
      }
      result_cid = committed.read.result_artifact_cid
      Ok(
        local_admitted_result_stream(
          host~,
          settings~,
          selected~,
          binding~,
          request~,
          scope=actual.scope,
          purpose=parameters.purpose,
          result_name~,
          format=destination.format,
          attempt_id~,
          max_output=parameters.max_output_bytes,
          current~,
          store=actual.store,
          retained=Some(business),
          captured_selection=Some(actual.original),
          file_destination=Some(destination),
        ),
      )
    } catch {
      ClientStop(issue) => Err(issue)
    }
    // No next destination can bypass an outstanding same-session/Store return.
    // A failed cleanup keeps all originals and stops before any further open.
    if business.close_result_children_after_return() is Err(cleanup) {
      let pending = "LocalResultCleanupPending: " +
        command_preparation_cleanup_kind(cleanup)
      stop(
        match outcome {
          Ok(_) => pending
          Err(primary) => primary + "; cleanup=" + pending
        },
      )
    }
    let fields : Map[String, Json] = Map::from_array([
      (
        "delivery_id",
        Json::string(
          if attempt_id.is_empty() {
            "requested-" + index.to_string()
          } else {
            attempt_id
          },
        ),
      ),
      ("run_id", Json::string(required(child, "run"))),
      (
        "request",
        Json::object(
          Map::from_array([
            ("result", Json::string(result_name)),
            ("result_cid", Json::string(result_cid)),
            ("format", Json::string(destination.format)),
            ("path", Json::string(destination.path)),
          ]),
        ),
      ),
      ("attempt", Json::number(if attempt_id.is_empty() { 0 } else { 1 })),
    ])
    match outcome {
      Ok(wire) => {
        let receipt = @publication.admit_publication_contract(
          "result_delivery_receipt", wire, 65536, 8192, 64,
        ).unwrap_or_else(() => stop("LocalResultReceiptUnavailable"))
        let receipt_json = local_delivery_contract_json(receipt)
        guard receipt_json is Object(receipt_fields) &&
          json_text(receipt_fields, "result_artifact_cid") == Some(result_cid) else {
          stop("LocalResultReceiptUnavailable")
        }
        guard fields.get("request") is Some(Object(request_fields)) else {
          stop("LocalResultReceiptUnavailable")
        }
        request_fields["result_cid"] = Json::string(result_cid)
        fields["status"] = Json::string("delivered")
        fields["receipt"] = receipt_json
        receipts.push(wire)
      }
      Err(issue) => {
        // A caller error cannot turn an unconfirmed physical operation into a
        // failed-with-no-exposure assertion. Keep the unresolved presentation.
        failure = Some(issue)
        fields["status"] = Json::string("pending")
        fields["error"] = Json::object(
          Map::from_array([
            ("code", Json::string("LocalResultDeliveryUnconfirmed")),
            ("message", Json::string(issue)),
          ]),
        )
      }
    }
    reports.push(Json::object(fields))
    if failure is Some(_) {
      break
    }
  }
  if delivery.receipt is Some(path) &&
    (delivery.files.length() > 1 || !receipts.is_empty()) {
    // Requested cardinality determines the container even after partial
    // failure. Export never retries or resends any completed payload.
    let exported = try {
      let wire = @run_host.client_result_delivery_receipt_file(
        receipts,
        delivery.files.length(),
      ).unwrap_or_else(() => stop("LocalResultReceiptUnavailable"))
      local_write_result_receipt(path, wire, crypto)
      Ok(())
    } catch {
      ClientStop(issue) => Err(issue)
    }
    if exported is Err(issue) {
      // Preserve an earlier delivery refusal as the primary command failure.
      // Payloads already delivered stay delivered even when export fails.
      stop(
        match failure {
          None => issue
          Some(primary) => primary + "; receipt-export=" + issue
        },
      )
    }
  }
  command_result_delivery_failed.val = failure is Some(_)
  if delivery.json {
    let saved = local_result_host_value(
      actual.capture.lookup_submitted_run_state_by_id_in_original_read(
        settings.principal,
        settings.connection,
        required(child, "run"),
        @env.now().to_double(),
      ),
      "saved Run after delivery",
    ).unwrap_or_else(() => stop("LocalOriginalRunStateUnavailable"))
    let state = @json.parse(saved.state().wire()) catch {
      _ => stop("LocalOriginalRunStateUnavailable")
    }
    return encode_request_json(
      Json::object(
        Map::from_array([
          ("version", Json::string("actql-cli-run-response/0.1")),
          ("run", state),
          (
            "delivery_status",
            Json::string(
              if failure is Some(_) {
                "pending"
              } else {
                "delivered"
              },
            ),
          ),
          ("deliveries", Json::array(reports)),
        ]),
      ),
      1048576,
    )
  }
  if failure is Some(issue) {
    stop(issue)
  }
  ""
}
