"""Bounded current-job compiler crash metadata, never raw reports or acceptance."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time

MAX_REPORT_BYTES = 4 * 1024 * 1024
MAX_REPORTS = 16
MAX_DIRECTORY_ENTRIES = 512


def _text(value, maximum=256):
    if (not isinstance(value, str) or len(value) > maximum
            or any(ord(c) < 32 or ord(c) > 126 for c in value)):
        return None
    return value


def summarize(raw, tools):
    """Only exception/termination scalars and the faulting thread's symbols."""
    first, end = json.JSONDecoder().raw_decode(raw.decode('utf-8'))
    remainder = raw.decode('utf-8')[end:].strip()
    body = json.loads(remainder) if remainder else first
    if not isinstance(body, dict):
        raise ValueError('Unavailable structured compiler report')
    name = body.get('procName')
    if name not in tools or body.get('procPath') != tools[name]:
        return None
    result = {'process': name, 'exception': {}, 'termination': {}, 'faulting_frames': []}
    for group, fields in (
        ('exception', ('type', 'signal', 'codes', 'rawCodes')),
        ('termination', ('namespace', 'code', 'flags', 'byProc', 'byPid')),
    ):
        original = body.get(group)
        if not isinstance(original, dict):
            continue
        for key in fields:
            value = original.get(key)
            if type(value) is int and -(2**64) < value < 2**64:
                result[group][key] = value
            elif (isinstance(value, list) and len(value) <= 8
                  and all(type(x) is int and -(2**64) < x < 2**64 for x in value)):
                result[group][key] = value
            elif _text(value) is not None:
                result[group][key] = value
    threads, images, index = body.get('threads'), body.get('usedImages'), body.get('faultingThread')
    if (isinstance(threads, list) and type(index) is int and 0 <= index < len(threads)
            and isinstance(threads[index], dict)):
        frames = threads[index].get('frames')
        if isinstance(frames, list):
            for frame in frames[:32]:
                if not isinstance(frame, dict):
                    continue
                selected = {}
                if _text(frame.get('symbol')) is not None:
                    selected['symbol'] = frame['symbol']
                for key in ('imageIndex', 'imageOffset'):
                    if type(frame.get(key)) is int and 0 <= frame[key] < 2**64:
                        selected[key] = frame[key]
                image_index = frame.get('imageIndex')
                if (isinstance(images, list) and type(image_index) is int
                        and 0 <= image_index < len(images) and isinstance(images[image_index], dict)):
                    image = images[image_index]
                    basename = image.get('name')
                    if basename is None and isinstance(image.get('path'), str):
                        basename = Path(image['path']).name
                    if _text(basename, 128) is not None:
                        selected['image'] = basename
                if selected:
                    result['faulting_frames'].append(selected)
    return result


def collect(directory, context):
    """No symlinks, old reports, foreign tools or unbounded directory walk."""
    result = {'reports': [], 'refused': [], 'complete': True,
              'association': 'current time window and original tool path; not PID-lineage proof'}
    if not directory.exists():
        return {**result, 'complete': False, 'availability': 'report-directory-unavailable'}
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('Compiler report directory must be an original directory')
    entries = opened = 0
    with os.scandir(directory) as scan:
        for item in scan:
            entries += 1
            if entries > MAX_DIRECTORY_ENTRIES:
                result['complete'] = False
                result['refused'].append('directory-entry-bound')
                break
            if not re.fullmatch(r'(?:moon|moonc)[-_][^/]+\.ips', item.name):
                continue
            status = item.stat(follow_symlinks=False)
            if (not stat.S_ISREG(status.st_mode) or status.st_uid != os.getuid()
                    or status.st_mtime_ns < context['started_ns']):
                continue
            if opened >= MAX_REPORTS:
                result['complete'] = False
                result['refused'].append('report-count-bound')
                break
            if not 0 < status.st_size <= MAX_REPORT_BYTES:
                result['complete'] = False
                result['refused'].append('report-byte-bound')
                continue
            opened += 1
            fd = os.open(item.path, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                before = os.fstat(fd)
                keys = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
                if (not 0 < before.st_size <= MAX_REPORT_BYTES
                        or any(getattr(before, k) != getattr(status, k) for k in keys)):
                    raise ValueError('Compiler report changed before reading')
                with os.fdopen(fd, 'rb', closefd=False) as stream:
                    raw = stream.read(MAX_REPORT_BYTES + 1)
                after = os.fstat(fd)
                if len(raw) != before.st_size or any(getattr(before, k) != getattr(after, k) for k in keys):
                    raise ValueError('Compiler report changed while reading')
                selected = summarize(raw, context['tools'])
                if selected is not None:
                    result['reports'].append({'sha256': hashlib.sha256(raw).hexdigest(), **selected})
            except (ValueError, UnicodeError, json.JSONDecodeError):
                result['complete'] = False
                result['refused'].append('malformed-or-changing-report')
            finally:
                os.close(fd)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--context', required=True, type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--start', action='store_true')
    mode.add_argument('--collect', type=Path)
    args = parser.parse_args()
    if args.start:
        tools = {name: str((Path(os.environ['MOON_HOME']) / 'bin' / name).resolve())
                 for name in ('moon', 'moonc')}
        context = {'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                   'started_ns': time.time_ns(), 'tools': tools}
        args.context.parent.mkdir(parents=True, exist_ok=True)
        with args.context.open('x') as output:
            json.dump(context, output)
        return
    if args.context.is_symlink() or not 0 < args.context.stat().st_size <= 65536:
        raise ValueError('Unavailable owned diagnostic context')
    context = json.loads(args.context.read_bytes())
    if (set(context) != {'source', 'started_ns', 'tools'}
            or type(context['started_ns']) is not int or context['started_ns'] <= 0
            or set(context['tools']) != {'moon', 'moonc'}):
        raise ValueError('Invalid owned diagnostic context')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != context['source']:
        raise ValueError('Diagnostic source changed')
    directory = Path.home() / 'Library/Logs/DiagnosticReports'
    deadline = time.monotonic() + 10
    while True:
        result = collect(directory, context)
        if result['reports'] or time.monotonic() >= deadline:
            break
        time.sleep(1)
    result.update(source=context['source'], scope='sanitized-current-compiler-crash-metadata',
                  raw_reports_retained=False, environment_retained=False,
                  registers_or_memory_retained=False, native_success=False,
                  availability='matching-current-report-observed' if result['reports'] else 'unobserved')
    with args.collect.open('x') as output:
        json.dump(result, output, indent=2)
        output.write('\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
