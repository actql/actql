import {runtimeField, runtimePair, runtimeTupleFromFields} from './compiler-binding.generated.mjs';
import {pollSdkPreparation, sdkPreparedRequest, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportRawObservation,
  cancelSdkPreparation, cleanupSdkPreparation, progressSdkOriginalIoCleanup,
  retireSdkDecodedResult, sdkOriginalIoObservationAvailable, bindSdkTransportCredential,
  confirmSavedSdkTransportResponse, pollSdkDecode, takeSavedSdkDecodedResult,
  prepareRegisteredSdkLanguageModel} from './intercepted-request.mjs';

// Private source integration only: not an exported package installation API.
// All records, SDK/request/response buffers and Promise overlaps must be funded
// by the original Run Ledger before this port is installed. No budget, grant,
// execution state or scheduler is inferred here. Common owns every transition.
export function createSdkModelPreflight(options) {
  return createSdkPhysicalPreflight(options, generationPlan,
    (moon, response) => moon.clientProgramModelPhysicalSavedChat(response), 'raw-only');
}

// The admitted selection belongs to the existing installed Provider. The
// runtime still binds this exact Request, Profile, Call, Store and one send.
export function createSdkStructuredModelPreflight(options, admission, readReportedUsage, readReportedResponse) {
  const moon = options?.moon;
  if (admission === undefined ||
      (readReportedUsage !== undefined && typeof readReportedUsage !== 'function') ||
      (readReportedResponse !== undefined && typeof readReportedResponse !== 'function') ||
      typeof moon?.clientProgramModelStructuredRequestPlan !== 'function' ||
      typeof moon?.clientProgramModelPhysicalSavedStructured !== 'function') {
    throw new TypeError('StructuredSdkPhysicalRuntimeUnavailable');
  }
  return createSdkPhysicalPreflight(options, (runtime, request, bytes, amounts,
    profile, installation, start, readDecoded) =>
    runtime.clientProgramModelStructuredRequestPlan(admission, request, bytes,
      amounts.tokens, amounts.costUnits, amounts.durationMs,
      profile, installation, start, readDecoded), undefined, 'saved-sdk', readReportedUsage, readReportedResponse);
}

export function originalSdkCallOptions(generation, prompt, responseFormat, unsupported, providerOptions) {
  const exactInteger = (value, minimum) => typeof value === 'bigint' &&
    value >= minimum && value <= BigInt(Number.MAX_SAFE_INTEGER);
  // MoonBit's JS Int64 representation can carry a negative seed as unsigned.
  const raw = runtimeField(generation, 4);
  const seed = typeof raw === 'bigint' && raw >= -9_223_372_036_854_775_808n &&
    raw <= 18_446_744_073_709_551_615n ? BigInt.asIntN(64, raw) : raw;
  const temperature = runtimeField(generation, 1), topP = runtimeField(generation, 2);
  const tokens = runtimeField(generation, 3);
  if (!Number.isFinite(temperature) || !Number.isFinite(topP) || !exactInteger(tokens, 1n) ||
      seed !== undefined && !exactInteger(seed, -BigInt(Number.MAX_SAFE_INTEGER))) {
    throw new TypeError(unsupported);
  }
  const options = {prompt, responseFormat, temperature, topP, maxOutputTokens: Number(tokens),
    ...(seed === undefined ? {} : {seed: Number(seed)})};
  if (providerOptions !== undefined) options.providerOptions = providerOptions;
  return options;
}

export function sdkProjectionBounds(limits, invalid) {
  const fields = ['maxBytes', 'maxDepth', 'maxFrames', 'maxNodes', 'maxWork'];
  if (limits === null || typeof limits !== 'object' || Array.isArray(limits) ||
      Object.keys(limits).sort().join(',') !== fields.join(',') ||
      fields.some(name => !Number.isSafeInteger(limits[name]) ||
        limits[name] < (name === 'maxWork' ? 0 : 1) || limits[name] > 2_147_483_647)) {
    throw new TypeError(invalid);
  }
  return Object.freeze({...limits});
}

