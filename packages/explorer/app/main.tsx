import type {CheckpointPageModel,ReviewObservation,ReviewReference} from '@actql/explorer-ui/checkpoint-review';
import {useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode} from 'react';
import {createRoot} from 'react-dom/client';
import {PlanExplorer, RunInspector, CancellationPanel, CheckpointPanel} from '@actql/explorer-ui/plan-explorer';
import type {OriginalCancellation, CancellationObservation} from '@actql/explorer-ui/plan-explorer';
import {validCancellationRef, validOperationAttemptRef, validRunRef} from '@actql/client-wire';
import type {RunReference} from '@actql/sdk';
import type {WireCancellationLookup} from '@actql/client-wire';
import type {RunObservationModel} from '@actql/explorer-ui/run-observation';
import type {PlanReadModel, StaticExplanationReadModel, OriginalRunPlanReadModel, OriginalRunPresentationReadModel, SavedExplanationReadModel, ExplanationStoryModel} from '@actql/explorer-ui/read-model';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';
import '@actql/explorer-ui/styles.css';
import './styles.css';

type StoryContext = StaticExplanationReadModel['context'];
type Step = ExplanationStoryModel['occurrences'][number];

function sameRun(original: RunReference, other: RunReference | undefined) {
  return other?.namespaceId === original.namespaceId && other.authorityScopeCid === original.authorityScopeCid &&
    other.runDefinitionCid === original.runDefinitionCid;
}

function StoryText({text}: {text: string}) {
  return <>{text.split(/("[^"\n]+")/u).map((part, index) => index % 2
    ? <code key={index}>{part.slice(1, -1)}</code> : part)}</>;
}

function StoryHeading({story, context}: {story: ExplanationStoryModel; context: StoryContext}) {
  const sources = context.filter(item=>item.origin.kind==='source');
  const models = context.filter(item=>item.origin.kind==='model_task');
  const outputs = context.filter(item=>item.origin.kind==='result');
  const effects = context.filter(item=>item.origin.kind==='effect_set');
  const ja = story.locale === 'ja';
  const sourceNames = sources.slice(0, 3).flatMap(({origin}) => origin.kind === 'source'
    ? [`"${origin.source_view.connector}.${origin.source_view.resource}"`] : []);
  const extraSources = sources.length - sourceNames.length;
  const sourceSummary = sourceNames.length ? ja
    ? `${sourceNames.join('、')}${extraSources ? `ほか ${extraSources} 件` : ''}を読み取る`
    : `Read ${sourceNames.join(', ')}${extraSources ? ` and ${extraSources} more declared sources` : ''}` : '';
  const joins = story.occurrences.filter(step=>step.explanation.meaning.kind==='join').length;
  const joinSummary = joins ? ja ? `確認済みの結合 ${joins} 件で入力を結ぶ` :
    `Combine inputs using ${joins} checked ${joins === 1 ? 'join' : 'joins'}` : '';
  const filter = story.occurrences.find(step=>step.explanation.meaning.kind==='filter');
  const summary = [sourceSummary, joinSummary, ...models.slice(0, 2).map(item=>item.text),
    filter?.explanation.text, ...outputs.slice(0, 2).map(item=>item.text), effects[0]?.text]
    .filter((text): text is string=>!!text)
    .map(text=>/[.!?。！？]$/u.test(text) ? text : text + (ja ? '。' : '.'))
    .join(ja ? '' : ' ');
  return <>
    <h1>{summary ? <StoryText text={summary}/> : 'Original query narrative'}</h1>
    <div className="story-chips">
      {effects.length > 0 && <span className="workspace-chip" data-tone="amber">Declared Effects</span>}
      {sources.length > 0 && <span className="workspace-chip" data-tone="teal">{sources.length} declared {sources.length === 1 ? 'source' : 'sources'}</span>}
      {models.length > 0 && <span className="workspace-chip" data-tone="lilac">{models.length} Model {models.length === 1 ? 'task' : 'tasks'} · input rows</span>}
    </div>
  </>;
}

