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
