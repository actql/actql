// Physical sink transport for an exact common-owned completed Relation borrow.
// The installed caller reserves and retains the existing Store writer and Run
// Ledger before calling. No cleanup owner, encoder, row codec or CID is added.
const yieldToHost = () => new Promise(resolve => setTimeout(resolve, 0));
const failure = (code, cause) => Object.assign(new Error(code, {cause}), {code});

// Cancellation remains sticky in the original managed provider. A retry makes
// at most one stop-only poll; only the same owner's cleanup confirms release.
// Stop work is observed even after the ordinary Compute allowance is exhausted.
export function stopGeneratedContentPrefix({control, prefix, chargeWork}) {
  control.prefixCancel(prefix);
  if (control.prefixCleanup(prefix) === true) return true;
  let before, result, accountingError, executionError;
  try { before = control.prefixWork(prefix); }
  catch (error) { accountingError = error; }
  // An accounting failure is not permission to leave a physical child alive.
  // Cancellation was made sticky above; this still enters only its stop poll.
  try { result = control.prefixAdvance(prefix, 1); }
  catch (error) { executionError = error; }
  try {
    const after = control.prefixWork(prefix);
    if (typeof before !== 'bigint' || typeof after !== 'bigint' || after < before ||
        after - before > 2147483647n) throw failure('InvalidGeneratedContentStopWork');
    // A false allowance result cannot authorize more Compute, nor prevent the
    // physical child from stopping. It still records the actual difference.
    chargeWork(Number(after - before));
  } catch (error) {
    accountingError ??= error;
  }
  if (result?.output !== undefined) {
    executionError ??= failure('GeneratedContentOutputAfterCancellation');
  }
  if (accountingError !== undefined) {
    throw executionError === undefined ? accountingError
      : failure('GeneratedContentStopAccountingFailed',
        new AggregateError([accountingError, executionError]));
  }
  if (executionError !== undefined) throw executionError;
  return false;
}

// Drive the existing managed prefix, charging cumulative differences from its
// original owner. Never infer zero work from an exception or a missing output.
// The caller already reserved the same Run Ledger and retains this prefix for
// stopping/cleanup; this transport neither releases it nor restarts Compute.
export async function runGeneratedContentPrefix({control, prefix,
  remainingWork, chargeWork, signal, quantum = 32}) {
  if (typeof remainingWork !== 'function' || typeof chargeWork !== 'function' ||
      !Number.isInteger(quantum) || quantum < 1 || quantum > 64) {
    throw new TypeError('InvalidGeneratedContentPrefixTransport');
  }
  let accounted = control.prefixWork(prefix);
  // Resuming a partly-observed Compute without its accounting cursor would
  // lose its earlier work. This entry is for the original unentered prefix;
  // durable byte recovery never re-enters this producer.
  if (accounted !== 0n) throw failure('GeneratedContentPrefixAlreadyAdvanced');
  const account = () => {
    const cumulative = control.prefixWork(prefix);
    if (typeof cumulative !== 'bigint' || cumulative < accounted) {
      throw failure('InvalidGeneratedContentAdvance');
    }
    const delta = cumulative - accounted;
    if (delta > 2147483647n) throw failure('GeneratedContentWorkOverflow');
    accounted = cumulative;
    if (chargeWork(Number(delta)) !== true) throw failure('GeneratedContentWorkLimit');
    return delta;
  };
  for (;;) {
    signal?.throwIfAborted();
    const remaining = remainingWork();
    if (!Number.isInteger(remaining) || remaining < 0 || remaining > 2147483647) {
      throw new TypeError('InvalidGeneratedContentWorkAllowance');
    }
    if (remaining === 0) throw failure('GeneratedContentWorkLimit');
    const granted = Math.min(quantum, remaining);
    let next;
    try { next = control.prefixAdvance(prefix, granted); }
    catch (error) {
      try { account(); }
      catch (accountingError) {
        // Neither failure converts the original execution into success. The
        // existing dispatch custody still stops/reclaims its exact prefix.
        accountingError.executionFailure = error;
        throw accountingError;
      }
      throw error;
    }
    const work = account();
    if (typeof next.work !== 'bigint' || next.work !== work || work > BigInt(granted) ||
        typeof next.stopped !== 'boolean') {
      throw failure('InvalidGeneratedContentAdvance');
    }
    if (next.issue !== undefined) throw failure('GeneratedContentPrefixFailed', next.issue);
    signal?.throwIfAborted();
    if (next.output !== undefined) return next.output;
    if (next.stopped) throw failure('GeneratedContentPrefixStopped');
    if (work === 0n) throw failure('InvalidGeneratedContentAdvance');
    await yieldToHost();
  }
}

