///|
priv suberror CommandStop {
  CommandStop(String)
}

///|
fn[T] stop(message : String) -> T raise CommandStop {
  raise CommandStop(message)
}

///|
fn option(
  matches : @argparse.Matches,
  name : String,
) -> String raise CommandStop {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => stop("missing or repeated option --" + name)
  }
}

///|
fn int_option(
  matches : @argparse.Matches,
  name : String,
) -> Int raise CommandStop {
  let value : Int = @string.from_str(option(matches, name)) catch {
    _ => stop("invalid integer option --" + name)
  }
  value
}

///|
fn int64_option(
  matches : @argparse.Matches,
  name : String,
) -> Int64 raise CommandStop {
  let value : Int64 = @string.from_str(option(matches, name)) catch {
    _ => stop("invalid integer option --" + name)
  }
  value
}

///|
fn read_text(
  root : String,
  name : String,
  max_bytes : Int64,
) -> String raise CommandStop {
  match @bounded_files.read_bounded_text_file(root, name, max_bytes) {
    Ok(value) => value
    Err(_) => stop("failed to read " + name)
  }
}

///|
fn admit_dispatch(
  body : String,
  cid : String,
) -> @remote.DispatchRequest raise CommandStop {
  match @remote.admit_dispatch_request_json(body, cid) {
    Ok(value) => value
    Err(_) => stop("dispatch request admission failed")
  }
}

///|
fn coordinator_issue(issue : @journal.NativeRemoteJournalIssue) -> String {
  match issue {
    @journal.UnsupportedTarget => "Coordinator journal is unsupported"
    @journal.Closed => "Coordinator journal is closed"
    @journal.MissingDispatch => "Coordinator dispatch is missing"
    @journal.StateCollision => "Coordinator journal state collided"
    @journal.StaleSiteBinding => "Coordinator Site binding is stale"
    @journal.Protocol(@remote.ObservationHistoryRequired) =>
      "Coordinator journal observation history required"
    @journal.Protocol(_) => "Coordinator protocol state was rejected"
    @journal.Physical(_) => "Coordinator journal persistence failed"
    @journal.InitializationCleanupPending(_, _, _) =>
      "Coordinator journal inspection cleanup pending"
  }
}

///|
fn reply(
  server : @https.NativeHttpsServer,
  request : @https.NativeHttpsRequest,
  status : Int,
  body : String,
) -> Unit raise CommandStop {
  match
    server.respond(request, status, "application/json", @utf8.encode(body)) {
    Ok(_) => ()
    Err(_) => stop("Coordinator response failed")
  }
}

///|
fn stored_text(
  database : @sqlite.Database,
  key : String,
) -> Result[String?, String] {
  match database.read("native_coordinator_output", key) {
    Ok(value) => {
      let body = @utf8.decode(value.body) catch {
        _ => return Err("Coordinator output journal contains invalid UTF-8")
      }
      Ok(Some(body))
    }
    Err(@sqlite.NotFound) => Ok(None)
    Err(_) => Err("Coordinator output journal read failed")
  }
}

///|
fn store_exact_text(
  database : @sqlite.Database,
  key : String,
  body : String,
) -> Result[Unit, String] {
  let encoded = @utf8.encode(body)
  match database.insert("native_coordinator_output", key, encoded) {
    Ok(0L) => Ok(())
    Ok(_) => Err("Coordinator output journal revision is invalid")
    Err(@sqlite.Collision) =>
      match database.read("native_coordinator_output", key) {
        Ok(value) if value.revision == 0L && value.body == encoded => Ok(())
        _ => Err("Coordinator output journal state collided")
      }
    Err(_) => Err("Coordinator output journal write failed")
  }
}

