"""Opt-in diagnostic protocol; system SQLite is a fixture, not the selected component."""
from pathlib import Path
import json,os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parent.parent
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

    def run_protocol(self,mode,selection):
        env=dict(os.environ);env.pop('ACTQL_NATIVE_TIMINGS',None)
        if selection is not None:env['ACTQL_NATIVE_TIMINGS']=selection
        result=subprocess.run([str(self.binary),mode],env=env,text=True,capture_output=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,'')
        rows=[]
        for line in result.stderr.splitlines():
            prefix,body=line.split(' ',1);self.assertIn(prefix,('ACTQL_NATIVE_TIMINGS','ACTQL_NATIVE_PHASE','ACTQL_NATIVE_COUNTER'));rows.append((prefix,json.loads(body)))
        return rows
    def test_disabled_and_nonliteral_selection_emit_nothing(self):
        for selection in (None,'true','01','0'):self.assertEqual(self.run_protocol('sql',selection),[])
    def test_actual_sql_calls_preserve_results_and_nested_exclusive_times(self):
        rows=self.run_protocol('sql','1');meta=[x for k,x in rows if k=='ACTQL_NATIVE_TIMINGS'];self.assertEqual(len(meta),1)
        self.assertFalse(meta[0]['overflow']);self.assertFalse(meta[0]['parallel_observed']);self.assertEqual(meta[0]['clock_failures'],0)
        phases={x['tag']:x for k,x in rows if k=='ACTQL_NATIVE_PHASE'};counts={x['tag']:x['count']for k,x in rows if k=='ACTQL_NATIVE_COUNTER' and x['count']}
        self.assertEqual(counts,{0:1,1:1,2:2,3:1})
        self.assertEqual(sum(k=='ACTQL_NATIVE_COUNTER'for k,x in rows),64)
        self.assertEqual(sum(k=='ACTQL_NATIVE_PHASE'for k,x in rows),32)
        self.assertEqual(phases[0]['exclusive_ns']+phases[3]['exclusive_ns'],phases[0]['inclusive_ns'])
        self.assertEqual(phases[3]['exclusive_ns'],phases[3]['inclusive_ns'])
        for tag in (0,3):self.assertEqual((phases[tag]['begins'],phases[tag]['ends'],phases[tag]['active']),(1,1,0))
    def test_real_threads_keep_exact_counts_and_label_parallel_time(self):
        rows=self.run_protocol('threads','1');meta=next(x for k,x in rows if k=='ACTQL_NATIVE_TIMINGS');self.assertTrue(meta['parallel_observed'])
        counts={x['tag']:x['count']for k,x in rows if k=='ACTQL_NATIVE_COUNTER' and x['count']};self.assertEqual(counts,{16:4000})
        phase=next(x for k,x in rows if k=='ACTQL_NATIVE_PHASE' and x['tag']==2);self.assertEqual((phase['begins'],phase['ends'],phase['active']),(4,4,0))
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
if __name__=='__main__':unittest.main()