// The verified Host supplies one registration. Common projects the prompt
// from the same admitted capability it uses to create the physical Plan.
export function createAdmittedRegisteredSdkPreflight({moon, request, admission,
  registeredSdk, taskCid, promptCid, outputSchemaCid, projectionLimits,
  maxRequestBytes, maxHeaderBytes, maxHeaders, checked, notify, signal, ...port}) {
  const route = registeredSdk?.route, sdk = port.installation?.sdk;
  if (route === undefined || sdk === undefined ||
      sdk.package_name !== registeredSdk.sdkPackage || sdk.version !== registeredSdk.sdkVersion ||
      sdk.interface !== 'v4' || sdk.lock_artifact_cid !== registeredSdk.lockArtifactCid ||
      port.installation.build_artifact_cid !== registeredSdk.adapterArtifactCid ||
      port.installation.endpoint !== route.endpoint ||
      typeof moon?.clientProgramStartAdmittedStructuredSdkProjection !== 'function' ||
      typeof moon.clientProgramAdvanceOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramRetireOpenAIChatProjection !== 'function' ||
      typeof moon.clientProgramAdmittedStructuredSdkRouteMatches !== 'function' ||
      moon.clientProgramAdmittedStructuredSdkRouteMatches(admission,
        route.selector, route.modelId, route.apiMode, route.endpoint) !== true) {
    throw new TypeError('RegisteredSdkPhysicalInstallationUnavailable');
  }
  const bounds = sdkProjectionBounds(projectionLimits, 'InvalidRegisteredSdkProjectionLimits');
  let cursor, terminal = false;
  const preparationProgress = {
    advance() {
      if (terminal || signal?.aborted) return {kind: 'rejected'};
      if (cursor === undefined) {
        cursor = checked(moon.clientProgramStartAdmittedStructuredSdkProjection(
          admission, request, port.profile, port.installation, bounds.maxBytes, bounds.maxNodes,
          bounds.maxDepth, bounds.maxFrames, bounds.maxWork));
        return {kind: 'pending'};
      }
      const projected = checked(moon.clientProgramAdvanceOpenAIChatProjection(cursor));
      if (projected === undefined) return {kind: 'pending'};
      preparationProgress.cleanup();
      const generation = moon.clientProgramModelRequestGeneration(request);
      if (generation === undefined || runtimeField(generation, 0) !== route.selector ||
          runtimeField(projected, 3) !== taskCid || runtimeField(projected, 4) !== promptCid ||
          runtimeField(projected, 5) !== outputSchemaCid || runtimeField(projected, 6) !== route.selector) {
        throw new TypeError('RegisteredSdkOriginalSelectionUnavailable');
      }
      // The verifier and SDK borrow one immutable request projection. The
      // SDK cannot revise its own expected prompt or schema before fetch.
      const prompt = Object.freeze([Object.freeze({role: 'system', content: runtimeField(projected, 0)}),
        Object.freeze({role: 'user', content: Object.freeze([
          Object.freeze({type: 'text', text: runtimeField(projected, 1)})])})]);
      const schema = JSON.parse(runtimeField(projected, 2), (_key, value) =>
        value !== null && typeof value === 'object' ? Object.freeze(value) : value);
      const responseFormat = Object.freeze({type: 'json', name: 'actql_output', schema});
      const options = Object.freeze(originalSdkCallOptions(generation, prompt, responseFormat,
        'RegisteredSdkGenerationUnsupported', registeredSdk.providerOptions));
      return {kind: 'ready', preparation: prepareRegisteredSdkLanguageModel({moon, admission,
        selector: route.selector, modelId: route.modelId, apiMode: route.apiMode, endpoint: route.endpoint,
        sdkProvider: registeredSdk.sdkProvider, createLanguageModel: registeredSdk.createLanguageModel,
        options, verifyRequest: body => registeredSdk.verifyRequest(body, options),
        maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify})};
    },
    cleanup() {
      if (cursor !== undefined) {
        moon.clientProgramRetireOpenAIChatProjection(cursor);
        cursor = undefined;
      }
      terminal = true;
      return true;
    },
  };
  return createSdkStructuredModelPreflight({...port, moon, request, checked, notify,
    preparationProgress}, admission, registeredSdk.readReportedUsage, registeredSdk.readReportedResponse);
}

