"""Read normal wheel payloads with stdlib parsers; never import product code.

RECORD supplies distributed members. AST supplies public bindings and private
helpers, including helpers outside the conventional SDK package directory.
This is coverage data, not a second Python execution/permission authority.
"""
import argparse
import ast
import base64
import csv
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tomllib
import zipfile


def python_interface(source: str) -> dict:
    tree = ast.parse(source)
    operations = []
    imports = []
    exports = set()
    occurrences = {}

    def visit(node, scope=()):
        child_scope = scope
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            child_scope = (*scope, node.name)
            if not scope and not node.name.startswith('_'):
                exports.add(node.name)
            parameters = []
            if not isinstance(node, ast.ClassDef):
                parameters = [argument.arg for argument in
                              (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs)]
                if node.args.vararg:
                    parameters.append('*' + node.args.vararg.arg)
                if node.args.kwarg:
                    parameters.append('**' + node.args.kwarg.arg)
            base = '/'.join(child_scope)
            occurrence = occurrences.get(base, 0) + 1
            occurrences[base] = occurrence
            name = base if occurrence == 1 else f'{base}#{occurrence}'
            operations.append({'name': name, 'parameters': parameters,
                               'async': isinstance(node, ast.AsyncFunctionDef)})
        if isinstance(node, ast.Import):
            imports.extend(alias.name for alias in node.names)
            if not scope:
                exports.update(alias.asname or alias.name.split('.')[0] for alias in node.names
                               if not (alias.asname or alias.name).startswith('_'))
        if isinstance(node, ast.ImportFrom):
            imports.append('.' * node.level + (node.module or ''))
            if not scope:
                exports.update(alias.asname or alias.name for alias in node.names
                               if not (alias.asname or alias.name).startswith('_'))
        if not scope and isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name) and not target.id.startswith('_'):
                    exports.add(target.id)
            if any(isinstance(target, ast.Name) and target.id == '__all__' for target in targets):
                try:
                    declared = ast.literal_eval(node.value)
                except (ValueError, TypeError) as failure:
                    raise ValueError('Nonliteral wheel export inventory requires owner projection') from failure
                if not isinstance(declared, (list, tuple)) or not all(isinstance(x, str) for x in declared):
                    raise ValueError('Invalid wheel export inventory')
                exports.update(declared)
        for child in ast.iter_child_nodes(node):
            visit(child, child_scope)

    visit(tree)
    return {'exports': sorted(exports), 'operations': sorted(operations, key=lambda x: x['name']),
            'imports': sorted(set(imports))}


def wheel_interfaces(path) -> dict:
    with zipfile.ZipFile(path) as wheel:
        names = wheel.namelist()
        if len(names) != len(set(names)) or any(
                PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts
                or '\\' in name for name in names):
            raise ValueError('Unsafe or duplicate wheel member')
        records = [name for name in names if name.endswith('.dist-info/RECORD')]
        if len(records) != 1:
            raise ValueError('One normal wheel RECORD is required')
        rows = list(csv.reader(io.StringIO(wheel.read(records[0]).decode())))
        by_name = {row[0]: row for row in rows}
        files = {name for name in names if not name.endswith('/')}
        if len(by_name) != len(rows) or set(by_name) != files:
            raise ValueError('Incomplete wheel RECORD coverage')
        modules = []
        for name in sorted(files):
            data = wheel.read(name)
            row = by_name[name]
            if len(row) != 3:
                raise ValueError('Invalid wheel RECORD member')
            if name != records[0]:
                expected = 'sha256=' + base64.urlsafe_b64encode(hashlib.sha256(data).digest()).decode().rstrip('=')
                if row[1] != expected or row[2] != str(len(data)):
                    raise ValueError('Wheel original digest mismatch: ' + name)
            if name.endswith(('.py', '.pyi')):
                modules.append({'module': name, 'sha256': hashlib.sha256(data).hexdigest(),
                                **python_interface(data.decode('utf-8'))})
        return {'entrance': records[0], 'modules': modules}