///|
fn commit_observation(
  coordinator : @journal.CoordinatorJournal,
  record : @remote.CoordinatorDispatchIntentRecord,
  response : @remote.RemoteDispatchResponse,
) -> Result[Unit, String] {
  let transition = match
    @remote.prepare_coordinator_response_observation(record, response) {
    Ok(value) => value
    Err(_) => return Err("Coordinator observation was rejected")
  }
  match
    coordinator.commit_transition(
      transition,
      evidence=@remote.remote_dispatch_response_evidence(response),
      subject=@remote.remote_dispatch_response_subject(response),
      measurement=@remote.remote_dispatch_response_measurement(response),
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(coordinator_issue(issue))
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-remote-coordinator",
    about="Coordinate one durable outbound ActQL Site execution",
    version="0.1",
    options=[
      @argparse.OptionArg("sqlite-library", required=true),
      @argparse.OptionArg("journal", required=true),
      @argparse.OptionArg("output-journal", required=true),
      @argparse.OptionArg("contract-root", required=true),
      @argparse.OptionArg("dispatch-file", required=true),
      @argparse.OptionArg("dispatch-cid", required=true),
      @argparse.OptionArg("input-binding-file", required=true),
      @argparse.OptionArg("output-envelope-file", required=true),
      @argparse.OptionArg("authority", required=true),
      @argparse.OptionArg("site-fingerprint", required=true),
      @argparse.OptionArg("admin-fingerprint", required=true),
      @argparse.OptionArg("host", required=true),
      @argparse.OptionArg("port", required=true),
      @argparse.OptionArg("cert", required=true),
      @argparse.OptionArg("key", required=true),
      @argparse.OptionArg("ca", required=true),
      @argparse.OptionArg("max-record-bytes", default_values=["3145728"]),
      @argparse.OptionArg("max-request-bytes", default_values=["3145728"]),
      @argparse.OptionArg("max-response-bytes", default_values=["1179648"]),
      @argparse.OptionArg("max-pending", default_values=["32"]),
      @argparse.OptionArg("max-chunks", default_values=["1024"]),
      @argparse.OptionArg("max-manifest-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-referenced-bytes", default_values=["268435456"]),
      @argparse.OptionArg("mode", default_values=["run"]),
    ],
  )
}

