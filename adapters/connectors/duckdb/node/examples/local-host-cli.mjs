// Minimal noninteractive Local Host CLI for the example application.
//
//   init    --directory <dir> [--account-config <file>] [--reviewer <id>]
//   run     --config <host.json> --database <db> --environment <file>
//           --environment-cid <cid> --program <file> --parameters <file>
//           [--schema main] [--table records] [--native-ms 5] [--resident]
//   list    --config <host.json>
//   inspect <checkpoint> --config <host.json>
//   approve <checkpoint>... --config <host.json> --signer <file> [--decided-at <time>]
//   reject  <checkpoint>... --config <host.json> --signer <file> [--decided-at <time>]
//   resume  <checkpoint|prepare-attempt> --config <host.json> [--claimant <id>] [--lease-ms <n>]
//   status  <run|prepare-attempt|checkpoint> --config <host.json>
//   cancel  <checkpoint|prepare-attempt> --config <host.json>
//   retire  --config <host.json>
//
// Output is JSON on stdout. The CLI never prompts and never reads stdin: TTY
// presence, EOF or a timeout cannot approve, reject or dispatch anything. A
// deferred decision exits 0 with `waiting_checkpoint`. Exit 1 is a refused,
// failed or partially answered command; exit 2 is an invalid command line.
//
// `init` also creates the private-evidence key (`state/private-evidence.key`,
// owner-only). After a command that can end a continuation the CLI retires
// the private evidence of continuations with no remaining need; waiting
// evidence is kept. A deletion that fails stays owned and is reported under
// `retention`; `retire` retries it.
import {parseArgs} from 'node:util';
import {initializeLocalHost, openLocalHost, readSigner} from './local-host.mjs';

const usage = code => Object.assign(new Error(code), {code, usage: true});

const COMMANDS = new Set(['init', 'run', 'list', 'inspect', 'approve', 'reject',
  'resume', 'status', 'cancel', 'retire']);
// Commands after which a continuation can have ended.
const SETTLES = new Set(['run', 'list', 'approve', 'reject', 'resume', 'cancel']);

async function main(argv) {
  const [command, ...rest] = argv;
  if (!COMMANDS.has(command)) throw usage('UnknownCommand');
  let parsed;
  try {
    parsed = parseArgs({args: rest, allowPositionals: true, options: {
      config: {type: 'string'},
      directory: {type: 'string'},
      'account-config': {type: 'string'},
      reviewer: {type: 'string'},
      principal: {type: 'string'},
      database: {type: 'string'},
      environment: {type: 'string'},
      'environment-cid': {type: 'string'},
      program: {type: 'string'},
      parameters: {type: 'string'},
      schema: {type: 'string', default: 'main'},
      table: {type: 'string', default: 'records'},
      'native-ms': {type: 'string', default: '5'},
      resident: {type: 'boolean', default: false},
      signer: {type: 'string'},
      'decided-at': {type: 'string'},
      claimant: {type: 'string'},
      'lease-ms': {type: 'string'},
      json: {type: 'boolean', default: true},
    }});
  } catch (error) {
    throw usage(error.code ?? 'InvalidArguments');
  }
  const {values, positionals} = parsed;
  if (command === 'init') {
    if (!values.directory || positionals.length > 0) throw usage('Required --directory');
    return {exit: 0, output: await initializeLocalHost({directory: values.directory,
      accountConfig: values['account-config'], reviewer: values.reviewer,
      principal: values.principal})};
  }
  if (!values.config) throw usage('Required --config');
  const one = () => {
    if (positionals.length !== 1) throw usage('ExactlyOneReference');
    return positionals[0];
  };
  const signer = (command === 'approve' || command === 'reject')
    ? (values.signer ? await readSigner(values.signer) : (() => {
      throw usage('Required --signer');
    })())
    : undefined;
  if (command === 'run') {
    for (const key of ['database', 'environment', 'environment-cid', 'program',
      'parameters']) {
      if (!values[key]) throw usage(`Required --${key}`);
    }
    if (positionals.length > 0) throw usage('UnexpectedArgument');
  }
  let leaseMs;
  if (values['lease-ms'] !== undefined) {
    leaseMs = Number(values['lease-ms']);
    if (!Number.isSafeInteger(leaseMs) || leaseMs < 1) throw usage('Invalid --lease-ms');
  }
  const host = await openLocalHost(values.config);
  try {
    const result = await dispatch(host, command, values, positionals, one,
      signer, leaseMs);
    if (!SETTLES.has(command)) return result;
    let retention;
    try { retention = await host.retire(); }
    catch (error) { retention = {error: error.code ?? error.message}; }
    return retention.error === undefined && retention.pending.length === 0
      ? result : {...result, output: {...result.output, retention}};
  } finally {
    await host.close();
  }
}

async function dispatch(host, command, values, positionals, one, signer, leaseMs) {
  switch (command) {
    case 'run': {
      const output = await host.run({
        database: values.database,
        environment: values.environment,
        environmentCid: values['environment-cid'],
        program: values.program,
        parameters: values.parameters,
        schema: values.schema,
        table: values.table,
        nativeMilliseconds: values['native-ms'],
        resident: values.resident,
      });
      return {exit: ['succeeded', 'waiting_checkpoint'].includes(output.status) ? 0 : 1,
        output};
    }
    case 'list':
      return {exit: 0, output: {pending: host.list()}};
    case 'inspect': {
      const output = host.inspect(one());
      return {exit: output === undefined ? 1 : 0,
        output: output ?? {status: 'not_found'}};
    }
    case 'status': {
      const output = host.status(one());
      return {exit: output === undefined ? 1 : 0,
        output: output ?? {status: 'not_found'}};
    }
    case 'approve':
    case 'reject': {
      if (positionals.length === 0) throw usage('CheckpointReferenceRequired');
      const results = await host.answer(positionals,
        command === 'approve' ? 'approved' : 'rejected',
        {signer, decidedAt: values['decided-at']});
      const ok = results.every(item =>
        item.status === 'committed' || item.status === 'duplicate');
      return {exit: ok ? 0 : 1, output: {results}};
    }
    case 'cancel': {
      const output = host.cancel(one());
      return {exit: ['cancelled', 'duplicate'].includes(output.outcome) ? 0 : 1,
        output};
    }
    case 'resume': {
      // Test-only diagnostic: hold the claimed continuation before any
      // work so a superseding claimant can be exercised across processes.
      const hold = Number(process.env.ACTQL_EXAMPLE_HOLD_AFTER_CLAIM_MS ?? 0);
      const output = await host.resume(one(), {
        ...(values.claimant ? {claimant: values.claimant} : {}),
        ...(leaseMs !== undefined ? {leaseMs} : {}),
        holdAfterClaimMs: Number.isSafeInteger(hold) && hold > 0 ? hold : 0,
      });
      return {exit: ['succeeded', 'waiting_checkpoint', 'completed']
        .includes(output.status) ? 0 : 1, output};
    }
    case 'retire': {
      if (positionals.length > 0) throw usage('UnexpectedArgument');
      const output = await host.retire();
      return {exit: output.pending.length === 0 ? 0 : 1, output};
    }
    default:
      throw usage('UnknownCommand');
  }
}

try {
  const {exit, output} = await main(process.argv.slice(2));
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  process.exitCode = exit;
} catch (error) {
  process.stderr.write(`${JSON.stringify({error: error.code ?? error.message,
    ...(error.runtimeCode ? {runtime_code: error.runtimeCode} : {}),
    ...(error.cause ? {detail: String(error.cause?.message ?? error.cause)} : {}),
  })}\n`);
  process.exitCode = error.usage ? 2 : 1;
}