function StoryCard({ordinal, label, title, detail, observed, children}: {
  ordinal: number; label: string; title: string; detail?: string; observed?: boolean; children: ReactNode;
}) {
  return <li className="story-row">
    <span className="step-marker" aria-hidden="true">{ordinal}</span>
    <details className="story-card panel">
      <summary><span className="step-label">{label}{observed && <span className="workspace-chip" data-tone="teal">Observed boundary</span>}</span>
        <strong><StoryText text={title}/></strong>{detail && <span className="step-summary"><StoryText text={detail}/></span>}
      </summary>
      <div className="step-details">{children}</div>
    </details>
  </li>;
}

function StepOrigin({step}: {step: Step}) {
  return <div className="occurrence-origin">
    <strong>{step.title}</strong><p><StoryText text={step.explanation.text}/></p>
    <code>{step.stepId}</code>
    {step.ports.length > 0 && <details><summary>Original ports</summary>
      <ul>{step.ports.map(port=><li key={port.port_id}>{port.role} · <code>{port.port_id}</code></li>)}</ul></details>}
  </div>;
}

function StorySteps({story, context, boundary}: {story: ExplanationStoryModel; context: StoryContext; boundary?: string}) {
  const sources = context.filter(item=>item.origin.kind === 'source');
  const outputs = context.filter(item=>item.origin.kind === 'result' || item.origin.kind === 'effect_set');
  const models = new Map<string, StoryContext[number][]>();
  const unboundModels: StoryContext[number][] = [];
  for (const item of context) if (item.origin.kind === 'model_task') {
    const producer = item.origin.producer;
    if (producer.state === 'projected') {
      if (!models.has(producer.step_id)) models.set(producer.step_id, []);
      models.get(producer.step_id)!.push(item);
    } else unboundModels.push(item);
  }
  const groups: Step[][] = [];
  for (const step of story.occurrences) {
    const current = groups.at(-1);
    if (step.operator === 'join' && current?.[0]?.operator === 'join') current.push(step);
    else groups.push([step]);
  }
  let ordinal = 0;
  return <section aria-label="Original story"><p className="ordering-note">{story.ordering.text}</p>
    <ol className="story-steps">
      {sources.map(({origin,text})=>origin.kind === 'source' && <StoryCard key={`source-${origin.stage_input.stage_ordinal}-${origin.stage_input.input_port_ordinal}`}
        ordinal={++ordinal} label="Read" title={text}>
        <p>{origin.source_view.connector} · <code>{origin.source_view.resource}</code> · {origin.request_kind}</p>
        <p>Stage {origin.stage_input.stage_ordinal + 1} · input {origin.stage_input.input_port_ordinal + 1}</p>
        <dl><dt>Contract</dt><dd><code>{origin.source_view.contract_cid}</code></dd>
          <dt>Catalog</dt><dd><code>{origin.source_view.catalog_cid}</code></dd></dl>
        {origin.consuming_ports.length > 0 && <ul aria-label="Original consumers">
          {origin.consuming_ports.map(port=><li key={port.port_id}><code>{port.step_id}</code><br/><code>{port.port_id}</code></li>)}</ul>}
      </StoryCard>)}
      {groups.map(group=>{
        const step = group[0], tasks = models.get(step.stepId) ?? [];
        const title = tasks.length === 1 ? tasks[0].text : tasks.length > 1 ? `${tasks.length} model tasks` :
          group.length > 1 ? `${group.length} join operations` :
          step.operator ? step.operator.replaceAll('_', ' ') : 'Original port';
        return <StoryCard key={step.stepId} ordinal={++ordinal} observed={group.some(item=>item.stepId===boundary)}
          label={tasks.length ? 'Ask model' : step.operator === 'join' ? 'Combine' : 'Computation'}
          title={title} detail={tasks.length ? undefined : step.explanation.text}>
          {group.map(item=><StepOrigin key={item.stepId} step={item}/>)}
          {tasks.map(({origin, text}, index)=>origin.kind === 'model_task' && <p key={index}>
            <StoryText text={text}/> Original task contract <code>{origin.contract_cid}</code>
          </p>)}
        </StoryCard>;
      })}
      {[...unboundModels,...outputs].map(({origin,text},index)=><StoryCard key={`${origin.kind}-${index}`}
        ordinal={++ordinal} label={origin.kind === 'effect_set' ? 'Write declaration' : origin.kind === 'result' ? 'Result' : 'Ask model'}
        title={text}>
        {origin.kind === 'effect_set' ? <><p>Original Effect set <code>{origin.unit_id}</code></p>
          <ul>{origin.members.map(({declaration,write_fields},position)=><li key={position}>
            <strong>{declaration.effect_kind}</strong> · <code>{declaration.contract.kind === 'mapping'
              ? declaration.contract.declared_target : declaration.contract.resource_kind}</code>
            {write_fields.state === 'declared' && <p>Fields: {write_fields.fields.join(', ')}</p>}
          </li>)}</ul><p className="workspace-note">Preview and current approval are separate Run observations.</p></> :
          origin.kind === 'result' ? <p>Declared output <code>{origin.name}</code> · stage {origin.stage_ordinal + 1}</p> :
          origin.kind === 'model_task' && <p>Original task contract <code>{origin.contract_cid}</code></p>}
      </StoryCard>)}
    </ol>
  </section>;
}

