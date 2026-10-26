import {parse} from 'acorn';

// Recognize the bounded registration forms used by the public resource suites.
// Read captured source bytes only; importing a suite would execute its tests,
// while importing a registry would bypass the validator's source snapshot.
export function registeredResourceEnvironmentCase(item, source, graphRegistry = '', operation) {
  if (item.suite === 'node:embedded_property_names') {
    const metadata = /for\s*\(const\s*\[kind,title\]\s*of\s*\[([\s\S]*?)\]\)\s*\{([\s\S]*?)\n\}/u.exec(source);
    if (item.case === 'compoundCompletionProgram' && metadata) {
      const registration = metadata[2].replace(/\s+/gu, '');
      const titles = [...metadata[1].matchAll(/\['(join|nest|interval|asof)','([^']+)'\]/gu)];
      if (titles.some(([, kind, title]) => title === item.fixture &&
          item.role === `${kind}_compound_metadata_public`) &&
          registration.includes('test(title,') &&
          registration.includes('=>verifyRetainedNames(t,`${kind}-source-metadata`,') &&
          registration.includes('id=>compoundCompletionProgram(id,kind,true),rows,contract)')) {
        return true;
      }
    }
    const sequence = /for\s*\(const\s+overlap\s+of\s+\['allow','disallow'\]\)\s*\{([\s\S]*?)\n\}/u.exec(source);
    if (item.case === 'sequencePositionProgram' && sequence) {
      const registration = sequence[1].replace(/\s+/gu, '');
      if (sequence[1].includes(`test(\`${item.fixture}\`,`) &&
          registration.includes('=>verifyRetainedNames(t,`sequence-position-${overlap}`,') &&
          registration.includes('id=>sequencePositionProgram(id,overlap),')) {
        return true;
      }
    }
  }
  if (item.suite === 'node:graph_public_host') {
    const registration = source.replace(/\s+/gu, '');
    const registry = graphRegistry.replace(/\s+/gu, '');
    const registryLoop = `export const graphPublicHostCases = Object.freeze(['local','remote'].flatMap(mode =>
      Object.entries(profiles).flatMap(([profile,title]) => profile === 'graph-mean'
        ? ['basic', 'asymmetric'].map(partition => Object.freeze({mode,profile,partition,
          name:\`\${title} \${mode}\${partition === 'basic' ? '' : ' (asymmetric)'}\`}))
        : [Object.freeze({mode,profile,name:\`\${title} \${mode}\`})])));`;
    if (!registration.includes("import{graphPublicHostCases}from'./fixtures/graph-host-cases.mjs';") ||
        !registration.includes('for(const{mode,profile,name,partition}ofgraphPublicHostCases){test(name,') ||
        !graphRegistry.includes('name:`${title} ${mode}`') ||
        !registry.includes(registryLoop.replace(/\s+/gu, ''))) {
      return false;
    }
    const profiles = /^const profiles = \{([\s\S]*?)^\};/mu.exec(graphRegistry);
    const projectionBody = /if \(profile === 'graph-projections'\) \{([\s\S]*?)\n    \}/u
      .exec(source)?.[1].replace(/\s+/gu, '') ?? '';
    for (const [, profile, title] of profiles?.[1].matchAll(/^\s*'([^']+)': '([^']+)',$/gmu) ?? []) {
      const selection = operation === 'node_rows' && profile === 'presence-selection' &&
        registration.includes("presenceFilterScenario(empty,profile==='presence-selection')");
      const projection = ['node_rows', 'edge_rows'].includes(operation) &&
        profile === 'graph-projections' &&
        projectionBody.includes("for(constprojectionof['node_rows','edge_rows']){") &&
        projectionBody.includes("document.stages[0].steps[4]={from:'g',[projection]:true,as:'rows'}") &&
        projectionBody.includes('presenceRows[projection]');
      if (item.role === 'graph_projection_public_store' && (selection || projection) &&
          ['local', 'remote'].some(mode => item.fixture === `${title} ${mode}`)) return true;
      const cancellation = {
        reach: ['graph-reach', 'reach'],
        shortest_path: ['graph-shortest', 'shortest'],
        graft_graph: ['graph-graft', 'graft'],
        mean_graphs: ['graph-mean', 'mean'],
      }[operation];
      if (cancellation?.[0] !== profile ||
          item.role !== `${cancellation[1]}_public_in_flight_cancel_cleanup` ||
          item.case !== 'assertOperationCancellation' ||
          !['local', 'remote'].some(mode => item.fixture ===
            `${title} ${mode}${profile === 'graph-mean' ? ' (asymmetric)' : ''}`)) continue;
      // This is the existing installed operation barrier, after positive work,
      // with stop, nonpublication, cleanup and same-request non-reexecution.
      // A basic Mean success or an earlier constructor is not this case.
      const barrier = /if \(name === 'local_compute_advanced' && detail\.task === cancellationTask\) \{([\s\S]*?)\n      \}/u
        .exec(source)?.[1].replace(/\s+/gu, '') ?? '';
      const body = /async function assertOperationCancellation\(sample, task\) \{([\s\S]*?)\n    \}/u
        .exec(source)?.[1].replace(/\s+/gu, '') ?? '';
      const requiredBarrier = ['assert.ok(BigInt(detail.work)>0n)',
        'cancellationBarrier.resolve(detail)', 'awaitreleaseCancellation.promise'];
      const requiredBody = ['cancellationTask=task', 'awaitcancelled.cancel()',
        'cancellationBarrier.promise', 'assert.equal(observation.task,cancellationTask)',
        'assert.equal(pending.control.cancellation_requested,true)',
        "assert.notEqual(pending.control.physical_stop,'confirmed')",
        "assert.notEqual(pending.status,'cancelled')",
        'assert.equal(completed(),completedBefore)',
        'assert.equal(snapshots.has(cancelled.ref.runDefinitionCid),false)',
        'releaseCancellation.resolve()', "assert.equal(stopped.status,'cancelled'",
        "assert.equal(stopped.control.physical_stop,'confirmed')",
        'awaitassert.rejects(cancelled.result(name).all())',
        'assert.deepEqual(repeated.ref,cancelled.ref)',
        'assert.equal(starts(),startsBefore+1)',
        "assert.equal(physicalSteps.filter(name=>name==='local_compute_advanced').length,advanced)",
        'assert.deepEqual(awaitreaddir(`${directory}/carrier-snapshots`),[])'];
      const operationCall = profile === 'graph-graft'
        ? registration.includes('if(graft)awaitassertOperationCancellation(graphGraftSourceSuccesses[0],3)')
        : registration.includes("if(profile!=='graph-mean'||partition==='asymmetric'){") &&
          registration.includes("graphReachSourceSuccesses.find(sample=>sample.name==='graph-reach-json-connected-out')") &&
          registration.includes("graphShortestSourceSuccesses.find(sample=>sample.name==='graph-shortest-json-weighted-parallel-edges')") &&
          registration.includes(':graphMeanSourceOracles[0]') &&
          registration.includes('awaitassertOperationCancellation(cancellationSample,3)');
      if (operationCall && requiredBarrier.every(marker => barrier.includes(marker)) &&
          requiredBody.every(marker => body.includes(marker))) return true;
    }
  }
  return false;
}

// Preserve offsets while making comments and literal text opaque to declaration
// and brace discovery. This is a narrow source guard, not a language parser.
function lexicalSource(source, maskLiterals) {
  const chars = source.split('');
  let index = 0;
  const blank = (start, end) => {
    for (let cursor = start; cursor < end; cursor++) {
      if (chars[cursor] !== '\n') chars[cursor] = ' ';
    }
  };
  while (index < source.length) {
    const start = index;
    if (source.startsWith('//', index)) {
      const end = source.indexOf('\n', index);
      index = end < 0 ? source.length : end;
      blank(start, index);
    } else if (source.startsWith('/*', index)) {
      let depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) { depth++; index += 2; }
        else if (source.startsWith('*/', index)) { depth--; index += 2; }
        else index++;
      }
      blank(start, index);
    } else if (['"', "'", '`'].includes(source[index])) {
      const quote = source[index++];
      while (index < source.length) {
        if (source[index] === '\\') index += 2;
        else if (source[index++] === quote) break;
      }
      if (maskLiterals) blank(start, index);
    } else index++;
  }
  return chars.join('');
}

