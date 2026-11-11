"""Opt-in diagnostic protocol; system SQLite is a fixture, not the selected component."""
from pathlib import Path
import json,os,re,subprocess,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parent.parent

def check_command_counter_map(mapping):
    owners = {}
    def assign(tag, owner):
        if type(tag) is not int or not 0 <= tag < 70:
            raise ValueError(f'invalid counter {tag!r}: {owner}')
        if tag in owners:
            raise ValueError(f'counter {tag} overlaps {owners[tag]} and {owner}')
        owners[tag] = owner
    domains = mapping['domainInventorySlots']
    for owner in ('Read', 'SQLite', 'Compute'):
        for tag in domains[owner]: assign(tag, owner)
    for tag in mapping['allocationCounterSlots']: assign(int(tag), 'allocation/command')
    assign(21, 'Check Environment')
    for tag in mapping['signingBoundarySlots']: assign(int(tag), 'Signing external boundary')
    for tag in mapping.get('requestWorkSlots', {}): assign(int(tag), 'Request observed work')
    product = {int(tag) for tag in mapping['productOriginalCounterSlots']}
    for tag in product: assign(tag, 'Product')
    product_path = ROOT / 'src/platform_native/client_host/local_product_configuration.mbt'
    actual_product = {int(tag) for tag in re.findall(r'native_timing_count\((\d+)\)', product_path.read_text())}
    if actual_product != product | {58}:
        raise ValueError('Product counter calls differ from the declared map')
    # These two closed packages contain the other literal MoonBit callsites.
    for package in ('cmd/native_client', 'platform_native/client_host'):
        for path in (ROOT / 'src' / package).glob('*.mbt'):
            if path == product_path or path.name.endswith(('_wbtest.mbt', '_test.mbt')): continue
            used = {int(tag) for tag in re.findall(r'native_timing_(?:count|amount)\((\d+)', path.read_text())}
            if product & used: raise ValueError(f'Product counter overlaps {path.name}')
    header = (ROOT / 'src/platform_native/filesystem/native_timings.h').read_text()
    reserved = {int(tag) for tag in re.findall(r'ACTQL_NATIVE_COUNT_\w+\s*=\s*(\d+)', header)}
    if product & reserved: raise ValueError('Product counter overlaps a named Native counter')
    emitter = (ROOT / 'src/cmd/native_client/native_timings.mbt').read_text()
    split = re.search(r'control_tag\s*=\s*if\s+first_tag\s*==\s*(\d+)\s*\{\s*(\d+)\s*\}\s*else\s*\{\s*first_tag\s*\+\s*2\s*\}', emitter)
    if split is None: raise ValueError('domain census emitter correspondence is missing')
    special, control = map(int, split.groups())
    for owner in ('Read', 'SQLite', 'Compute'):
        first = domains[owner][0]
        offset = control if first == special else first + 2
        if domains[owner] != [first, first + 1, offset, offset + 1, offset + 2]:
            raise ValueError(f'{owner} census emitter differs from the declared map')
    return {'counterAssignments': len(owners), 'productSlots': sorted(product), 'domainGroups': 3}

class CommandCounterMap(unittest.TestCase):
    def mapping(self):
        return {'domainInventorySlots': {'Read': [4,5,6,7,8], 'SQLite': [9,10,11,12,13],
                'Compute': [14,15,60,61,62]},
                'allocationCounterSlots': {str(tag): 'allocation/command' for tag in [31,*range(46,60),63]},
                'signingBoundarySlots': {'64': 'actual external/physical signing boundary', '65': 'unexpected helper revalidation'},
                'requestWorkSlots': {str(tag): 'Request observed work' for tag in range(66, 70)},
                'productOriginalCounterSlots': {'28': 'Product original check', '29': 'Product body read'}}
    def test_product_and_domain_amounts_have_distinct_slots(self):
        self.assertEqual(check_command_counter_map(self.mapping())['productSlots'], [28,29])
    def test_signing_boundary_cannot_reuse_environment_admission_slot(self):
        mapping = self.mapping(); mapping['signingBoundarySlots'] = {'21': 'signing boundary'}
        # This actual command source owns Environment admission independently.
        source = (ROOT / 'src/cmd/native_client/local_command_configuration.mbt').read_text()
        self.assertIn('native_timing_count(21)', source)
        expected = (ROOT / 'src/platform_native/client_host/local_initial_signing_read.mbt').read_text()
        self.assertIn('native_timing_count(64)', expected)
        self.assertNotIn('native_timing_count(21)', expected)
        with self.assertRaisesRegex(ValueError, 'counter 21 overlaps'):
            check_command_counter_map(mapping)

    def test_previous_product_slots_collide_before_compilation(self):
        mapping = self.mapping(); mapping['productOriginalCounterSlots'] = {'60': 'check', '61': 'read'}
        with self.assertRaisesRegex(ValueError, 'counter 60 overlaps'):
            check_command_counter_map(mapping)
    def test_request_work_cannot_reuse_signing_slot(self):
        mapping = self.mapping(); mapping['requestWorkSlots'] = {'65': 'Request parse'}
        with self.assertRaisesRegex(ValueError, 'counter 65 overlaps'):
            check_command_counter_map(mapping)
    def test_run_installation_admission_has_a_distinct_slot(self):
        mapping = self.mapping(); mapping['productOriginalCounterSlots'] = {'31': 'check', '29': 'read'}
        with self.assertRaisesRegex(ValueError, 'counter 31 overlaps'):
            check_command_counter_map(mapping)
    def test_declaration_cannot_relabel_the_actual_product_calls(self):
        mapping = self.mapping(); mapping['productOriginalCounterSlots'] = {'30': 'check', '32': 'read'}
        with self.assertRaisesRegex(ValueError, 'Product counter calls differ'):
            check_command_counter_map(mapping)