def source_projects(root: Path, files=None) -> dict:
    """Source-only projection of normal setuptools declarations, not a wheel PASS."""
    root = root.resolve()
    if files is None:
        files = sorted(set(subprocess.check_output(
            ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
            cwd=root).decode().split('\0')) - {''})
    roots = []
    modules = {}
    for manifest in files:
        path = PurePosixPath(manifest)
        if path.name != 'pyproject.toml' or 'fixtures' in path.parts:
            continue
        manifest_path = (root / manifest).resolve()
        if not manifest_path.is_relative_to(root):
            raise ValueError('Escaped Python distribution manifest')
        data = tomllib.loads(manifest_path.read_text())
        project = data.get('project')
        if project is None:
            continue
        backend = data.get('build-system', {}).get('build-backend', 'setuptools.build_meta')
        if backend != 'setuptools.build_meta':
            raise ValueError('Unregistered Python distribution backend: ' + manifest)
        discovery = data.get('tool', {}).get('setuptools', {}).get('packages', {}).get('find', {'where': ['.']})
        if not isinstance(discovery, dict) or not isinstance(discovery.get('where'), list) or not discovery['where']:
            raise ValueError('Unregistered Python distribution discovery: ' + manifest)
        directories = [(root / path.parent / where).resolve() for where in discovery['where']]
        if any(not directory.is_relative_to(root) for directory in directories):
            raise ValueError('Escaped Python distribution source')
        members = []
        for name in files:
            if not name.endswith(('.py', '.pyi')):
                continue
            source_path = (root / name).resolve()
            if any(source_path.is_relative_to(directory) for directory in directories):
                if not source_path.is_relative_to(root):
                    raise ValueError('Escaped Python interface member')
                raw = source_path.read_bytes()
                members.append(name)
                modules[name] = {'module': name, 'sha256': hashlib.sha256(raw).hexdigest(),
                                 **python_interface(raw.decode('utf-8'))}
        roots.append({'kind': 'python-wheel-source-candidate', 'name': project['name'], 'manifest': manifest,
                      'entrances': sorted(members), 'scripts': project.get('scripts', {})})
    return {'qualification': 'source-input-coverage-only', 'roots': roots,
            'modules': [modules[name] for name in sorted(modules)]}


def module_interfaces(root: Path, names) -> list:
    root = root.resolve()
    if not isinstance(names, list) or not all(isinstance(name, str) for name in names):
        raise ValueError('Invalid Python module projection request')
    modules = []
    for name in sorted(set(names)):
        path = (root / name).resolve()
        if not path.is_relative_to(root):
            raise ValueError('Escaped Python interface module')
        raw = path.read_bytes()
        if not name.endswith(('.py', '.pyi')) and not re.match(
                rb'^#!(?:/usr/bin/env[ \t]+python3?|/usr/bin/python3?)(?:[ \t\r\n]|$)', raw[:256]):
            raise ValueError('Unregistered Python script interface')
        modules.append({'module': name, 'sha256': hashlib.sha256(raw).hexdigest(),
                        **python_interface(raw.decode('utf-8'))})
    return modules


def source_blob_interfaces(values) -> list:
    """Project immutable caller-supplied source bytes with the same AST reader."""
    if not isinstance(values, list):
        raise ValueError('Invalid Python source blob projection')
    modules = []
    for item in values:
        if not isinstance(item, dict) or set(item) != {'module', 'source'} or not all(
                isinstance(item[key], str) for key in ['module', 'source']):
            raise ValueError('Invalid Python source blob')
        name = PurePosixPath(item['module'])
        if name.is_absolute() or '..' in name.parts or '\\' in str(name):
            raise ValueError('Escaped Python source blob')
        raw = item['source'].encode('utf-8')
        modules.append({'module': item['module'], 'sha256': hashlib.sha256(raw).hexdigest(),
                        **python_interface(item['source'])})
    return modules


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wheel', nargs='?')
    parser.add_argument('--source-root', type=Path)
    parser.add_argument('--modules-root', type=Path)
    parser.add_argument('--source-blobs', action='store_true')
    args = parser.parse_args()
    if sum(value is not None for value in [args.wheel, args.source_root, args.modules_root]) + args.source_blobs != 1:
        parser.error('Choose exactly one normal wheel, source root or module projection')
    result = (source_blob_interfaces(json.load(sys.stdin)) if args.source_blobs else
              source_projects(args.source_root) if args.source_root else
              module_interfaces(args.modules_root, json.load(sys.stdin)) if args.modules_root else
              wheel_interfaces(args.wheel))
    print(json.dumps(result, sort_keys=True))
