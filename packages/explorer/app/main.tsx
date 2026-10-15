import {useMemo, useRef, useState, type FormEvent} from 'react';
import {createRoot} from 'react-dom/client';
import {PlanExplorer} from '@actql/explorer-ui/plan-explorer';
import type {PlanReadModel, OriginalRunPlanReadModel} from '@actql/explorer-ui/read-model';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';
import '@actql/explorer-ui/styles.css';
import './styles.css';

function App() {
  const source = useMemo(() => createExplorerBrowserSource({origin: window.location.origin}), []);
  const [connected, connect] = useState(false), [plan, showPlan] = useState<PlanReadModel>();
  const [run, showRun] = useState<unknown>(), [result, showResult] = useState<unknown>();
  const [originalPlan, showOriginalPlan] = useState<OriginalRunPlanReadModel>();
  const [programText, setProgramText] = useState('SELECT 1 AS answer');
  const [programFormat, setProgramFormat] = useState<'sql' | 'aql-text' | 'program'>('sql');
  const [runReference, setRunReference] = useState('');
  const [launcherProgram, showLauncherProgram] = useState(false);
  const [error, showError] = useState(''), [pending, busy] = useState(false);
  const epoch = useRef(0);
  const invalidate = () => {epoch.current++; source.close(); connect(false); busy(false);
    showPlan(undefined); showRun(undefined); showResult(undefined); showOriginalPlan(undefined); showLauncherProgram(false); showError('');};
  const perform = async (action: () => Promise<void>) => {
    const original = epoch.current; busy(true); showError('');
    try {await action();}
    catch {if (original === epoch.current) {showPlan(undefined); showRun(undefined); showResult(undefined); showOriginalPlan(undefined);
      showError('Read unavailable. Check the original reference and current Host access, or explicitly reconnect with a new bootstrap.');}}
    finally {if (original === epoch.current) busy(false);}
  };
  const session = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const form = event.currentTarget;
    const token = String(new FormData(form).get('bootstrap')); form.reset(); invalidate();
    void perform(async () => {
      const selected = epoch.current;
      await source.connect(token);
      connect(true);
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
      format === 'program' ? {} : {format: format as 'sql' | 'aql-text'}));});
  };
  const readRun = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const data = new FormData(event.currentTarget);
    const raw = String(data.get('ref')), name = String(data.get('name'));
    const savedPlan = (event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') === 'run-plan';
    void perform(async () => {showRun(undefined); showResult(undefined); showOriginalPlan(undefined);
      const ref = JSON.parse(raw);
      if (savedPlan) showOriginalPlan(await source.runPlan(ref));
      else {showRun(await source.inspect(ref)); if (name) showResult(await source.describe(ref, name));}});
  };
  return <main><header><p>READ-ONLY · LOCAL PRESENTATION</p><h1>ActQL Explorer</h1>
    <p>Static Plan, existing Run observations and Named Result metadata.</p>
    <p>Controls, Samples, Result payloads and physical/source-origin projections are unavailable.</p></header>
    <form onSubmit={session}><label>One-use bootstrap <input name="bootstrap" type="password"
      autoComplete="off" maxLength={43} required disabled={pending}/></label>
      <button disabled={pending}>Connect</button><button type="button" onClick={invalidate}>Disconnect</button></form>
    <p role="status">{connected ? 'Connected. Session expires after at most five minutes; reconnect explicitly.' : 'Paste the bootstrap printed by the launcher. No Host token belongs in this page.'}</p>
    {error && <p role="alert">{error}</p>}
    <section><h2>Static Plan</h2>
      {launcherProgram && <p>The launcher-selected Program is shown below. This editor requests a separate static Plan.</p>}
      <form onSubmit={readPlan}>
      <label>Format <select name="format" value={programFormat} onChange={event => setProgramFormat(event.target.value as typeof programFormat)}><option value="sql">SQL</option><option value="aql-text">AQL text</option><option value="program">Program JSON</option></select></label>
      <label>Program <textarea name="program" value={programText} onChange={event => setProgramText(event.target.value)} maxLength={60000} required/></label>
      <button disabled={!connected || pending}>Read Plan</button></form>
      {plan && <PlanExplorer model={plan} scopeKey={String(epoch.current)}/>}</section>
    <section><h2>Existing Run</h2><form onSubmit={readRun}>
      <label>Original Run reference JSON <textarea name="ref" value={runReference} onChange={event => setRunReference(event.target.value)} maxLength={4096} required
        placeholder={'{"namespaceId":"...","authorityScopeCid":"sha256:...","runDefinitionCid":"sha256:..."}'}/></label>
      <label>Named Result (optional metadata) <input name="name" maxLength={1024}/></label>
      <button disabled={!connected || pending}>Read Run and metadata</button>
      <button type="submit" value="run-plan" disabled={!connected || pending}>Read saved Run Plan</button></form>
      {originalPlan && <><h3>Saved original Run Plan</h3>
        <p>Static original map; no live progress overlay. Missing old evidence stays unavailable.</p>
        <pre>{JSON.stringify(originalPlan.runRef, null, 2)}</pre>
        <PlanExplorer model={originalPlan.plan} scopeKey={`${epoch.current}:${JSON.stringify(originalPlan.runRef)}`}/></>}
      {run !== undefined && <><h3>Original non-atomic Run observation</h3><pre>{JSON.stringify(run, null, 2)}</pre></>}
      {result !== undefined && <><h3>Named Result metadata</h3><pre>{JSON.stringify(result, null, 2)}</pre></>}</section>
  </main>;
}
createRoot(document.getElementById('root')!).render(<App/>);