class NativeTimingProtocol(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='actql-native-timings-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.binary = Path(cls.temporary.name) / 'protocol'
        subprocess.run([os.environ.get('CC', 'cc'), '-std=c11', '-O2', '-Wall',
                        '-Wextra', '-Werror', '-pthread',
                        '-I', str(ROOT / 'src/platform_native/filesystem'),
                        str(ROOT / 'scripts/fixtures/native_timings_protocol.c'),
                        '-lsqlite3', '-o', str(cls.binary)], check=True, timeout=60)

    def run_protocol(self,mode,selection,acceptance=None):
        env=dict(os.environ);env.pop('ACTQL_NATIVE_TIMINGS',None)
        env.pop('ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS',None)
        if acceptance is not None:env['ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS']=acceptance
        if selection is not None:env['ACTQL_NATIVE_TIMINGS']=selection
        result=subprocess.run([str(self.binary),mode],env=env,text=True,capture_output=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'')
        rows=[]
        for line in result.stderr.splitlines():
            prefix,body=line.split(' ',1);self.assertIn(prefix,('ACTQL_NATIVE_TIMINGS','ACTQL_NATIVE_PHASE','ACTQL_NATIVE_COUNTER','ACTQL_NATIVE_ACCEPTANCE_BEGIN','ACTQL_NATIVE_ACCEPTANCE_EVENT','ACTQL_NATIVE_ACCEPTANCE_END'));rows.append((prefix,json.loads(body)))
        return rows
    def test_acceptance_is_opt_in_bounded_metadata_with_owned_original_identity(self):
        for selection in (None,'0','true','01'):
            rows=self.run_protocol('acceptance','1',selection)
            self.assertFalse(any(k.startswith('ACTQL_NATIVE_ACCEPTANCE') for k,x in rows))
        self.assertEqual(self.run_protocol('acceptance',None,'1'),[])
        rows=self.run_protocol('acceptance','1','1')
        begin=next(x for k,x in rows if k=='ACTQL_NATIVE_ACCEPTANCE_BEGIN')
        end=next(x for k,x in rows if k=='ACTQL_NATIVE_ACCEPTANCE_END')
        events=[x for k,x in rows if k=='ACTQL_NATIVE_ACCEPTANCE_EVENT']
        self.assertTrue(begin['complete']);self.assertEqual(begin['count'],7)
        self.assertEqual(end,{'pid':begin['pid'],'count':7})
        self.assertEqual([x['tag'] for x in events],[0,1,2,5,6,7,8])
        self.assertEqual([x['seq'] for x in events],list(range(7)))
        for event in events:
            self.assertEqual(event['pid'],begin['pid'])
            self.assertEqual(event['identity'],'' if event['tag'] in (6,7) else 'sha256:'+'1'*64)
    def test_actual_c_acceptance_stream_is_admitted_by_the_same_cli_parser(self):
        env={**os.environ,'ACTQL_NATIVE_TIMINGS':'1','ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS':'1'}
        result=subprocess.run([str(self.binary),'acceptance'],env=env,text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0);self.assertEqual(result.stdout,'')
        program="import{nativeMockAcceptanceObservations as parse}from'./packages/native-cli/lib/project-scaffold.mjs';let s='';for await(const b of process.stdin)s+=b;const g=parse(s);if(g.length!==1||g[0].events.length!==7)throw Error('C event correspondence');console.log('7');"
        checked=subprocess.run(['node','--input-type=module','-e',program],cwd=ROOT,input=result.stderr,text=True,capture_output=True,timeout=10)
        self.assertEqual(checked.returncode,0,checked.stderr);self.assertEqual(checked.stdout,'7\n')
    def test_acceptance_invalid_and_overflow_are_incomplete_not_zero(self):
        for mode in ('acceptance-invalid','acceptance-overflow'):
            rows=self.run_protocol(mode,'1','1')
            begin=next(x for k,x in rows if k=='ACTQL_NATIVE_ACCEPTANCE_BEGIN')
            events=[x for k,x in rows if k=='ACTQL_NATIVE_ACCEPTANCE_EVENT']
            self.assertFalse(begin['complete']);self.assertGreater(len(events),0);self.assertLessEqual(len(events),32)
            self.assertNotIn('XXX',json.dumps(rows));self.assertNotIn('Pha256',json.dumps(rows))
    def test_disabled_and_nonliteral_selection_emit_nothing(self):
        for selection in (None,'true','01','0'):self.assertEqual(self.run_protocol('sql',selection),[])
    def test_approval_stage_names_and_full_boundary_counter_are_distinct(self):
        rows = self.run_protocol('approval-stages', '1')
        phases = {x['tag']: x for k, x in rows if k == 'ACTQL_NATIVE_PHASE'}
        for tag in range(32, 39):
            self.assertTrue(phases[tag]['name'].startswith('approval_'))
            self.assertEqual((phases[tag]['begins'], phases[tag]['ends'], phases[tag]['active']), (1, 1, 0))
        counts = {x['tag']: x for k, x in rows if k == 'ACTQL_NATIVE_COUNTER'}
        self.assertEqual(counts[64]['name'], 'signing_full_boundary_calls')
        self.assertEqual(counts[64]['count'], 1)
        self.assertEqual(counts[21]['count'], 0)

    def test_counter_snapshot_is_read_only_and_missing_is_not_zero(self):
        self.assertEqual(self.run_protocol('snapshot', None), [])
        rows = self.run_protocol('snapshot', '1')
        counts = {x['tag']: x['count'] for k, x in rows if k == 'ACTQL_NATIVE_COUNTER'}
        self.assertEqual(counts[16], 1)
        self.assertEqual(len(counts), 70)

    def test_request_work_amounts_have_distinct_names_and_no_signing_or_parse_alias(self):
        rows = self.run_protocol('request-work', '1')
        counts = {x['tag']: x for k, x in rows if k == 'ACTQL_NATIVE_COUNTER'}
        names = ['request_query_parse_calls', 'request_query_lower_calls',
                 'request_semantic_check_calls', 'request_program_compile_calls']
        self.assertEqual([counts[tag]['name'] for tag in range(66, 70)], names)
        self.assertEqual([counts[tag]['count'] for tag in range(66, 70)], [2, 3, 4, 5])
        self.assertEqual([counts[tag]['count'] for tag in (17, 64, 65)], [0, 0, 0])

    def test_actual_sql_calls_preserve_results_and_nested_exclusive_times(self):
        rows=self.run_protocol('sql','1');meta=[x for k,x in rows if k=='ACTQL_NATIVE_TIMINGS'];self.assertEqual(len(meta),1)
        self.assertFalse(meta[0]['overflow']);self.assertFalse(meta[0]['parallel_observed']);self.assertEqual(meta[0]['clock_failures'],0)
        phases={x['tag']:x for k,x in rows if k=='ACTQL_NATIVE_PHASE'};counts={x['tag']:x['count']for k,x in rows if k=='ACTQL_NATIVE_COUNTER' and x['count']}
        self.assertEqual(counts,{0:1,1:1,2:2,3:1})
        self.assertEqual(sum(k=='ACTQL_NATIVE_COUNTER'for k,x in rows),70)
        self.assertEqual(sum(k=='ACTQL_NATIVE_PHASE'for k,x in rows),39)
        self.assertEqual(phases[0]['exclusive_ns']+phases[3]['exclusive_ns'],phases[0]['inclusive_ns'])
        self.assertEqual(phases[3]['exclusive_ns'],phases[3]['inclusive_ns'])
        self.assertEqual(phases[3]['sql_prepares'], 1)
        self.assertEqual(phases[0]['sql_prepares'], 1)
        self.assertEqual(phases[3]['current_calls'], 0)
        for tag in (0,3):self.assertEqual((phases[tag]['begins'],phases[tag]['ends'],phases[tag]['active']),(1,1,0))
    def test_real_threads_keep_exact_counts_and_label_parallel_time(self):
        rows=self.run_protocol('threads','1');meta=next(x for k,x in rows if k=='ACTQL_NATIVE_TIMINGS');self.assertTrue(meta['parallel_observed'])
        counts={x['tag']:x['count']for k,x in rows if k=='ACTQL_NATIVE_COUNTER' and x['count']};self.assertEqual(counts,{16:4000})
        phase=next(x for k,x in rows if k=='ACTQL_NATIVE_PHASE' and x['tag']==2);self.assertEqual((phase['begins'],phase['ends'],phase['active']),(4,4,0))
    def test_amounts_are_bounded_additions_not_increment_loops(self):
        rows=self.run_protocol('amount','1');meta=next(x for k,x in rows if k=='ACTQL_NATIVE_TIMINGS')
        counts={x['tag']:x for k,x in rows if k=='ACTQL_NATIVE_COUNTER'}
        self.assertEqual(counts[46]['count'],512*1024*1024+16384)
        self.assertEqual(counts[47]['count'],16384)
        self.assertEqual(counts[46]['name'],'backing_allocated_bytes')
        self.assertEqual(counts[47]['name'],'backing_explicit_zeroed_bytes')
        self.assertEqual(meta['invalid_amounts'],1);self.assertEqual(meta['invalid_tags'],1)
        self.assertFalse(meta['overflow'])
        self.assertEqual(self.run_protocol('amount',None),[])
    def test_amount_overflow_remains_explicit(self):
        rows=self.run_protocol('amount-overflow','1');meta=next(x for k,x in rows if k=='ACTQL_NATIVE_TIMINGS')
        self.assertTrue(meta['overflow'])
        count=next(x['count'] for k,x in rows if k=='ACTQL_NATIVE_COUNTER' and x['tag']==46)
        self.assertEqual(count,(3*((1<<63)-1))%(1<<64))
    def test_child_snapshot_does_not_duplicate_parent_report_or_counts(self):
        rows=self.run_protocol('fork','1');self.assertEqual(sum(k=='ACTQL_NATIVE_TIMINGS'for k,x in rows),1)
        counts={x['tag']:x['count']for k,x in rows if k=='ACTQL_NATIVE_COUNTER' and x['count']};self.assertEqual(counts,{16:1})
    def test_closed_stderr_pipe_preserves_successful_exit_and_parent_signal_handler(self):
        import signal
        read_fd,write_fd=os.pipe();os.close(read_fd)
        before=signal.getsignal(signal.SIGPIPE)
        try:
            env=dict(os.environ,ACTQL_NATIVE_TIMINGS='1')
            result=subprocess.run([str(self.binary),'threads'],env=env,stdout=subprocess.PIPE,stderr=write_fd,timeout=10)
            self.assertEqual(result.returncode,0)
            self.assertEqual(signal.getsignal(signal.SIGPIPE),before)
        finally:os.close(write_fd)
    def test_full_stderr_pipe_does_not_wait_for_a_reader(self):
        import fcntl
        read_fd,write_fd=os.pipe();flags=fcntl.fcntl(write_fd,fcntl.F_GETFL)
        try:
            fcntl.fcntl(write_fd,fcntl.F_SETFL,flags|os.O_NONBLOCK)
            try:
                while True:os.write(write_fd,b'x'*4096)
            except BlockingIOError:pass
            fcntl.fcntl(write_fd,fcntl.F_SETFL,flags)
            before_child=fcntl.fcntl(write_fd,fcntl.F_GETFL)
            self.assertFalse(before_child & os.O_NONBLOCK)
            result=subprocess.run([str(self.binary),'threads'],env=dict(os.environ,ACTQL_NATIVE_TIMINGS='1'),stdout=subprocess.PIPE,stderr=write_fd,timeout=10)
            self.assertEqual(result.returncode,0)
            self.assertEqual(fcntl.fcntl(write_fd,fcntl.F_GETFL),before_child)
        finally:os.close(read_fd);os.close(write_fd)
    def test_bounded_stack_and_pending_frames_are_reported_without_success(self):
        rows=self.run_protocol('partial','1');meta=next(x for k,x in rows if k=='ACTQL_NATIVE_TIMINGS');self.assertEqual(meta['stack_overflows'],3);self.assertEqual(meta['invalid_tags'],1)
        phases={x['tag']:x for k,x in rows if k=='ACTQL_NATIVE_PHASE'};self.assertEqual(phases[6]['active'],1);self.assertEqual(phases[0]['active'],1);self.assertEqual(phases[5]['unmatched_end'],1)
        self.assertEqual(phases[4]['begins'],34);self.assertEqual(phases[4]['ends'],31)
if __name__=='__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--check-counter-map':
        mapping = json.loads(Path(sys.argv[2]).read_text())
        source = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
        if mapping['source'] != source: raise ValueError('counter map source differs from HEAD')
        print(json.dumps(check_command_counter_map(mapping)))
    else: unittest.main()
