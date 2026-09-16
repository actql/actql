import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {exportPhysicalValue, bindPhysicalValue} from '../physical-values.mjs';
import {checked} from '../runtime-result.mjs';
import {runFixedCompute, matchesFixedCompute, releaseFixedCompute} from '../fixed-compute.mjs';
import {createLocalRetainedStore} from '../../store-local/files.mjs';
import {registerManagedInput, withManagedInputFile} from '../../store-local/managed-representations.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const limits = {maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  maxChunkRows: 2, maxChunkBytes: 4096, memoryBytes: 128 * 1024 * 1024, threads: 1};
const profileCid = 'sha256:161b405aa85064521a44076212bb266d93f166fa1b383ca8948a87923d797527';
const fieldsFrame = fields => JSON.stringify(fields.map(({name, type}) =>
  [name, type.id, type.precision == null ? null : String(type.precision),
    type.scale == null ? null : String(type.scale)]));

test('managed selected Compute verifies actual DuckDB transport and exact physical holding without output CID', async () => {
  const exec = promisify(execFile);
  for (const target of ['connectors/duckdb/host_node', 'duckdb_conformance']) {
    await exec('moon', ['build', '--target', 'js', '--release', `src/${target}`], {cwd: root});
  }
  const moon = await import(pathToFileURL(join(root, '_build/js/release/build/connectors/duckdb/host_node/host_node.js')));
  const fixture = await import(pathToFileURL(join(root, '_build/js/release/build/duckdb_conformance/duckdb_conformance.js')));
  const source = await readFile(join(root, 'src/query_integration/pinned_engine_contracts_wbtest.mbt'), 'utf8');
  const contracts = [...source.matchAll(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")/g)].map(match => JSON.parse(match[1]));
  const profile = checked(fixture.managedFileProfile(await readFile(join(root,
    'spec/contracts/actql-managed-retained-execution.json'), 'utf8')));
  const pipeline = JSON.stringify([
    {values: {schema: {id: {type: 'number', nullable: false}, amount: {type: 'string', nullable: true}},
      rows: [{id: 3, amount: '日本語'}, {id: 1, amount: 'unused'},
        {id: 4, amount: null}, {id: 3, amount: '日本語'}]}, as: 'seed'},
    {select: ['id', 'amount']},
  ]);
  for (const empty of [false, true]) for (const revoke of ['none', 'transport', 'policy', 'completion-input']) {
    const configured = fixture.typedFixedCreate(pipeline, empty ? 'id > 9' : 'id > 2', ...contracts);
    const directory = await mkdtemp(join(tmpdir(), 'actql-managed-compute-'));
    const store = await createLocalRetainedStore({parentDirectory: directory, capacityBytes: 65536, maxFrameBytes: 4096});
    let result, output, run, attempt, port, consume, completed, downstreamOutput, downstreamCompleted;
    try {
      run = checked(moon.computeHostOpen(fixture.ownedFixedConfiguration(configured),
        current => current === attempt && matchesFixedCompute(result, port, consume)));
      attempt = moon.computeHostAttempt(run);
      // Installed test Host policy: this invocation asks only for managed
      // retained reading, not legacy publication or another demanded identity.
      let authorized = true;
      assert.throws(() => checked(moon.computeHostManagedPrepare(run, profile, () => false)));
      const completion = checked(moon.computeHostManagedPrepare(run, profile, () => authorized));
      port = Object.freeze({
        importCount: () => moon.computeHostImportCount(run),
        rowCount: index => Number(checked(moon.computeHostCount(run, index, false))),
        columnCount: index => Number(checked(moon.computeHostCount(run, index, true))),
        createSql: index => checked(moon.computeHostSql(run, 0, index)),
        insertSql: index => checked(moon.computeHostSql(run, 1, index)),
        parameter: (index, row, column) => JSON.parse(checked(moon.computeHostParameter(run, row, column, false, index))),
        querySql: () => checked(moon.computeHostSql(run, 2, 0)),
        queryParameters: () => Array.from({length: moon.computeHostQueryParameterCount(run)},
          (_, index) => JSON.parse(checked(moon.computeHostParameter(run, 0, index, true, 0)))),
      });
      const writer = store.reserve(65536);
      await writer.start();
      const begin = fields => output ??= checked(moon.computeHostManagedOutputBegin(run, fieldsFrame(fields)));
      const observed = [];
      consume = async chunk => {
        begin(chunk.fields);
        checked(moon.managedOutputAccept(output, chunk.rowCount, JSON.stringify(chunk.columns)));
        // Fixture-only physical frame codec, not a registered public Artifact.
        // Values are native transport columns, not canonical logical row JSON.
        await writer.appendBytes(Buffer.from(JSON.stringify({rows: chunk.rowCount, columns: chunk.columns}) + '\n'));
        observed.push(...chunk.columns[0]);
      };
      result = await runFixedCompute(port, limits, {maxRows: 4, maxCells: 8}, consume);
      begin(result.value.fields);
      checked(moon.managedOutputFinish(output));
      const body = await writer.sealPhysical();
      checked(moon.managedOutputRetain(output, BigInt(body.bytes), () => body.available()));
      assert.deepEqual(observed, empty ? [] : ['日本語', null, '日本語']);
      assert.equal(moon.managedOutputComputeVerified(output), false);
      assert.equal(moon.managedOutputAvailable(output), true, 'holding is not execution proof');
      if (revoke === 'transport') {
        releaseFixedCompute(result);
        assert.throws(() => checked(moon.managedOutputVerifyCompute(output)));
        assert.equal(moon.managedOutputAvailable(output), false);
        assert.equal(body.available(), true, 'revocation is not physical cleanup');
      } else {
        checked(moon.managedOutputVerifyCompute(output));
        assert.equal(moon.managedOutputComputeVerified(output), true);
        assert.equal(checked(moon.managedOutputMeasurements(output))[0], empty ? 0 : 3);
        assert.throws(() => checked(moon.computeHostComplete(run)), 'old completion cannot consume managed output');
        const foreignRun = checked(moon.computeHostOpen(fixture.ownedFixedConfiguration(configured), () => false));
        try {
          const foreignCompletion = checked(moon.computeHostManagedPrepare(foreignRun, profile, () => true));
          assert.throws(() => checked(moon.managedOutputCompleteCompute(output, foreignCompletion)),
            'equal setup cannot authorize another attempt output');
          assert.equal(moon.managedOutputComputeVerified(output), true, 'foreign port failure must not revoke the actual attempt');
        } finally { moon.computeHostClose(foreignRun); }
        if (revoke === 'policy') {
          authorized = false;
          assert.throws(() => checked(moon.managedOutputCompleteCompute(output, completion)));
          authorized = true;
          assert.throws(() => checked(moon.managedOutputCompleteCompute(output, completion)),
            'failed completion cannot revive when policy changes back');
          assert.equal(moon.managedOutputComputeVerified(output), false);
          continue;
        }
        completed = checked(moon.managedOutputCompleteCompute(output, completion));
        assert.equal(moon.managedCompletedProfileCid(completed), profileCid);
        assert.equal(moon.managedCompletedAvailable(completed), true);
        assert.throws(() => checked(moon.managedOutputCompleteCompute(output, completion)), 'completion is single use');
        releaseFixedCompute(result);
        assert.equal(moon.managedOutputComputeVerified(output), false);
        assert.equal(moon.managedCompletedAvailable(completed), true, 'sealed independent output is not a live input verification');
        const material = moon.managedOutputMaterial(output);
        const codec = `sha256:${'4'.repeat(64)}`; // Fixture physical-frame interpretation only.
        registerManagedInput(material, input => moon.managedInputMatchesMaterial(input, material), store, body, codec);
        const foreign = fixture.typedFixedCreate(pipeline, empty ? 'id > 9' : 'id > 2', ...contracts);
        assert.equal(fixture.ownedFixedManagedInput(foreign, completed), undefined);
        for (let consumer = 0; consumer < 2; consumer++) {
          const input = fixture.ownedFixedManagedInput(configured, completed);
          assert.ok(input);
          // Two separate consumer ledgers both charge the full logical input.
          // This call consumes stored metadata, not cells or physical bytes.
          assert.deepEqual(fixture.ownedFixedManagedInputUsage(configured, input),
            empty ? [0, 0, 0, 0] : [3, 6, 26, 3]);
          let reads = 0;
          const use = async file => {
            reads++;
            assert.equal(store.status().activeReaders, 1);
            const frames = (await readFile(file.path, 'utf8')).trim();
            return frames ? frames.split('\n').flatMap(frame => JSON.parse(frame).columns[0]) : [];
          };
          await assert.rejects(withManagedInputFile(material, input, codec, () => false, use),
            {code: 'ManagedInputUnauthorized'});
          await assert.rejects(withManagedInputFile(material, null, codec, () => true, use),
            {code: 'ManagedInputUnavailable'});
          await assert.rejects(withManagedInputFile(material, input, `sha256:${'5'.repeat(64)}`, () => true, use),
            {code: 'UnsupportedManagedCodec'});
          assert.equal(reads, 0);
          let integrityReadBytes = 0;
          const read = await withManagedInputFile(material, input, codec, () => true, use,
            undefined, bytes => { integrityReadBytes += bytes; });
          assert.deepEqual(read, empty ? [] : ['日本語', null, '日本語']);
          assert.equal(reads, 1);
          assert.equal(integrityReadBytes, body.bytes);
          assert.equal(store.status().activeReaders, 0);
          let authorizedRead = true;
          await assert.rejects(withManagedInputFile(material, input, codec, () => authorizedRead,
            async file => { const read = await use(file); authorizedRead = false; return read; }),
          {code: 'ManagedInputUnauthorized'});
          assert.equal(store.status().activeReaders, 0);
          assert.equal(moon.managedCompletedAvailable(completed), true,
            'failed additional use does not undo prior completion');
        }
        // Compile the receiving operation from its actual checked owner, not
        // test-authored aggregate SQL or a fabricated legacy CID input.
        const countInput = fixture.ownedFixedManagedCountInput(configured, completed);
        assert.deepEqual(fixture.managedColumnMeasurement(countInput),
          empty ? [0, 0, 0, 0, 0] : [3, 26, 3, 11, 1]);
        assert.deepEqual(fixture.ownedFixedManagedInputUsage(configured, countInput),
          empty ? [0, 0, 0, 0] : [3, 6, 26, 3]);
        const nativeQuery = fixture.managedFixedQuery(countInput);
        assert.equal(fixture.managedFixedQueryMatches(nativeQuery, countInput), true);
        assert.equal(fixture.managedFixedQueryMatches(nativeQuery,
          fixture.ownedFixedManagedCountInput(configured, completed)), false,
        'same output is not the same receiving use');
        const [createSql, querySql] = fixture.managedFixedQuerySql(nativeQuery);
        let nativeSettled = false;
        let downstreamAuthorized = true;
        let invalidateInputOnAuthorization = false;
        const downstreamPort = checked(fixture.managedQueryCompletion(nativeQuery, profile, ...contracts, 10000,
          () => {
            if (invalidateInputOnAuthorization) moon.managedOutputCancel(output);
            return downstreamAuthorized;
          },
          () => {
            if (nativeSettled && revoke === 'completion-input') invalidateInputOnAuthorization = true;
            return nativeSettled && fixture.managedFixedQueryMatches(nativeQuery, countInput);
          }));
        downstreamOutput = checked(moon.managedOutputOpen(moon.managedInputOutputValues(downstreamPort),
          JSON.stringify([['n', 'DOUBLE', null, null]]), fixture.managedFilePhysicalLimits(),
          fixture.managedFileTransportLimits(), 100));
        const database = await DuckDBInstance.create(':memory:', {threads: '1', memory_limit: '128MB'});
        const connection = await database.connect();
        try {
          await connection.run(createSql);
          let integrityBytes = 0;
          const rows = await withManagedInputFile(material, countInput, codec,
            () => fixture.managedFixedQueryMatches(nativeQuery, countInput), async file => {
              assert.equal(store.status().activeReaders, 1);
              if (!empty) {
                // Fixture-only frame decoder inside DuckDB. No JS cell decode
                // or parameter INSERT, and no second Core value admission.
                const path = `'${file.path.replaceAll("'", "''")}'`;
                await connection.run(`INSERT INTO managed_input SELECT unnest(columns[1])
                  FROM read_json(${path}, format='newline_delimited',
                    columns={rows: 'BIGINT', columns: 'VARCHAR[][]'})`);
              }
              return (await connection.runAndReadAll(querySql)).getRowObjects();
            }, undefined, bytes => { integrityBytes += bytes; });
          assert.deepEqual(rows, [{n: empty ? 0 : 3}]);
          assert.equal(integrityBytes, body.bytes);
          assert.equal(store.status().activeReaders, 0);
          // Only this awaited exact native query supplies the downstream values.
          const columns = [[exportPhysicalValue(rows[0].n, {id: 'DOUBLE'})]];
          checked(moon.managedOutputAccept(downstreamOutput, 1, JSON.stringify(columns)));
          checked(moon.managedOutputFinish(downstreamOutput));
          assert.deepEqual(checked(moon.managedOutputReusedMeasurements(downstreamOutput)),
            empty ? [2, 1, 1] : [8, 27, 4]);
          const downstreamWriter = store.reserve(4096);
          await downstreamWriter.start();
          const native_columns = [[rows[0].n]]; // Fixture numeric file view of the same native result.
          await downstreamWriter.appendBytes(Buffer.from(JSON.stringify({rows: 1, columns, native_columns}) + '\n'));
          const downstreamBody = await downstreamWriter.sealPhysical();
          checked(moon.managedOutputRetain(downstreamOutput, BigInt(downstreamBody.bytes),
            () => downstreamBody.available()));
          for (const failure of ['transport', 'policy', 'cancel', 'reentrant']) {
            let allowed = true, settled = false, rejectPort;
            rejectPort = checked(fixture.managedQueryCompletion(nativeQuery, profile, ...contracts, 10000,
              () => allowed, () => {
                if (failure === 'reentrant') moon.managedInputCompletionCancel(rejectPort);
                return failure !== 'transport' || settled;
              }));
            const rejected = checked(moon.managedOutputOpen(moon.managedInputOutputValues(rejectPort),
              JSON.stringify([['n', 'DOUBLE', null, null]]), fixture.managedFilePhysicalLimits(),
              fixture.managedFileTransportLimits(), 100));
            try {
              checked(moon.managedOutputAccept(rejected, 1, JSON.stringify(columns)));
              checked(moon.managedOutputFinish(rejected));
              checked(moon.managedOutputRetain(rejected, BigInt(downstreamBody.bytes),
                () => downstreamBody.available()));
              if (failure === 'policy') allowed = false;
              if (failure === 'cancel') assert.equal(moon.managedInputCompletionCancel(rejectPort), true);
              assert.throws(() => checked(moon.managedOutputCompleteInput(rejected, rejectPort)), failure);
              allowed = true; settled = true;
              assert.throws(() => checked(moon.managedOutputCompleteInput(rejected, rejectPort)),
                'failed admission cannot revive');
            } finally { moon.managedOutputCancel(rejected); }
          }
          // The same output cannot complete a separately prepared consumer ledger.
          const foreignPort = checked(fixture.managedQueryCompletion(nativeQuery, profile, ...contracts, 10000,
            () => true, () => true));
          assert.throws(() => checked(moon.managedOutputCompleteInput(downstreamOutput, foreignPort)));
          nativeSettled = true;
          if (revoke === 'completion-input') {
            assert.throws(() => checked(moon.managedOutputCompleteInput(downstreamOutput, downstreamPort)),
              'final authorization cannot revoke input yet publish success');
            assert.throws(() => checked(moon.managedOutputCompleteInput(downstreamOutput, downstreamPort)));
            continue;
          }
          downstreamCompleted = checked(moon.managedOutputCompleteInput(downstreamOutput, downstreamPort));
          assert.equal(moon.managedCompletedProfileCid(downstreamCompleted), profileCid);
          assert.equal(moon.managedCompletedAvailable(downstreamCompleted), true);
          assert.throws(() => checked(moon.managedOutputCompleteInput(downstreamOutput, downstreamPort)));
          // Completion preserves binding history, not a lease on ancestors.
          moon.managedOutputCancel(output);
          body.close();
          await store.cleanup();
          assert.equal(body.available(), false);
          assert.equal(store.status().reservedBytes, downstreamBody.bytes,
            'ancestor bytes are physically reclaimed before downstream use ends');
          assert.equal(moon.managedCompletedAvailable(downstreamCompleted), true);
          downstreamAuthorized = false;
          nativeSettled = false;
          assert.equal(moon.managedCompletedAvailable(downstreamCompleted), true,
            'settled independent holding does not borrow the prior attempt');
          const countMaterial = moon.managedOutputMaterial(downstreamOutput);
          const countCodec = `sha256:${'6'.repeat(64)}`;
          registerManagedInput(countMaterial, input => moon.managedInputMatchesMaterial(input, countMaterial),
            store, downstreamBody, countCodec);
          if (revoke === 'none') for (const ceiling of [10000, 4]) {
            const filterInput = fixture.ownedFixedManagedFilterInput(nativeQuery, downstreamCompleted);
            assert.deepEqual(fixture.managedColumnMeasurement(filterInput),
              [1, 1, 1, 1, 0]);
            const filterQuery = fixture.managedFixedQuery(filterInput);
            let settled = false;
            const filterPort = checked(fixture.managedQueryCompletion(filterQuery, profile, ...contracts, ceiling,
              () => true, () => settled && fixture.managedFixedQueryMatches(filterQuery, filterInput)));
            const filterOutput = checked(moon.managedOutputOpen(moon.managedInputOutputValues(filterPort),
              JSON.stringify([['n', 'DOUBLE', null, null]]), fixture.managedFilePhysicalLimits(),
              fixture.managedFileTransportLimits(), 100));
            const db = await DuckDBInstance.create(':memory:', {threads: '1', memory_limit: '128MB'});
            const connection = await db.connect();
            let filterBody;
            try {
              const [create, sql] = fixture.managedFixedQuerySql(filterQuery);
              await connection.run(create);
              const rows = await withManagedInputFile(countMaterial, filterInput, countCodec, () => true, async file => {
                {
                  const path = `'${file.path.replaceAll("'", "''")}'`;
                  await connection.run(`INSERT INTO managed_input SELECT unnest(native_columns[1])
                    FROM read_json(${path}, format='newline_delimited', columns={native_columns:'DOUBLE[][]'})`);
                }
                const statement = await connection.prepare(sql);
                try {
                  bindPhysicalValue(statement, 1, JSON.parse(checked(fixture.managedFixedQueryParameter(filterQuery))));
                  return (await statement.runAndReadAll()).getRowObjects();
                } finally { statement.destroySync(); }
              });
              assert.deepEqual(rows, empty ? [] : [{n: 3}]);
              const columns = [rows.map(row => exportPhysicalValue(row.n, {id: 'DOUBLE'}))];
              checked(moon.managedOutputAccept(filterOutput, rows.length, JSON.stringify(columns)));
              checked(moon.managedOutputFinish(filterOutput));
              const writer = store.reserve(4096);
              await writer.start();
              await writer.appendBytes(Buffer.from(JSON.stringify({rows: rows.length, columns}) + '\n'));
              filterBody = await writer.sealPhysical();
              checked(moon.managedOutputRetain(filterOutput, BigInt(filterBody.bytes), () => filterBody.available()));
              settled = true;
              if (empty && ceiling === 4) {
                assert.throws(() => checked(moon.managedOutputCompleteInput(filterOutput, filterPort)),
                  'false predicate is five logical bytes even with an empty result');
                assert.throws(() => checked(moon.managedOutputCompleteInput(filterOutput, filterPort)));
                continue;
              }
              const filtered = checked(moon.managedOutputCompleteInput(filterOutput, filterPort));
              assert.deepEqual(checked(moon.managedInputComparisonUsage(filterPort)),
                (empty ? [1, 1, 1, 0, 1, 0, 5, 3, 1, 1] : [1, 1, 1, 1, 0, 0, 4, 3, 1, 1]).map(String));
              assert.equal(moon.managedCompletedProfileCid(filtered), profileCid);
              assert.equal(moon.managedCompletedAvailable(filtered), true);
              assert.deepEqual(checked(moon.managedOutputReusedMeasurements(filterOutput)),
                empty ? [2, 1, 1] : [4, 2, 2]);
            } finally {
              moon.managedOutputCancel(filterOutput);
              filterBody?.close();
              connection.closeSync(); db.closeSync();
              await store.cleanup();
            }
          }
          for (let reader = 0; reader < 2; reader++) {
            const countRead = fixture.managedCountRead(nativeQuery, downstreamCompleted);
            const frame = await withManagedInputFile(countMaterial, countRead, countCodec, () => true,
              async file => JSON.parse(await readFile(file.path, 'utf8')));
            assert.deepEqual(frame, {rows: 1, columns, native_columns});
            assert.equal(store.status().activeReaders, 0);
          }
        } finally { connection.closeSync(); database.closeSync(); }
        moon.managedOutputCancel(output);
        assert.equal(fixture.managedFixedQueryMatches(nativeQuery, countInput), false,
          'prepared SQL does not preserve authority after material revocation');
      }
    } finally {
      if (downstreamOutput) moon.managedOutputCancel(downstreamOutput);
      if (downstreamCompleted) assert.equal(moon.managedCompletedAvailable(downstreamCompleted), false);
      if (output) moon.managedOutputCancel(output);
      if (completed) assert.equal(moon.managedCompletedAvailable(completed), false);
      if (run) moon.computeHostClose(run);
      if (result) releaseFixedCompute(result);
      store.close(); await store.cleanup();
      assert.equal(store.status().cleanupPending, false);
      assert.equal(store.status().reservedBytes, 0);
      await rmdir(directory);
    }
  }
});