function declaredFunctionBody(source, name) {
  const code = lexicalSource(source, true);
  const declaration = new RegExp(`(?:async\\s+function|function|pub\\s+fn|fn)\\s+${name}\\s*\\(`, 'gu');
  const matches = [...code.matchAll(declaration)];
  if (matches.length !== 1) return '';
  let cursor = matches[0].index + matches[0][0].length;
  let depth = 1;
  while (cursor < code.length && depth > 0) {
    if (code[cursor] === '(') depth++;
    if (code[cursor] === ')') depth--;
    cursor++;
  }
  const start = code.indexOf('{', cursor);
  if (start < 0) return '';
  cursor = start + 1;
  depth = 1;
  while (cursor < code.length && depth > 0) {
    if (code[cursor] === '{') depth++;
    if (code[cursor] === '}') depth--;
    cursor++;
  }
  return depth === 0 ? lexicalSource(source.slice(start + 1, cursor - 1), false)
    .replace(/\s+/gu, '') : '';
}

function directHostSourceParts(source, name) {
  try {
    const comments = [];
    const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module',
      onComment: (_block, _text, start, end) => comments.push({start, end})});
    const functions = ast.body.filter(node => node.type === 'FunctionDeclaration' &&
      node.id?.name === 'fusedGraphHostCancellation');
    const tests = ast.body.filter(node => node.type === 'ExpressionStatement' &&
      node.expression.type === 'CallExpression' &&
      node.expression.callee.type === 'Identifier' && node.expression.callee.name === 'test' &&
      node.expression.arguments[0]?.value === name);
    if (functions.length !== 1 || tests.length !== 1) return {};
    const declarations = functions[0].body.body.filter(node =>
      node.type === 'VariableDeclaration' && node.kind === 'const')
      .flatMap(node => node.declarations);
    const normalized = node => JSON.stringify(node, (key, value) =>
      ['start', 'end', 'raw'].includes(key) ? undefined : value);
    // These authored shapes are the premises of the independent 29-unit
    // constructor bound. More columns, nodes, or edges need a new proof.
    for (const [binding, expression] of [
      ['values', `({schema:{node_key:{type:'number',nullable:false}},
        rows:Array.from({length:8},(_,index)=>({node_key:index+1}))})`],
      ['definition', `({name:'N',key:['node_key'],labels:[]})`],
      ['constructor', `({version:'actql-graph-constructor/0.1',
        nodes:[{...definition,from:'rows'}],edges:[]})`],
    ]) {
      const declared = declarations.filter(node => node.id.type === 'Identifier' &&
        node.id.name === binding);
      const expected = parse(expression, {ecmaVersion: 'latest'}).body[0].expression;
      if (declared.length !== 1 || normalized(declared[0].init) !== normalized(expected)) return {};
    }
    const withoutComments = node => {
      const chars = source.slice(node.start, node.end).split('');
      for (const comment of comments) {
        for (let index = Math.max(comment.start, node.start);
          index < Math.min(comment.end, node.end); index++) chars[index - node.start] = ' ';
      }
      return chars.join('').replace(/\s+/gu, '');
    };
    return {body: withoutComments(functions[0].body), registration: withoutComments(tests[0])};
  } catch {
    return {};
  }
}

