#!/usr/bin/env python3
"""Theme discovery/selection. Settings belong to Omarchy, never written here."""
import fcntl
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile

PLUGIN_ID = 'z.theme-roulette'
INTERVALS = (5, 15, 30, 60, 120, 240)


def settings(home):
    config = json.loads((home / '.config/omarchy/shell.json').read_text())
    entries = []
    for section in ('left', 'center', 'right'):
        entries.extend(config.get('bar', {}).get('layout', {}).get(section, []))
    entries.extend(config.get('plugins', []))
    return next((e for e in entries if isinstance(e, dict) and e.get('id') == PLUGIN_ID), {})


def current(home):
    try:
        return (home / '.local/state/omarchy/current/theme.name').read_text().strip()
    except FileNotFoundError:
        return ''


def catalog(home, omarchy):
    roots = [omarchy / 'themes', home / '.config/omarchy/themes']
    names = sorted({p.name for root in roots if root.is_dir() for p in root.iterdir()
                    if p.is_dir() and not p.name.startswith('.')})
    result = []
    for slug in names:
        # Only names round-tripping through omarchy theme set are selectable.
        if slug != slug.lower().replace(' ', '-') or '<' in slug or '>' in slug:
            continue
        with tempfile.TemporaryDirectory(prefix='theme-roulette-') as tmp:
            staged = Path(tmp)
            for base in roots:
                source = base / slug
                installed = not source.is_symlink() and (source / '.git').is_dir()
                for filename in ('colors.toml', 'light.mode', 'alacritty.toml'):
                    path = source / filename
                    if path.is_file() and not (installed and path.is_symlink()):
                        shutil.copyfile(path, staged / filename)
                # Same whole-file overlay ordering as Omarchy, not a TOML merge.
            if not (staged / 'colors.toml').exists() and (staged / 'alacritty.toml').exists():
                subprocess.run(['omarchy-theme-colors-from-alacritty', tmp],
                               check=True, capture_output=True, text=True)
            resolved = subprocess.run(['omarchy', 'theme', 'color', '--file',
                                       str(staged / 'colors.toml'), 'mode'],
                                      check=True, capture_output=True, text=True).stdout.strip()
        result.append({'slug': slug, 'name': slug.replace('-', ' ').title(),
                       'mode': resolved if resolved in ('dark', 'light') else 'unknown'})
    return result


def eligible(themes, config, active):
    pool = config.get('pool', 'Any')
    if pool not in ('Dark', 'Light', 'Any'):
        raise ValueError('Theme pool must be Dark, Light or Any')
    excluded = config.get('excludedThemes', [])
    if not isinstance(excluded, list):
        raise ValueError('Excluded themes must be a list')
    return [t for t in themes if t['slug'] != active and t['slug'] not in excluded
            and (pool == 'Any' or t['mode'] == pool.lower())]


def main():
    home = Path.home()
    omarchy = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy'))
    action = sys.argv[1] if len(sys.argv) > 1 else 'catalog'
    if action == 'catalog':
        print(json.dumps({'themes': catalog(home, omarchy), 'current': current(home)}))
        return
    if action not in ('switch', 'automatic'):
        raise ValueError('Unknown action')
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', str(home / '.cache')))
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'z.theme-roulette.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({'message': 'A theme change is already running'}))
            return
        themes = catalog(home, omarchy)
        # Re-read after discovery so recent pool/exclusion/enable edits win.
        config = settings(home)
        if action == 'automatic' and config.get('enabled') is not True:
            print(json.dumps({'message': 'Automatic switching is off'}))
            return
        candidates = eligible(themes, config, current(home))
        if not candidates:
            print(json.dumps({'message': 'No other eligible theme. Change the pool or exclusions.'}))
            return
        chosen = secrets.choice(candidates)
        result = subprocess.run(['omarchy', 'theme', 'set', chosen['slug']],
                                capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError((result.stderr or result.stdout or 'Theme change failed')[-3000:])
        print(json.dumps({'message': 'Switched to ' + chosen['name'], 'selected': chosen['slug']}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        sys.exit(1)
