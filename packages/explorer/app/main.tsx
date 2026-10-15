import type {CheckpointSummary} from '@actql/sdk';
import type {CheckpointPageModel,ReviewObservation} from '@actql/explorer-ui/checkpoint-review';
import {useEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {createRoot} from 'react-dom/client';
import {PlanExplorer, RunInspector, CancellationPanel, CheckpointPanel} from '@actql/explorer-ui/plan-explorer';
import type {OriginalCancellation, CancellationObservation} from '@actql/explorer-ui/plan-explorer';
import {validCancellationRef, validOperationAttemptRef} from '@actql/client-wire';
import type {WireCancellationLookup} from '@actql/client-wire';
import type {RunObservationModel} from '@actql/explorer-ui/run-observation';
import type {PlanReadModel, OriginalRunPlanReadModel} from '@actql/explorer-ui/read-model';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';
import '@actql/explorer-ui/styles.css';
import './styles.css';

function App() {
  const source = useMemo(() => createExplorerBrowserSource({origin: window.location.origin}), []);
  const [connected, connect] = useState(false), [plan, showPlan] = useState<PlanReadModel>();
  const [run, showRun] = useState<RunObservationModel>(), [result, showResult] = useState<unknown>();
  const [follow, setFollow] = useState(false);
  const [originalPlan, showOriginalPlan] = useState<OriginalRunPlanReadModel>();
  const [programText, setProgramText] = useState('SELECT 1 AS answer');
  const [programFormat, setProgramFormat] = useState<'sql' | 'aql' | 'aql-text' | 'program'>('sql');
  const [runReference, setRunReference] = useState('');
  const [launcherProgram, showLauncherProgram] = useState(false);
  const [error, showError] = useState(''), [pending, busy] = useState(false);
  const [cancellationEnabled, enableCancellation] = useState(false);
  const [originalCancellation, keepCancellation] = useState<OriginalCancellation|null>(null);
  const [cancellationObservation, showCancellation] = useState<CancellationObservation|null>(null);
  const [cancellationHistory, showCancellationHistory] = useState<WireCancellationLookup|null>(null);
  const [savedCancellation, confirmSavedCancellation] = useState(false);
  const [checkpointPage,showCheckpointPage]=useState<CheckpointPageModel|null>(null);
  const [review,showReview]=useState<ReviewObservation|null>(null);
  const [checkpointCapabilities,setCheckpointCapabilities]=useState({list:false,read:false});
  const reviewSelection=useRef(0);
  const cancelSent = useRef(false);
  const epoch = useRef(0);
  const runSelection = useRef(0);
  const invalidate = () => {epoch.current++; runSelection.current++; setFollow(false); source.close(); connect(false); enableCancellation(false); busy(false);
    showPlan(undefined); showRun(undefined); showResult(undefined); showOriginalPlan(undefined); showLauncherProgram(false);
    reviewSelection.current++;showCheckpointPage(null);showReview(null);setCheckpointCapabilities({list:false,read:false});
    showCancellationHistory(null);showCancellation(originalCancellation && cancelSent.current
      ? {state:'unknown',original:originalCancellation} : null);showError('');};
  const perform = async (action: () => Promise<void>) => {
    const original = epoch.current; busy(true); showError('');
    try {await action();}
    catch {if (original === epoch.current) {invalidate();
      showError('Read unavailable. Check the original reference and current Host access, or explicitly reconnect with a new bootstrap.');}}
    finally {if (original === epoch.current) busy(false);}
  };
  useEffect(() => {
    if (!follow || !run || run.run.terminal || pending || !connected) return;
    const selected = runSelection.current, scope = epoch.current;
    const timer = setTimeout(() => {void perform(async () => {
      const next = await source.observe(run.runRef);
      if (runSelection.current === selected && epoch.current === scope) showRun(next);
    });}, 1000);
    return () => clearTimeout(timer);
  }, [follow, run, pending, connected, source]);
  const session = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const form = event.currentTarget;
    const token = String(new FormData(form).get('bootstrap')); form.reset(); invalidate();
    void perform(async () => {
      const selected = epoch.current;
      const capabilities = await source.connect(token);
      setCheckpointCapabilities({list:capabilities.checkpointList,read:capabilities.checkpointReview});
      enableCancellation(capabilities.cancellation); connect(true);
      const view = await source.launchView();
      if (epoch.current !== selected) return;
      if (view?.kind === 'program') {
        showLauncherProgram(true); showPlan(view.plan);
      } else if (view?.kind === 'run') {
        setRunReference(JSON.stringify(view.originalPlan.runRef, null, 2));
        showOriginalPlan(view.originalPlan);
      }
    });
  };
  const readPlan = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const data = new FormData(event.currentTarget);
    const text = String(data.get('program')), format = String(data.get('format'));
    void perform(async () => {showLauncherProgram(false); showPlan(undefined); showPlan(await source.plan(
      format === 'program' ? JSON.parse(text) : text,
      format === 'program' ? {} : {format: format as 'sql' | 'aql' | 'aql-text'}));});
  };
  const readRun = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const data = new FormData(event.currentTarget);
    const raw = String(data.get('ref')), name = String(data.get('name'));
    const savedPlan = (event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') === 'run-plan';
    const selected = ++runSelection.current, scope = epoch.current; setFollow(false);
    void perform(async () => {showRun(undefined); showResult(undefined); showOriginalPlan(undefined);
      const ref = JSON.parse(raw);
      if (savedPlan) {
        const value = await source.runPlan(ref);
        if (runSelection.current === selected && epoch.current === scope) showOriginalPlan(value);
      } else {
        const value = await source.observe(ref);
        const metadata = name ? await source.describe(ref, name) : undefined;
        if (runSelection.current === selected && epoch.current === scope) {showRun(value); showResult(metadata);}
      }});
  };
  const prepareCancellation = () => {
    if (!run || run.run.terminal || originalCancellation || !connected || !cancellationEnabled) return;
    setFollow(false);
    keepCancellation(Object.freeze({cancelRef:Object.freeze({...run.runRef,
      cancelId:crypto.randomUUID(),expectedRevision:run.run.controlRevision}),
      attemptRef:Object.freeze({operation:'cancel' as const,attemptId:crypto.randomUUID()})}));
  };
  const requestCancellation = () => {
    if (!originalCancellation || !savedCancellation || cancelSent.current || !connected || !cancellationEnabled) return;
    // Keep this exact explicit operation before transport and never dispatch it
    // a second time from this view, including after ACK loss or scope changes.
    cancelSent.current=true;setFollow(false);
    const saved=originalCancellation,scope=epoch.current;
    showCancellation({state:'unknown',original:saved});
    void perform(async () => {const answer=await source.cancel(saved);
      if (epoch.current===scope) showCancellation(answer);});
  };
  const lookupCancellation = () => {
    if (!originalCancellation || !connected || !cancellationEnabled) return;
    const saved=originalCancellation,scope=epoch.current;
    void perform(async () => {const answer=await source.lookupCancellation(saved.cancelRef);
      if (epoch.current===scope) showCancellationHistory(answer);});
  };
  const importCancellation = (event:FormEvent<HTMLFormElement>) => {
    event.preventDefault();if(originalCancellation) return;
    try {
      const input=JSON.parse(String(new FormData(event.currentTarget).get('original')));
      if (!input || Object.keys(input).length!==2 || !validCancellationRef(input.cancelRef) ||
          !validOperationAttemptRef(input.attemptRef) || input.attemptRef.operation!=='cancel') throw new Error();
      const saved=Object.freeze({cancelRef:Object.freeze(structuredClone(input.cancelRef)),
        attemptRef:Object.freeze(structuredClone(input.attemptRef))});
      keepCancellation(saved);cancelSent.current=true;showCancellation({state:'unknown',original:saved});
    } catch {showError('Invalid original cancellation reference. No Host operation was requested.');}
  };
  const listCheckpoints=()=>{const selected=++reviewSelection.current,scope=epoch.current;setFollow(false);
    void perform(async()=>{showCheckpointPage(null);showReview(null);const value=await source.checkpoints();
      if(epoch.current===scope&&selected===reviewSelection.current)showCheckpointPage(value);});};
  const readReview=(checkpoint:CheckpointSummary)=>{const selected=++reviewSelection.current,scope=epoch.current;setFollow(false);
    void perform(async()=>{showReview(null);const value=await source.reviewCheckpoint(checkpoint);
      if(epoch.current===scope&&selected===reviewSelection.current)showReview(value);});};
  return <main><header><p>LOCAL PRESENTATION · EXPLICIT OWNER OPERATIONS</p><h1>ActQL Explorer</h1>
    <p>Static Plan, existing Run observations and Named Result metadata.</p>
    <p>Pause, step, resume, Samples, Result payloads and physical/source-origin projections are unavailable. Cancellation is available only with the launcher’s explicit opt-in and current Host permission.</p></header>
    <form onSubmit={session}><label>One-use bootstrap <input name="bootstrap" type="password"
      autoComplete="off" maxLength={43} required disabled={pending}/></label>
      <button disabled={pending}>Connect</button><button type="button" onClick={invalidate}>Disconnect</button></form>
    <p role="status">{connected ? 'Connected. Session expires after at most five minutes; reconnect explicitly.' : 'Paste the bootstrap printed by the launcher. No Host token belongs in this page.'}</p>
    {error && <p role="alert">{error}</p>}
    <section><h2>Static Plan</h2>
      {launcherProgram && <p>The launcher-selected Program is shown below. This editor requests a separate static Plan.</p>}
      <form onSubmit={readPlan}>
      <label>Format <select name="format" value={programFormat} onChange={event => setProgramFormat(event.target.value as typeof programFormat)}><option value="sql">SQL</option><option value="aql">AQL</option><option value="aql-text">AQL text alias</option><option value="program">Program JSON</option></select></label>
      <label>Program <textarea name="program" value={programText} onChange={event => setProgramText(event.target.value)} maxLength={60000} required/></label>
      <button disabled={!connected || pending}>Read Plan</button></form>
      {plan && <PlanExplorer model={plan} scopeKey={String(epoch.current)}/>}</section>
    <section><h2>Existing Run</h2><form onSubmit={readRun}>
      <label>Original Run reference JSON <textarea name="ref" value={runReference} onChange={event => {
        runSelection.current++; setFollow(false); showRun(undefined); setRunReference(event.target.value);
      }} maxLength={4096} required
        placeholder={'{"namespaceId":"...","authorityScopeCid":"sha256:...","runDefinitionCid":"sha256:..."}'}/></label>
      <label>Named Result (optional metadata) <input name="name" maxLength={1024}/></label>
      <button disabled={!connected || pending}>Read Run and metadata</button>
      <button type="submit" value="run-plan" disabled={!connected || pending}>Read saved Run Plan</button></form>
      {originalPlan && <><h3>Saved original Run Plan</h3>
        <p>Static original map; no live progress overlay. Missing old evidence stays unavailable.</p>
        <pre>{JSON.stringify(originalPlan.runRef, null, 2)}</pre>
        <PlanExplorer model={originalPlan.plan} scopeKey={`${epoch.current}:${JSON.stringify(originalPlan.runRef)}`}/></>}
      {run !== undefined && <><label className="actql-run-follow"><input type="checkbox" checked={follow}
        disabled={pending || run.run.terminal} onChange={event => setFollow(event.target.checked)}/>
        Follow this exact Run (one-second read interval)</label>
        <p>{run.run.terminal ? 'Following stopped: terminal Run state observed.'
          : follow ? 'Following authorized read-only observations; no execution is started.' : 'Showing the last explicit read.'}</p>
        <RunInspector model={run}/></>}
      {result !== undefined && <><h3>Named Result metadata</h3><pre>{JSON.stringify(result, null, 2)}</pre></>}</section>
    <CheckpointPanel page={checkpointPage} review={review} pending={pending}
      canList={connected&&checkpointCapabilities.list} canRead={connected&&checkpointCapabilities.read}
      onList={listCheckpoints} onRead={readReview}/>
    {(cancellationEnabled || originalCancellation) && <section>
      {!originalCancellation && <form onSubmit={importCancellation}>
        <label>Saved original cancellation JSON (lookup only)<textarea name="original" maxLength={8192} required/></label>
        <button disabled={pending}>Load saved reference for lookup</button></form>}
      {originalCancellation && !cancelSent.current && <label className="actql-run-follow">
        <input type="checkbox" checked={savedCancellation} onChange={event=>confirmSavedCancellation(event.target.checked)} disabled={pending}/>
        I saved this original cancellation reference.</label>}
      <CancellationPanel original={originalCancellation} observation={cancellationObservation}
        history={cancellationHistory} pending={pending}
        canPrepare={connected && cancellationEnabled && !!run && !run.run.terminal && !originalCancellation}
        canRequest={connected && cancellationEnabled && savedCancellation && !cancelSent.current}
        canLookup={connected && cancellationEnabled && !!originalCancellation}
        onPrepare={prepareCancellation} onRequest={requestCancellation} onLookup={lookupCancellation}/>
    </section>}
  </main>;
}
createRoot(document.getElementById('root')!).render(<App/>);