function generationPlan(moon, request, bytes, quantities, profile, installation, start) {
  return moon.clientProgramModelAsyncPhysicalRequestPlan(request, bytes,
    quantities.tokens, quantities.costUnits, quantities.durationMs, profile, installation, start);
}

// Native membership/profile checking belongs to Common's dedicated builder.
// No generation settings, decoded SDK facts, startup funding or new Entry
// issuer are introduced. This callback runs during preflight, never between
// the existing final one-shot gate and its fixed physical transport.
export function createSdkNativeDecisionPreflight(options, original, provider, probability) {
  if (typeof options?.moon?.clientProgramModelAsyncNativeDecisionRequestPlan !== 'function' ||
      typeof options?.moon?.clientProgramModelPhysicalSavedNativeDecision !== 'function' ||
      original === undefined || provider === undefined || probability === undefined) {
    throw new TypeError('NativeDecisionPhysicalRuntimeUnavailable');
  }
  return createSdkPhysicalPreflight(options, (moon, request, bytes, quantities, profile, installation, start) =>
    moon.clientProgramModelAsyncNativeDecisionRequestPlan(request, original, provider,
      bytes, quantities.tokens, quantities.costUnits, quantities.durationMs, profile,
      installation, probability, start), (moon, response, checked) =>
      checked(moon.clientProgramModelPhysicalSavedNativeDecision(response,
        original, provider, probability)), 'sdk');
}