// The caller reserves this scan workspace on the existing Run Ledger before
// entry. Its actual work shares the same remaining allowance as generation;
// failure never closes the borrowed input or refunds consumed work.
export async function identifyGeneratedContentInput({control, compiled, input,
  limits, identityLimits, maxWorkspaceSlots, remainingWork, chargeWork,
  signal, quantum = 32, captured}) {
  if (typeof remainingWork !== 'function' || typeof chargeWork !== 'function' ||
      !Number.isInteger(quantum) || quantum < 1 || quantum > 64) {
    throw new TypeError('InvalidGeneratedContentIdentityTransport');
  }
  const allowance = remainingWork();
  if (!Number.isInteger(allowance) || allowance < 0 || allowance > 2147483647) {
    throw new TypeError('InvalidGeneratedContentWorkAllowance');
  }
  signal?.throwIfAborted();
  const scan = control.inputIdentityStart(input, limits, allowance, maxWorkspaceSlots);
  try {
    for (;;) {
      signal?.throwIfAborted();
      const remaining = remainingWork();
      if (!Number.isInteger(remaining) || remaining < 0 || remaining > 2147483647) {
        throw new TypeError('InvalidGeneratedContentWorkAllowance');
      }
      if (remaining === 0) throw failure('GeneratedContentWorkLimit');
      const granted = Math.min(quantum, remaining);
      const next = control.inputIdentityAdvance(scan, granted);
      if (typeof next.work !== 'bigint' || next.work < 0n ||
          next.work > BigInt(granted) || typeof next.ready !== 'boolean') {
        throw failure('InvalidGeneratedContentAdvance');
      }
      if (chargeWork(Number(next.work)) !== true) throw failure('GeneratedContentWorkLimit');
      if (next.issue !== undefined) throw failure('GeneratedContentIdentityFailed', next.issue);
      signal?.throwIfAborted();
      if (next.ready) return control.inputIdentityFinish(compiled, scan, identityLimits, captured);
      if (next.work === 0n) throw failure('InvalidGeneratedContentAdvance');
      await yieldToHost();
    }
  } finally { control.inputIdentityCancel(scan); }
}

export async function writeGeneratedContent({control, input, writer,
  remainingWork, chargeWork, signal, quantum = 32}) {
  if (typeof writer?.append !== 'function' || typeof remainingWork !== 'function' ||
      typeof chargeWork !== 'function' || !Number.isInteger(quantum) ||
      quantum < 1 || quantum > 64) {
    throw new TypeError('InvalidGeneratedContentTransport');
  }
  // This read requires the opaque binding to the original completed port,
  // including for an empty Relation. Caller row arrays/counts are not accepted.
  const rows = control.inputRows(input);
  try {
    for (let row = -1; row < rows; row++) {
      signal?.throwIfAborted();
      if (row >= 0) control.inputRow(input, row);
      for (;;) {
        signal?.throwIfAborted();
        const remaining = remainingWork();
        if (!Number.isSafeInteger(remaining) || remaining < 0) {
          throw new TypeError('InvalidGeneratedContentWorkAllowance');
        }
        if (remaining === 0) throw failure('GeneratedContentWorkLimit');
        const granted = Math.min(quantum, remaining);
        const next = control.inputAdvance(input, granted);
        if (!Number.isInteger(next.work) || next.work < 0 || next.work > granted ||
            typeof next.ready !== 'boolean' || typeof next.piece !== 'string') {
          throw failure('InvalidGeneratedContentAdvance');
        }
        // A failed poll can have consumed work. Report it to the same Ledger
        // before interpreting the failure or trying the physical sink.
        if (chargeWork(next.work) !== true) throw failure('GeneratedContentWorkLimit');
        if (next.issue !== undefined) throw failure('GeneratedContentEncodingFailed', next.issue);
        if (!next.ready && next.work === 0) throw failure('InvalidGeneratedContentAdvance');
        signal?.throwIfAborted();
        if (next.piece.length !== 0) await writer.append(next.piece);
        signal?.throwIfAborted();
        if (next.ready) break;
        await yieldToHost();
      }
    }
    signal?.throwIfAborted();
    return control.inputFinish(input);
  } catch (error) {
    control.inputCancel(input);
    // Never release a possibly written/committed object here. The original
    // installed custody owner keeps its reservation and performs lawful retry.
    throw error;
  }
}