// Internal owned-input entrypoints need their own delivered Host-driver proof.
// A selected public task's cancellation cannot establish this constructor lifetime.
export function registeredDirectTraversalHostCase(operation, source, preparer) {
  const title = operation === 'reach' ? 'Reach'
    : operation === 'shortest_path' ? 'Shortest' : undefined;
  if (title === undefined) return false;
  const name = `unselected ${title} stops after exact constructor work through the Local Host driver`;
  const {body, registration} = directHostSourceParts(source, name);
  if (!registration?.includes(`awaitfusedGraphHostCancellation('${operation}')`)) return false;
  const fixture = declaredFunctionBody(preparer, 'subgraph_cancel_create');
  return [
    "rows:Array.from({length:8}",
    'values.rows.length*(1+1+1)+2*1+3',
    "JSON.stringify([{graph:{...constructor,nodes:[{...definition,from:'prior'}]},as:'g'},consumer])",
    "operation==='reach'?{from:'g',reach:{start:{where:'true'},direction:'out',max_depth:1},as:'answer'}",
    ":{from:'g',shortest_path:{source:{where:'true'},target:{where:'true'},selection:'each_pair',direction:'out',max_hops:1},as:'answer'}",
    'totalWork+=work', 'totalWork>constructorWork',
    'setTimeout(()=>{delivered=true;abort.abort();},0)',
    "assert.equal(fixture.subgraphCancelStopped(fused),false,'requestisnotstopacknowledgement')",
    'assert.equal(fixture.subgraphCancelInputAvailable(fused),true)',
    "assert.fail('cancelledfusedGraphconsumermustnotpublish')",
    'localStrategyContribution(runtime,undefined,checked).run(',
    'assert.equal(fixture.subgraphCancelStopped(fused),true)',
    "assert.equal(advances,settledAdvances,'cleanupneverresumesexecution')",
  ].every(marker => body.includes(marker)) && [
    '@execution.completion_preparation_selected_step(', '),None,)',
    'assert_eq(@execution.generated_sequence_step_count(generated),2)',
    'assert_eq(@execution.completed_row_count(output),8)',
    '@execution.constrain_generated_traversal(generated,1,8L*8L,8L)',
    '@execution.bind_completed_input(consumer,0,owner,output)',
    '@local_sga_provider.provider(',
    '@local_connector.start_managed_provider_with_execution(',
  ].every(marker => fixture.includes(marker)) &&
    declaredFunctionBody(preparer, 'subgraph_cancel_request')
      .includes('@local_connector.cancel_managed_provider(f.execution)') &&
    declaredFunctionBody(preparer, 'subgraph_cancel_cleanup')
      .includes('@local_connector.cleanup_managed_provider(f.execution)');
}