function App() {
  const source = useMemo(() => createExplorerBrowserSource({origin: window.location.origin}), []);
  const [connected, connect] = useState(false), [plan, showPlan] = useState<PlanReadModel>();
  const [staticExplanation, showStaticExplanation] = useState<StaticExplanationReadModel>();
  const [run, showRun] = useState<RunObservationModel>(), [result, showResult] = useState<unknown>();
  const [follow, setFollow] = useState(false);
  const [queryShown, showQuery] = useState(true), [editing, setEditing] = useState(false);
  const [graph, showGraph] = useState(false);
  const [analyzedDraft, keepAnalyzedDraft] = useState<{text: string; format: string}>();
  const [selectedRef, selectRef] = useState<RunReference>();
  const [originalPlan, showOriginalPlan] = useState<OriginalRunPlanReadModel>();
  const [originalPresentation, showOriginalPresentation] = useState<OriginalRunPresentationReadModel | SavedExplanationReadModel>();
  const [programText, setProgramText] = useState('SELECT 1 AS answer');
  const [draftName, setDraftName] = useState<string>();
  const draftVersion = useRef(0);
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
    selectRef(undefined); keepAnalyzedDraft(undefined);
    showPlan(undefined); showStaticExplanation(undefined); showRun(undefined); showResult(undefined); showOriginalPlan(undefined); showOriginalPresentation(undefined); showLauncherProgram(false);
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
  useEffect(() => {
    const toggle = (event: KeyboardEvent) => {
      if (event.altKey || event.metaKey || event.ctrlKey || event.shiftKey ||
          !(event.target instanceof HTMLElement) ||
          event.target.closest('input, textarea, select, button, summary, a, [contenteditable]')) return;
      if (event.key.toLowerCase() === 'q') showQuery(value => !value);
      if (event.key.toLowerCase() === 'g') showGraph(value => !value);
    };
    window.addEventListener('keydown', toggle);
    return () => window.removeEventListener('keydown', toggle);
  }, []);
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
        const original = view.originalPlan.runRef;
        setRunReference(JSON.stringify(original, null, 2));
        selectRef(original);
        showOriginalPlan(view.originalPlan);
      }
    });
  };
  const openDraft = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = '';
    if (!file) return;
    const version = ++draftVersion.current;
    const extension = file.name.split('.').at(-1)?.toLowerCase();
    if (file.size > 60000 || !['sql', 'aql', 'json'].some(value=>value === extension)) {
      showError('Choose a SQL, AQL, or Program JSON file up to 60,000 bytes.');
      return;
    }
    try {
      const text = new TextDecoder('utf-8', {fatal: true}).decode(await file.arrayBuffer());
      if (version !== draftVersion.current) return;
      setProgramText(text); setDraftName(file.name);
      setProgramFormat(extension === 'json' ? 'program' : extension === 'aql' ? 'aql' : 'sql');
      showError('');
    } catch {
      if (version === draftVersion.current) showError('The selected file could not be read as UTF-8.');
    }
  };
  const readPlan = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const data = new FormData(event.currentTarget);
    const text = programText, format = programFormat;
    const locale = data.get('staticLocale') === 'ja' ? 'ja' : 'en';
    const explain = (event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') === 'static-explanation';
    const scope = epoch.current;
    void perform(async () => {
      runSelection.current++; setFollow(false); selectRef(undefined);
      showRun(undefined); showResult(undefined); showOriginalPlan(undefined); showOriginalPresentation(undefined);
      showLauncherProgram(false); showPlan(undefined); showStaticExplanation(undefined);
      const input = format === 'program' ? JSON.parse(text) : text;
      const options = format === 'program' ? {} : {format};
      if (explain) {
        const original = await source.staticExplanation(input, options, locale);
        if (scope === epoch.current) {
          showStaticExplanation(original); showPlan(original.plan); keepAnalyzedDraft({text, format});
          showGraph(false);
        }
      } else {
        const original = await source.plan(input, options);
        if (scope === epoch.current) {showPlan(original); keepAnalyzedDraft({text, format}); showGraph(true);}
      }
    });
  };
  const readRun = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const menu = event.currentTarget.closest('details');
    const data = new FormData(event.currentTarget);
    const name = String(data.get('name'));
    const selectedRead = (event.nativeEvent as SubmitEvent).submitter?.getAttribute('value') ?? 'run-explanation-context';
    const locale = data.get('locale') === 'ja' ? 'ja' : 'en';
    const selected = ++runSelection.current, scope = epoch.current; setFollow(false);
    const current = () => runSelection.current === selected && epoch.current === scope;
    void perform(async () => {
      const original: unknown = JSON.parse(runReference);
      if (!validRunRef(original)) throw new Error('Invalid Run reference');
      showRun(undefined);
      if (!sameRun(original, selectedRef)) {
        showResult(undefined); showOriginalPlan(undefined); showOriginalPresentation(undefined);
      }
      selectRef(original); showPlan(undefined); showStaticExplanation(undefined); showLauncherProgram(false);
      if (selectedRead === 'run-explanation-context' || selectedRead === 'run-presentation') {
        const view = await (selectedRead === 'run-explanation-context'
          ? source.runContext(original, locale) : source.runPresentation(original, {locale}));
        if (!current()) return;
        showOriginalPresentation(view); showGraph(false);
      } else if (selectedRead === 'run-plan') {
        const view = await source.runPlan(original);
        if (!current()) return;
        showOriginalPlan(view); showGraph(true);
      } else {
        const observation = await source.observe(original);
        if (!current()) return;
        showRun(observation);
        if (name && selectedRead === 'inspect') {
          const metadata = await source.describe(original, name);
          if (!current()) return;
          showResult(metadata);
        }
      }
      if (menu?.open) {
        const restoreFocus = menu.contains(document.activeElement);
        menu.open = false;
        if (restoreFocus) menu.querySelector('summary')?.focus();
      }
    });
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
  const readReview=(checkpoint:ReviewReference)=>{const selected=++reviewSelection.current,scope=epoch.current;setFollow(false);
    void perform(async()=>{showReview(null);const value=await source.reviewCheckpoint(checkpoint);
      if(epoch.current===scope&&selected===reviewSelection.current)showReview(value);});};
  const explanation = originalPresentation?.explanation;
  const story = selectedRef
    ? explanation?.state === 'projected' ? explanation.story : undefined
    : staticExplanation?.story;
  const context = selectedRef
    ? explanation?.state === 'projected' && 'context' in explanation ? explanation.context : []
    : staticExplanation?.context ?? [];
  const map = selectedRef ? originalPresentation?.plan ?? originalPlan?.plan : plan;
  const scopeKey = selectedRef ? selectedRef.runDefinitionCid : 'checked-program';
  const edited = analyzedDraft !== undefined &&
    (analyzedDraft.text !== programText || analyzedDraft.format !== programFormat);
  const currentBoundary = run && story && run.planBinding.compiledPlanCid === story.compiledPlanCid &&
    run.planBinding.logicalMapCid === story.logicalMapCid ? run.run.boundary?.step_id ?? undefined : undefined;
  const status = run ? run.run.status.replaceAll('_', ' ') : selectedRef ? 'Current status unavailable' :
    map ? 'Checked plan · no Run' : 'No Run selected';
  const supportedCheckpoint = connected && (checkpointCapabilities.list || checkpointCapabilities.read);
  return <div className="explorer-workspace">
    <header className="workspace-header">
      <div className="workspace-brand"><strong><span aria-hidden="true">&gt;</span> ActQL<span aria-hidden="true">_</span></strong>
        <span>Explorer</span><span className="breadcrumb-divider" aria-hidden="true">/</span>
        <span className="workspace-label">{selectedRef ? 'Original Run' : launcherProgram ? 'Launcher Plan' : draftName ?? 'Query draft'}</span>
      </div>
      <div className="workspace-actions">
        <button type="button" className="small" onClick={()=>showQuery(value=>!value)}
          aria-controls="query-pane" aria-expanded={queryShown}>{queryShown ? 'Hide query' : 'Show query'} <kbd>Q</kbd></button>
        <div className="view-switch" role="group" aria-label="Plan view">
          <button type="button" className="small" aria-pressed={!graph} onClick={()=>showGraph(false)}>Steps</button>
          <button type="button" className="small" aria-pressed={graph} onClick={()=>showGraph(true)}>Graph <kbd>G</kbd></button>
        </div>
        <span className="workspace-chip" data-tone={connected ? 'teal' : 'neutral'}>
          {connected ? 'Gateway connected' : 'Disconnected'}</span>
        <details className="shortcut-help"><summary aria-label="Keyboard shortcuts">?</summary>
          <div className="panel shortcut-card"><p><kbd>Q</kbd> Toggle query pane</p><p><kbd>G</kbd> Switch Steps and Graph</p></div>
        </details>
      </div>
    </header>
    <div className={'workspace-grid' + (queryShown ? '' : ' query-hidden')}>
      {queryShown && <aside id="query-pane" className="query-panel panel" aria-label="Query">
        <header><div><span className="connection-dot" data-connected={connected}/><strong>{editing ? 'Editing draft' : draftName ?? 'Query draft'}</strong></div>
          <button className="small" type="button" onClick={()=>setEditing(value=>!value)}>{editing ? 'Done' : 'Edit'}</button></header>
        {editing ? <label className="query-editor"><span className="sr-only">Program</span>
          <textarea value={programText} onChange={event=>{draftVersion.current++; setProgramText(event.target.value);}} maxLength={60000} rows={16}/>
        </label> : <ol className="query-lines" aria-label="Query text">
          {programText.split('\n').map((line,index)=><li key={index}><code>{line || ' '}</code></li>)}</ol>}
        <form className="query-controls" onSubmit={readPlan}>
          <label className="query-file">Open query file <input type="file" accept=".sql,.aql,.json" onChange={event=>void openDraft(event)}/></label>
          <label>Format <select name="format" value={programFormat} onChange={event=>setProgramFormat(event.target.value as typeof programFormat)}>
            <option value="sql">SQL</option><option value="aql">AQL</option><option value="aql-text">AQL text</option>
            <option value="program">Program JSON</option></select></label>
          <label>Language <select name="staticLocale" defaultValue="en"><option value="en">English</option><option value="ja">日本語</option></select></label>
          <div className="query-buttons">
            <button disabled={!connected || pending || !programText}>Read Plan</button>
            <button className="primary" value="static-explanation" disabled={!connected || pending || !programText}>Explain Effect</button>
          </div>
        </form>
        {selectedRef && <p className="query-note">This draft is separate from the selected Run's retained Plan.</p>}
        {launcherProgram && <p className="query-note">The launcher supplied the Plan. Edit this draft to check a different program.</p>}
      </aside>}
      <main className="story-workspace">
        {!connected && <form className="connection-form panel" onSubmit={session}>
          <label>One-use bootstrap <input name="bootstrap" type="password" autoComplete="off" maxLength={43} required disabled={pending}/></label>
          <button className="primary" disabled={pending}>Connect</button>
        </form>}
        {error && <p className="workspace-notice" role="alert">{error}</p>}
        <div className="story-heading">
          <p className="eyebrow">{selectedRef ? <><span>Run</span> <code>{run?.run.id ?? selectedRef.runDefinitionCid}</code></> :
            map ? 'Checked program' : 'Explorer debugger'}</p>
          {run && <p className="observation-line">Revision {run.run.controlRevision} · Updated {run.run.updatedAt}</p>}
          {story ? <StoryHeading story={story} context={context}/> : <h1>{selectedRef ?
            explanation?.state === 'not_projected' ? 'Saved explanation unavailable' : 'Original Run' :
            map ? 'Inspect the checked Plan' : 'Understand the query before running it'}</h1>}
          {explanation?.state === 'not_projected' && <p className="workspace-note">{explanation.reason === 'not_retained'
            ? 'No explanation was retained for this Run.' : 'The Run profile does not support this explanation.'}</p>}
        </div>
        {edited && !selectedRef && map && <p className="workspace-notice">The Story and Graph still show the previously checked draft. Read the edited query to update them.</p>}
        <div className="run-toolbar" aria-label="Run controls and status">
          <span className="workspace-chip" data-tone={run ? 'teal' : 'neutral'}>{selectedRef ? 'Original Run' : 'Static'}</span>
          <details className="toolbar-menu"><summary>Open Run</summary>
            <form className="panel run-reference-form" onSubmit={readRun}>
              <label>Original Run reference<textarea name="ref" value={runReference} onChange={event=>setRunReference(event.target.value)}
                maxLength={4096} rows={5} required
                placeholder={'{"namespaceId":"…","authorityScopeCid":"sha256:…","runDefinitionCid":"sha256:…"}'}/></label>
              <label>Named Result <input name="name" maxLength={1024}/></label>
              <label>Language <select name="locale" defaultValue="en"><option value="en">English</option><option value="ja">日本語</option></select></label>
              <div className="toolbar-form-actions">
                <button className="primary" disabled={!connected || pending}>Open Saved explanation</button>
                <button value="inspect" disabled={!connected || pending}>Inspect status</button>
                <button value="run-plan" disabled={!connected || pending}>Read Saved Plan</button>
                <button value="run-presentation" disabled={!connected || pending}>Read original Facts</button>
              </div>
            </form>
          </details>
          <button type="button" disabled title="Durable Step is unavailable in this Explorer">Step</button>
          <button type="button" disabled title="Durable Continue is unavailable in this Explorer">Continue</button>
          {connected && <button type="button" className="small" onClick={invalidate}>Disconnect</button>}
          <span className="run-status" role="status"><span className="status-dot"/>{pending ? 'Reading original…' : status}</span>
          {selectedRef && <details className="toolbar-menu terminal-menu"><summary>Terminal</summary>
            <div className="panel terminal-card"><p>Use this original reference with an authorized CLI on the same Host.</p>
              <pre aria-label="Original Run reference">{JSON.stringify(selectedRef, null, 2)}</pre>
            </div>
          </details>}
        </div>
        <div className="inspection-strip">
          {run && <label className="actql-run-follow"><input type="checkbox" checked={follow}
            disabled={pending || run.run.terminal} onChange={event=>setFollow(event.target.checked)}/>Follow this Run</label>}
          <span>Step controls unavailable</span>
          <span>Samples {run && run.sample.state !== 'unavailable' ? run.sample.state : 'unavailable'}</span>
          <span>Preview unavailable</span>
        </div>
        {graph && map && <PlanExplorer model={map} initialView="flow" scopeKey={`${epoch.current}:${scopeKey}:${map.logicalMapCid}`}/>}
        {!graph && story && <StorySteps key={`${scopeKey}:${story.logicalMapCid}:${story.locale}`}
          story={story} context={context} boundary={currentBoundary}/>}
        {graph && !map && <p className="workspace-note">Read a Plan or open an original Run to see its Graph.</p>}
        {!graph && !story && map && <p className="workspace-note">This read supplies a logical map. Choose Graph to inspect it.</p>}
        {run && <details className="workspace-tools panel"><summary>Current Run observations</summary><RunInspector model={run}/></details>}
        {result !== undefined && <details className="workspace-tools panel"><summary>Named Result metadata</summary><pre>{JSON.stringify(result, null, 2)}</pre></details>}
        {(supportedCheckpoint || run?.run.status === 'waiting_checkpoint') &&
          <details className="workspace-tools panel"><summary>Checkpoint review</summary>
            <CheckpointPanel page={checkpointPage} review={review} pending={pending}
              canList={connected&&checkpointCapabilities.list} canRead={connected&&checkpointCapabilities.read}
              onList={listCheckpoints} onRead={readReview}/>
          </details>}
    {(cancellationEnabled || originalCancellation) && <details className="workspace-tools panel"><summary>Cancellation</summary>
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
    </details>}
      </main>
    </div>
  </div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
