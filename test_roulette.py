import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('roulette', Path(__file__).with_name('roulette.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

class RouletteTests(unittest.TestCase):
    def test_selection_boundaries(self):
        themes = [{'slug': 'a', 'mode': 'dark'}, {'slug': 'b', 'mode': 'light'}, {'slug': 'c', 'mode': 'dark'}]
        self.assertEqual([t['slug'] for t in r.eligible(themes, {'pool':'Dark'}, 'a')], ['c'])
        self.assertEqual(r.eligible(themes, {'pool':'Dark', 'excludedThemes':['c']}, 'a'), [])
        self.assertEqual([t['slug'] for t in r.eligible(themes, {'pool':'Light'}, 'a')], ['b'])
        self.assertEqual(len(r.eligible(themes, {'pool':'Any'}, 'a')), 2)
        self.assertEqual(r.eligible(themes[:1], {}, 'a'), [])
        self.assertEqual(len(r.eligible(themes[:1], {}, 'other')), 1)
        with self.assertRaises(ValueError): r.eligible(themes, {'pool':'invalid'}, '')

    def test_real_resolver_overlays_and_legacy(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / 'home'; stock = Path(tmp) / 'omarchy'
            user = home / '.config/omarchy/themes'
            def theme(base, name, text=None, marker=False):
                p = base / name; p.mkdir(parents=True)
                if text is not None: (p / 'colors.toml').write_text(text)
                if marker: (p / 'light.mode').touch()
            theme(stock / 'themes', 'overlay', 'mode = "dark"\n')
            theme(user, 'overlay', 'mode = "light"\n')
            theme(stock / 'themes', 'inherited', 'mode = "light"\n')
            theme(user, 'inherited')
            theme(user, 'legacy', None, True)
            theme(user, 'explicit', 'mode = "dark"\n', True)
            theme(user, 'alias', 'theme_type = "light"\n')
            theme(user, 'bright', 'background = "#ffffff"\n')
            theme(user, 'fallback')
            theme(user, 'old')
            (user / 'old/alacritty.toml').write_text('[colors.primary]\nbackground = "#ffffff"\nforeground = "#000000"\n')
            with (user / 'old/alacritty.toml').open('a') as f:
                f.write('[colors.normal]\n' + ''.join(name + ' = "#888888"\n' for name in ('black','red','green','yellow','blue','magenta','cyan','white')))
            (user / 'custom-link').symlink_to(user / 'explicit', target_is_directory=True)
            result = {t['slug']:t['mode'] for t in r.catalog(home, stock)}
            self.assertEqual(result, {'overlay':'light', 'inherited':'light', 'legacy':'light',
                'explicit':'dark', 'alias':'light', 'bright':'light', 'fallback':'dark',
                'old':'light', 'custom-link':'dark'})
            self.assertFalse((user / 'old/colors.toml').exists(), 'Discovery must not mutate themes')

    def test_settings_and_command_dispatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            folder = home / '.config/omarchy'; folder.mkdir(parents=True)
            entry = {'id':r.PLUGIN_ID, 'enabled':True, 'pool':'Dark', 'excludedThemes':['excluded']}
            (folder / 'shell.json').write_text(json.dumps({'bar':{'layout':{'center':[entry]}}}))
            self.assertEqual(r.settings(home), entry)
            themes = [{'slug':'current', 'mode':'dark', 'name':'Current'},
                      {'slug':'chosen', 'mode':'dark', 'name':'Chosen'},
                      {'slug':'excluded', 'mode':'dark', 'name':'Excluded'}]
            with patch.object(r.Path, 'home', return_value=home), patch.object(r, 'catalog', return_value=themes), \
                 patch.object(r, 'current', return_value='current'), patch.dict(os.environ, {'XDG_RUNTIME_DIR':tmp}), \
                 patch.object(r.sys, 'argv', ['roulette.py','automatic']), patch.object(r.subprocess, 'run') as run:
                run.return_value = subprocess.CompletedProcess([], 0, '', '')
                r.main()
                run.assert_called_once_with(['omarchy','theme','set','chosen'], capture_output=True, text=True)
                entry['enabled'] = False
                (folder / 'shell.json').write_text(json.dumps({'plugins':[entry]}))
                run.reset_mock(); r.main(); run.assert_not_called()

if __name__ == '__main__': unittest.main()