///|
fn execute_checked(matches : @argparse.Matches) -> Unit raise CommandStop {
  let max_record_bytes = int64_option(matches, "max-record-bytes")
  let max_request_bytes = int_option(matches, "max-request-bytes")
  let max_response_bytes = int_option(matches, "max-response-bytes")
  let max_pending = int_option(matches, "max-pending")
  let max_chunks = int_option(matches, "max-chunks")
  let max_manifest_bytes = int_option(matches, "max-manifest-bytes")
  let max_referenced_bytes = int64_option(matches, "max-referenced-bytes")
  let port = int_option(matches, "port")
  if max_record_bytes < 1L ||
    max_request_bytes < 1 ||
    max_response_bytes < 1 ||
    max_pending < 1 ||
    max_chunks < 1 ||
    max_manifest_bytes < 1 ||
    max_referenced_bytes < 0L ||
    port < 0 ||
    port > 65535 {
    stop("invalid Coordinator limits")
  }
  let contract_root = option(matches, "contract-root")
  let dispatch_body = read_text(
    contract_root,
    option(matches, "dispatch-file"),
    max_record_bytes,
  )
  let dispatch = admit_dispatch(dispatch_body, option(matches, "dispatch-cid"))
  let input_binding_body = read_text(
    contract_root,
    option(matches, "input-binding-file"),
    max_record_bytes,
  )
  let input_binding = match
    @remote.prepare_remote_input_binding(
      input_binding_body,
      max_record_bytes.to_int(),
    ) {
    Ok(value) => value
    Err(_) => stop("input binding admission failed")
  }
  if !@remote.remote_input_binding_matches_dispatch(input_binding, dispatch) {
    stop("input binding does not match dispatch")
  }
  let output_envelope = read_text(
    contract_root,
    option(matches, "output-envelope-file"),
    max_record_bytes,
  )
  let output = match @remote.admit_remote_poll_output_json(output_envelope) {
    Ok(value) => value
    Err(_) => stop("output envelope admission failed")
  }
  if @remote.dispatch_request_identity(
      @remote.remote_poll_output_request(output),
    ) !=
    @remote.dispatch_request_identity(dispatch) {
    stop("output envelope does not match dispatch")
  }
  let intent = @remote.remote_poll_output_intent(output)
  let poll_dispatch = match
    @remote.remote_poll_dispatch_json(dispatch, input_binding) {
    Ok(value) => value
    Err(_) => stop("dispatch poll envelope failed")
  }
  let poll_query = match @remote.remote_poll_query_json(dispatch) {
    Ok(value) => value
    Err(_) => stop("query poll envelope failed")
  }
  let poll_plan = match @remote.remote_poll_output_plan_json(dispatch, intent) {
    Ok(value) => value
    Err(_) => stop("output plan poll envelope failed")
  }
  let poll_output = match @remote.remote_poll_output_json(dispatch, intent) {
    Ok(value) => value
    Err(_) => stop("output poll envelope failed")
  }
  let poll_release = match @remote.remote_poll_release_json(dispatch) {
    Ok(value) => value
    Err(_) => stop("release poll envelope failed")
  }
  let library = match @sqlite.load_library(option(matches, "sqlite-library")) {
    Ok(value) => value
    Err(_) => stop("SQLite library load failed")
  }
  let control = match
    @remote.create_coordinator_dispatch_journal(option(matches, "authority")) {
    Ok(value) => value
    Err(_) => stop("Coordinator authority is invalid")
  }
  let coordinator = match
    @journal.open_coordinator_journal(
      library,
      option(matches, "journal"),
      max_record_bytes,
      control,
    ) {
    Ok(value) => value
    Err(issue) => stop(coordinator_issue(issue))
  }
  let output_database = match
    library.open_database(option(matches, "output-journal"), max_record_bytes) {
    Ok(value) => value
    Err(_) => {
      ignore(coordinator.close())
      stop("Coordinator output journal open failed")
    }
  }
  let record = match coordinator.accept(dispatch) {
    Ok((_, value)) => value
    Err(issue) => {
      output_database.close()
      ignore(coordinator.close())
      stop(coordinator_issue(issue))
    }
  }
  let recovered = match coordinator.recover_after("") {
    Ok(Some(value)) => value
    _ => {
      output_database.close()
      ignore(coordinator.close())
      stop("Coordinator dispatch recovery failed")
    }
  }
  let subject = [@journal.recovered_coordinator_dispatch_subject(recovered)]
  let output_record : Array[@remote.CoordinatorOutputRecord?] = [None]
  let plan_body : Array[String?] = [None]
  match stored_text(output_database, "plan") {
    Ok(Some(body)) => {
      let observed_subject = match subject[0] {
        Some(value) => value
        None => stop("durable output plan has no dispatch subject")
      }
      let plan = match
        @remote.admit_remote_output_plan_json(
          body, output, observed_subject, max_chunks, max_manifest_bytes, max_referenced_bytes,
        ) {
        Ok(value) => value
        Err(_) => stop("durable output plan admission failed")
      }
      let admission = match
        @remote.prepare_coordinator_output_intent(
          control,
          output,
          @remote.remote_output_plan_payload_request(plan),
          @remote.remote_output_plan_transfer_request(plan),
        ) {
        Ok(value) => value
        Err(_) => stop("durable output intent recovery failed")
      }
      output_record[0] = match
        @remote.commit_coordinator_output_intent(admission, true) {
        Ok((_, value)) => Some(value)
        Err(_) => stop("durable output intent commit failed")
      }
      plan_body[0] = Some(body)
    }
    Ok(None) => ()
    Err(issue) => stop(issue)
  }
  let output_result_body = [stored_text(output_database, "result")]
  match output_result_body[0] {
    Ok(Some(body)) => {
      let plan = match (plan_body[0], subject[0]) {
        (Some(plan_wire), Some(observed_subject)) =>
          match
            @remote.admit_remote_output_plan_json(
              plan_wire, output, observed_subject, max_chunks, max_manifest_bytes,
              max_referenced_bytes,
            ) {
            Ok(value) => value
            Err(_) => stop("durable output plan recovery failed")
          }
        _ => stop("durable output result has no plan")
      }
      let result = match
        @remote.admit_remote_output_result_json(
          body,
          output,
          @remote.remote_output_plan_payload_request(plan),
          @remote.remote_output_plan_transfer_request(plan),
        ) {
        Ok(value) => value
        Err(_) => stop("durable output result admission failed")
      }
      let current = match output_record[0] {
        Some(value) => value
        None => stop("durable output record is missing")
      }
      let transition = match
        @remote.prepare_coordinator_output_success(current, result) {
        Ok(value) => value
        Err(_) => stop("durable output success recovery failed")
      }
      output_record[0] = match
        @remote.commit_coordinator_output_transition(transition, true) {
        Ok(value) => Some(value)
        Err(_) => stop("durable output success commit failed")
      }
    }
    Ok(None) => ()
    Err(issue) => stop(issue)
  }
  if option(matches, "mode") == "reconcile" {
    if output_record[0] is None ||
      @remote.coordinator_dispatch_record_state_codes(record)[5] != "2" {
      output_database.close()
      ignore(coordinator.close())
      stop("Coordinator terminal state is not durable")
    }
    println(
      "{\"kind\":\"reconciled\",\"dispatch_request_cid\":\"" +
      @remote.dispatch_request_identity(dispatch) +
      "\"}",
    )
    output_database.close()
    ignore(coordinator.close())
    return
  }
  if option(matches, "mode") != "run" {
    output_database.close()
    ignore(coordinator.close())
    stop("invalid Coordinator mode")
  }
  let server = match
    @https.open(
      option(matches, "host"),
      port,
      option(matches, "cert"),
      option(matches, "key"),
      option(matches, "ca"),
      max_request_bytes,
      max_response_bytes,
      max_pending,
    ) {
    Ok(value) => value
    Err(_) => {
      output_database.close()
      ignore(coordinator.close())
      stop("Coordinator HTTPS listener failed")
    }
  }
  println("{\"kind\":\"ready\",\"port\":" + server.port().to_string() + "}")
  let expected_fingerprint = option(matches, "site-fingerprint")
  let admin_fingerprint = option(matches, "admin-fingerprint")
  let dispatch_cid = @remote.dispatch_request_identity(dispatch)
  let execution_scope = @remote.dispatch_request_execution_scope(dispatch)
  let poll_path = "/v1/sites/" +
    execution_scope[0] +
    "/generations/" +
    execution_scope[1] +
    "/outbound/poll"
  let observation_path = "/v1/sites/" +
    execution_scope[0] +
    "/generations/" +
    execution_scope[1] +
    "/outbound/observations"
  let mut control_bytes = 0L
  let mut poll_count = 0
  let mut observation_count = 0
  let mut completed = false
  let mut terminal_poll_served = false
  while !terminal_poll_served {
    let request = match server.poll(30000) {
      Ok(Some(value)) => value
      Ok(None) => continue
      Err(_) => stop("Coordinator listener failed")
    }
    let body_bytes = request.body()
    control_bytes += body_bytes.length().to_int64()
    if request.request_method() == "POST" &&
      request.path() == "/v1/coordinator/output-plan" &&
      request.peer_fingerprint() == admin_fingerprint {
      if body_bytes != b"{}" {
        reply(server, request, 400, "{\"error\":\"invalid_request\"}")
      } else {
        match plan_body[0] {
          Some(value) => reply(server, request, 200, value)
          None => reply(server, request, 409, "{\"error\":\"not_ready\"}")
        }
      }
      continue
    }
    if request.peer_fingerprint() != expected_fingerprint {
      reply(server, request, 404, "{\"error\":\"not_found\"}")
      continue
    }
    if request.request_method() != "POST" {
      reply(server, request, 404, "{\"error\":\"not_found\"}")
      continue
    }
    if request.path() == poll_path {
      poll_count += 1
      if body_bytes != b"{}" {
        reply(server, request, 400, "{\"error\":\"invalid_request\"}")
        continue
      }
      if completed {
        match server.respond(request, 204, "application/json", b"") {
          Ok(_) => terminal_poll_served = true
          Err(_) => stop("Coordinator terminal poll response failed")
        }
        continue
      }
      let state = @remote.coordinator_dispatch_record_state_codes(record)
      let envelope = if state[5] == "2" {
        poll_release
      } else if output_record[0] is Some(output_state) {
        if @remote.coordinator_output_record_status(output_state)[1] == "2" {
          poll_release
        } else {
          poll_output
        }
      } else if subject[0] is Some(_) {
        poll_plan
      } else if state[2] != "-1" {
        // An accepted Site revision is already known. Reconcile its exact
        // durable observation instead of delivering a second start request.
        poll_query
      } else {
        poll_dispatch
      }
      reply(server, request, 200, envelope)
      continue
    }
    if request.path() != observation_path {
      reply(server, request, 404, "{\"error\":\"not_found\"}")
      continue
    }
    observation_count += 1
    let body = @utf8.decode(body_bytes) catch { _ => "" }
    let mut accepted = false
    let mut output_ack : String? = None
    match
      @remote.admit_remote_dispatch_response_json(
        body,
        dispatch,
        @remote.DispatchReply,
      ) {
      Ok(response) =>
        match commit_observation(coordinator, record, response) {
          Ok(_) => accepted = true
          Err(_) => ()
        }
      Err(_) => ()
    }
    if !accepted {
      match
        @remote.admit_remote_dispatch_response_json(
          body,
          dispatch,
          @remote.StatusReply,
        ) {
        Ok(response) =>
          match commit_observation(coordinator, record, response) {
            Ok(_) => {
              subject[0] = @remote.remote_dispatch_response_subject(response)
              let projection = @remote.remote_dispatch_response_projection(
                response,
              )
              if projection[3] == 2 {
                completed = true
              }
              accepted = true
            }
            Err(_) => ()
          }
        Err(_) => ()
      }
    }
    if !accepted && output_record[0] is None {
      match subject[0] {
        Some(observed_subject) =>
          match
            @remote.admit_remote_output_plan_json(
              body, output, observed_subject, max_chunks, max_manifest_bytes, max_referenced_bytes,
            ) {
            Ok(plan) => {
              match store_exact_text(output_database, "plan", body) {
                Ok(_) => ()
                Err(issue) => stop(issue)
              }
              let admission = match
                @remote.prepare_coordinator_output_intent(
                  control,
                  output,
                  @remote.remote_output_plan_payload_request(plan),
                  @remote.remote_output_plan_transfer_request(plan),
                ) {
                Ok(value) => value
                Err(_) => stop("output intent preparation failed")
              }
              output_record[0] = match
                @remote.commit_coordinator_output_intent(admission, true) {
                Ok((_, value)) => Some(value)
                Err(_) => stop("output intent commit failed")
              }
              plan_body[0] = Some(body)
              accepted = true
            }
            Err(_) => ()
          }
        None => ()
      }
    }
    if !accepted {
      match (output_record[0], plan_body[0], subject[0]) {
        (Some(output_state), Some(plan_wire), Some(observed_subject)) => {
          let plan = match
            @remote.admit_remote_output_plan_json(
              plan_wire, output, observed_subject, max_chunks, max_manifest_bytes,
              max_referenced_bytes,
            ) {
            Ok(value) => value
            Err(_) => stop("output plan state was corrupted")
          }
          match
            @remote.admit_remote_output_result_json(
              body,
              output,
              @remote.remote_output_plan_payload_request(plan),
              @remote.remote_output_plan_transfer_request(plan),
            ) {
            Ok(result) => {
              match store_exact_text(output_database, "result", body) {
                Ok(_) => ()
                Err(issue) => stop(issue)
              }
              // An exact replay uses the already durable terminal fact. It
              // does not create another transition or advance its revision.
              let confirmed = if output_result_body[0] is Ok(Some(_)) {
                output_state
              } else {
                let transition = match
                  @remote.prepare_coordinator_output_success(
                    output_state, result,
                  ) {
                  Ok(value) => value
                  Err(_) => stop("output success transition failed")
                }
                match
                  @remote.commit_coordinator_output_transition(transition, true) {
                  Ok(value) => value
                  Err(_) => stop("output success commit failed")
                }
              }
              output_record[0] = Some(confirmed)
              output_result_body[0] = Ok(Some(body))
              output_ack = match
                @remote.coordinator_output_report_ack_json(confirmed, body) {
                Ok(value) => Some(value)
                Err(_) => stop("durable output ACK preparation failed")
              }
              accepted = true
            }
            Err(_) => ()
          }
        }
        _ => ()
      }
    }
    if accepted {
      reply(server, request, 200, output_ack.unwrap_or("{\"accepted\":true}"))
    } else {
      reply(server, request, 404, "{\"error\":\"not_found\"}")
    }
  }
  ignore(server.close())
  output_database.close()
  ignore(coordinator.close())
  println(
    "{\"kind\":\"complete\",\"dispatch_request_cid\":\"" +
    dispatch_cid +
    "\",\"control_bytes\":" +
    control_bytes.to_string() +
    ",\"polls\":" +
    poll_count.to_string() +
    ",\"observations\":" +
    observation_count.to_string() +
    "}",
  )
}

///|
fn execute(matches : @argparse.Matches) -> Result[Unit, String] {
  try {
    execute_checked(matches)
    Ok(())
  } catch {
    CommandStop(message) => Err(message)
  }
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  match execute(matches) {
    Ok(_) => ()
    Err(message) => abort("actql-native-remote-coordinator: " + message)
  }
}