function createSdkPhysicalPreflight({moon, request, preparation, profile,
  installation, quantities, fetch, responseLimits, persistRaw, notify, checked,
  observeAt, cleanupRaw, preparationProgress, rawCaptureBinder, needsCredential = false}, preparePlan, selectSaved, responseMode, readReportedUsage, readReportedResponse) {
  const deferredRaw = rawCaptureBinder !== undefined;
  const structured = responseMode === 'saved-sdk';
  if (typeof fetch !== 'function' || needsCredential && !deferredRaw ||
      (deferredRaw ? typeof rawCaptureBinder !== 'function' ||
        persistRaw !== undefined || cleanupRaw !== undefined ||
        preparation !== undefined || preparationProgress === undefined
        : typeof persistRaw !== 'function' || typeof cleanupRaw !== 'function') ||
      typeof notify !== 'function' || typeof checked !== 'function' ||
      typeof observeAt !== 'function' ||
      preparationProgress !== undefined && (preparation !== undefined ||
        typeof preparationProgress?.advance !== 'function' ||
        typeof preparationProgress?.cleanup !== 'function')) {
    throw new TypeError('InvalidSdkModelPort');
  }
  let plan;
  let call;
  let response;
  let selectedResponse;
  let saving;
  let reconciling;
  let reconciliationPending = false;
  let reconciled;
  let saveStarted = false;
  let failure;
  let startUnknown = false;
  let preparationTerminal = false;
  let retired = false;
  let rawBound = !deferredRaw;
  const wake = () => {
    try { notify(); } catch { /* Wake is not execution or persistence evidence. */ }
  };
  const readDecoded = structured ? (original, receipt, bytes) => {
    if (retired || original !== call || pollSdkDecode(preparation).kind !== 'ready') {
      return undefined;
    }
    const decoded = takeSavedSdkDecodedResult(preparation, receipt, bytes);
    const content = decoded.content;
    // Only the same SDK invocation's confirmed Raw supplies observations.
    // The SDK's normalized usage/model/request defaults are not evidence.
    const raw = decoded.response?.body;
    const usage = readReportedUsage?.(raw);
    const report = readReportedResponse?.(raw);
    const finish = report?.outcome ?? decoded.finishReason?.unified ?? 'unknown';
    const text = finish === 'stop' && Array.isArray(content) && content.length === 1 &&
      content[0]?.type === 'text' && typeof content[0].text === 'string' ? content[0].text : undefined;
    const reportedText = value => typeof value === 'string' && value.length > 0 && value.length <= 256
      ? value : undefined;
    return runtimeTupleFromFields([text, finish, usage?.inputTokens, usage?.outputTokens,
      reportedText(report?.model), reportedText(report?.requestId), reportedText(report?.finishReason),
      text !== undefined]);
  } : undefined;
  const pollResponse = () => {
    // Only the unused SDK projection is dropped. Saved/raw observations and
    // the same Store/Entry cleanup obligation remain owned independently.
    if (!structured && !retired && preparation !== undefined) retireSdkDecodedResult(preparation);
    if (response !== undefined && failure === undefined && !startUnknown) {
      try {
        if (selectedResponse !== undefined) return selectedResponse;
        if (structured) {
          const decoded = pollSdkDecode(preparation);
          if (decoded.kind === 'pending') return moon.clientProgramModelPhysicalPending();
          selectedResponse = checked(moon.clientProgramModelPhysicalSavedStructured(
            call, response.receipt, response.bytes));
        } else {
          selectedResponse = selectSaved(moon, response, checked);
        }
        return selectedResponse;
      }
      catch (error) {
        // Late binding loss does not erase saved raw custody or recreate Entry.
        // Retain the primary failure and let the original Model hold Unknown.
        failure = error;
      }
    }
    if (failure !== undefined || startUnknown) return moon.clientProgramModelPhysicalUnknown();
    if (retired) {
      throw Object.assign(new TypeError('ForeignSdkPreparation'), {code: 'ForeignSdkPreparation'});
    }
    const observed = pollSdkTransport(preparation);
    const raw = sdkTransportRawObservation(preparation);
    if (raw !== undefined && !saveStarted) {
      saveStarted = true;
      // The installed persistence port must use this exact original call and
      // raw backing, reconfirm Store bytes, and return its nominal saved view.
      // No SDK decoded defaults supply Common's answer or usage observations.
      saving = Promise.resolve().then(() => structured
        ? persistRaw(call, raw, true) : persistRaw(call, raw)).then(saved => {
        if (structured) {
          confirmSavedSdkTransportResponse(preparation, raw, saved);
          response = saved;
        } else {
          response = saved.response;
          if (response === undefined) throw new TypeError('MissingSavedRawChat');
        }
      }).catch(error => {
        failure = error;
      }).finally(() => { saving = undefined; wake(); });
    }
    if (saveStarted) return moon.clientProgramModelPhysicalPending();
    return observed.kind === 'unknown'
      ? moon.clientProgramModelPhysicalUnknown()
      : moon.clientProgramModelPhysicalPending();
  };
  const poll = () => {
    let io;
    if (!retired && preparation !== undefined) {
      try { io = progressSdkOriginalIoCleanup(preparation); }
      catch { /* Neither failure nor cancellation is a quiescence ACK. */ }
    }
    const observed = pollResponse();
    // Only a selected original transport with an actual cleanup port reports
    // the separate fact. Legacy decoded/native transports stay unchanged.
    // SDK true is DATA: the same Common callback still checks Call/Entry/Plan/
    // attempt/reservation before admitting its own internal nominal observation.
    if ((responseMode === 'raw-only' || structured) && io !== undefined &&
        typeof moon.clientProgramModelPhysicalIoObservation === 'function') {
      return moon.clientProgramModelPhysicalIoObservation(call, io === true, observed);
    }
    return observed;
  };
  const cancel = () => {
    if (retired) {
      throw Object.assign(new TypeError('ForeignSdkPreparation'), {code: 'ForeignSdkPreparation'});
    }
    if (preparation !== undefined) cancelSdkPreparation(preparation);
  };
  const cleanup = () => {
    if (retired) return true;
    if (preparation !== undefined) retireSdkDecodedResult(preparation);
    if (preparation !== undefined) {
      try { progressSdkOriginalIoCleanup(preparation); }
      catch { /* Full original cleanup must still settle this duty. */ }
    }
    if (saving !== undefined || reconciliationPending) return false;
    // Every attempted raw save retains its original port until cleanup,
    // including a successful save's local aliases. This does not erase the
    // parent's durable receipt/custody. Failed commit/cleanup stays pending.
    if (saveStarted || failure !== undefined || deferredRaw && rawBound) {
      try {
        if (cleanupRaw(call) !== true) return false;
      } catch { return false; }
    }
    if (preparation !== undefined && !cleanupSdkPreparation(preparation)) return false;
    if (preparationProgress !== undefined) {
      try { if (preparationProgress.cleanup() !== true) return false; }
      catch { return false; }
    }
    response = undefined;
    selectedResponse = undefined;
    reconciled = undefined;
    reconciling = undefined;
    call = undefined;
    plan = undefined;
    // Escaped preflight/call closures must not keep the factory's original
    // input or installed callbacks after both original owners acknowledge
    // cleanup. Pending/failed cleanup retains them unchanged for retry.
    // Escaped immutable views and the primary failure retain their own
    // responsibility; clearing these aliases does not mutate those originals.
    request = undefined;
    preparation = undefined;
    preparationProgress = undefined;
    profile = undefined;
    installation = undefined;
    quantities = undefined;
    fetch = undefined;
    responseLimits = undefined;
    persistRaw = undefined;
    notify = undefined;
    checked = undefined;
    observeAt = undefined;
    cleanupRaw = undefined;
    preparePlan = undefined;
    selectSaved = undefined;
    readReportedUsage = undefined;
    readReportedResponse = undefined;
    retired = true;
    return true;
  };
  const start = entry => {
    // Missing installation custody is not send permission. Core keeps an
    // already entered attempt's unknown responsibility when no call starts.
    // This is a local data check, with no callback or await at the final gate.
    if (retired || call !== undefined || startUnknown) return undefined;
    if (!rawBound) { startUnknown = true; return undefined; }
    call = moon.clientProgramModelPhysicalCallForRequest(entry, request, poll, cancel, cleanup);
    if (call === undefined) { startUnknown = true; return undefined; }
    // Exact fixed transport only, immediately after Common's final gate. No
    // await, notification, user callback or request rebuilding occurs here.
    try { startSdkTransport(preparation); }
    catch { startUnknown = true; }
    return call;
  };
  const advance = () => {
    if (retired) return [true, undefined];
    if (plan !== undefined) return [true, plan];
    if (preparationTerminal) return [true, undefined];
    if (preparation===undefined && preparationProgress!==undefined) {
      try {
        const projected=preparationProgress.advance();
        if (projected.kind==='pending') return [false,undefined];
        if (projected.kind!=='ready' || projected.preparation===undefined) {
          preparationTerminal=true;
          return [true,undefined];
        }
        preparation=projected.preparation;
      } catch {
        preparationTerminal=true;
        return [true,undefined];
      }
      // SDK async readiness is a later advance, never another Common poll in
      // this same bounded physical-preflight transition.
      return [false,undefined];
    }
    const preparationState = pollSdkPreparation(preparation);
    if (preparationState.kind === 'pending') return [false, undefined];
    if (preparationState.kind !== 'ready') return [true, undefined];
    const original = sdkPreparedRequest(preparation);
    // Freeze fetch/init/bounds before Common consumes its one-shot Entry.
    preparationTerminal = true;
    try {
      prepareSdkTransport(preparation, {fetch, responseLimits, observeAt, responseMode});
      if ((responseMode === 'raw-only' || structured) && sdkOriginalIoObservationAvailable(preparation) &&
          typeof moon.clientProgramModelPhysicalIoObservation !== 'function') {
        throw new TypeError('OriginalSdkPhysicalIoObservationUnavailable');
      }
      plan = checked(preparePlan(moon, request, BigInt(original.requestBytes),
        quantities, profile, installation, start, readDecoded));
    } catch { return [true, undefined]; }
    return [true, plan];
  };
  if (deferredRaw) {
    // The same original operation retains this private binder before its
    // Common preflight cursor is issued. Only its installed continuation
    // supplies the actual Store port after nominal raw registration.
    const bindRaw = (registration, persistence) => {
      if (retired || rawBound || registration === undefined ||
          typeof persistence !== 'function' || typeof persistence.cleanup !== 'function') {
        throw new TypeError('OriginalSdkRawBindingUnavailable');
      }
      persistRaw = persistence;
      cleanupRaw = persistence.cleanup;
      rawBound = true;
    };
    const bound = needsCredential ? rawCaptureBinder(bindRaw, () => {
      if (retired || plan === undefined || preparation === undefined) {
        throw new TypeError('OpenAIProjectCredentialPreparationUnavailable');
      }
      bindSdkTransportCredential(preparation);
    }) : rawCaptureBinder(bindRaw);
    if (bound !== undefined) throw new TypeError('OriginalSdkRawBinderUnavailable');
    rawCaptureBinder = undefined;
  }
  // The pinned MoonBit JS tuple ABI is a field record, not a JS Array.
  const preflight = moon.clientProgramModelRequestPreflight(() => {
    const [terminal, physicalPlan] = advance();
    return runtimePair(terminal, physicalPlan);
  }, cleanup);
  return Object.freeze({preflight,
    reconcileRaw(original) {
      // An explicit parent request only. Reuse the same observed transport
      // backing and persistence port, never re-enter the physical operation.
      // The saved view is returned for Common's reconciliation/usage reader;
      // it does not replace a terminal Unknown or issue answer/send authority.
      if (retired || call === undefined || original !== call ||
          !saveStarted || failure === undefined || saving !== undefined) {
        return Promise.reject(new TypeError('OriginalRawReconciliationUnavailable'));
      }
      if (reconciling !== undefined) return reconciling;
      const raw = sdkTransportRawObservation(preparation);
      if (raw === undefined) {
        return Promise.reject(new TypeError('MissingOriginalRawObservation'));
      }
      // This private initial physical shape owns one stable reconfirmation
      // Promise/view, including failure. Further recovery requires an explicit
      // owner-funded token/lifetime; it is not a language-level retry ban.
      reconciliationPending = true;
      reconciling = Promise.resolve().then(() => structured
        ? persistRaw(call, raw, true) : persistRaw(call, raw))
        .then(saved => {
          if (structured) return saved;
          if (saved?.response === undefined) throw new TypeError('MissingSavedRawChat');
          reconciled = saved.response;
          return saved;
        }).finally(() => { reconciliationPending = false; wake(); });
      return reconciling;
    },
    readReconciledUsage(original, quantum) {
      if (retired || original !== call || reconciled === undefined ||
          !Number.isInteger(quantum) || quantum < 1 || quantum > 2_147_483_647) {
        throw new TypeError('OriginalRawUsageUnavailable');
      }
      return checked(moon.clientProgramReadReconciledInferRawUsage(
        original, reconciled, quantum));
    },
    // Private retained responsibility for the parent owner, never a public
    // success/result or authority. A failed save is not automatically retried.
    rawFailure: () => failure,
  });
}
