"""Positive/negative Swift fixtures and CLI policy tests for the bounded UI guard."""
from collections import Counter
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'check-ui-source.py'
SPEC = importlib.util.spec_from_file_location('ui_source', SCRIPT)
guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = guard
SPEC.loader.exec_module(guard)


class SwiftFixtures(unittest.TestCase):
    def findings(self, source):
        return guard.scan('Miniti/Views/Example.swift', source)

    def test_raw_constructor_variants_fail(self):
        fixtures = [
            'Color(hex: "71717A")',
            'SwiftUI.Color /* comment */ (\n hex: "123456"\n)',
            'SwiftUI.Color.init(hex: token)',
            'Color(red: 0.2, green: 0.4, blue: 0.8)',
            'Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)',
            'UIColor(white: 0.8, alpha: 1)',
            'NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1)',
            'CGColor(gray: 0.3, alpha: 1)',
            'UIColor(hue: 0.5, saturation: 1, brightness: 1, alpha: 1)',
            'CGColor(colorSpace: space, components: [0, 0, 0, 1])',
            '#colorLiteral(red: 1, green: 0, blue: 0, alpha: 1)',
            'Color(`hex`: "ffffff")',
        ]
        for fixture in fixtures:
            with self.subTest(fixture=fixture):
                self.assertEqual([f.rule for f in self.findings(fixture)], ['raw-color'])

    def test_palette_assets_and_native_bridges_pass(self):
        source = '''
        ColorPalette.Text.dim
        Color("BrandAsset", bundle: .main)
        UIColor(named: "Asset")
        NSColor(ColorPalette.Text.dim)
        Color(nsColor: .labelColor)
        Color(cgColor: imageColor)
        Color(uiColor: make(red: 1))
        Color.accentColor
        .font(.body).frame(width: 9).padding(4)
        .focusable(true)
        .font(.system(size: metrics.body))
        .font(.system(size: 17))
        .font(.system(size: 12 + adjustment))
        RoundedRectangle(cornerRadius: Radius.control)
        '''
        self.assertEqual(self.findings(source), [])

    def test_comments_and_string_prose_do_not_flag(self):
        source = r'''
        // Color(hex: "fake")
        /* outer Color(red: 1) /* nested .focusable(false) */ end */
        let example = "Color(hex: \"fake\") and .focusable(false)"
        let raw = #"Color(hex: "fake") and .font(.system(size: 9))"#
        let multiline = """
        Color(hex: "fake")
        """
        let rawMulti = ##"""
        Color(hex: "fake")
        """##
        '''
        self.assertEqual(self.findings(source), [])

    def test_interpolation_code_is_checked_in_normal_and_raw_strings(self):
        fixtures = [
            r'"value \(Color(hex: "123456"))"',
            r'#"value \#(Color(hex: "123456"))"#',
            r'"""value \(Color(hex: "123456"))"""',
            r'"value \(f("nested \(Color(hex: "123456"))"))"',
        ]
        for source in fixtures:
            with self.subTest(source=source):
                self.assertEqual([f.rule for f in self.findings(source)], ['raw-color'])

    def test_escaped_interpolation_is_not_code(self):
        self.assertEqual(self.findings(r'"value \\(Color(hex: fake))"'), [])
        self.assertEqual(self.findings(r'#"value \(Color(hex: fake))"#'), [])

    def test_multiline_reports_real_location(self):
        found = self.findings('/*\nignored\n*/\nSwiftUI.Color(\nhex: "abc"\n)')
        self.assertEqual(found[0].line, 4)

    def test_whitespace_and_comments_preserve_baseline_signature(self):
        first = self.findings('Color(hex: "abc")')[0].key
        second = self.findings('Color /* nested /* comment */ */ (\nhex : "abc" )')[0].key
        self.assertEqual(first, second)

    def test_small_fonts_are_review_cues_only(self):
        for source in ['.font(.system(size: 9, weight: .medium))',
                       'UIFont.systemFont(ofSize: 12.5)', 'NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)']:
            with self.subTest(source=source):
                self.assertEqual([f.rule for f in self.findings(source)], ['small-fixed-font'])

    def test_focus_and_local_geometry_are_review_cues(self):
        found = self.findings('.focusable(false).background(RoundedRectangle(cornerRadius: 6)).cornerRadius(4)')
        self.assertEqual([f.rule for f in found], ['focus-opt-out', 'local-chrome', 'local-chrome'])

    def test_ternary_names_are_not_argument_labels(self):
        for source in ['Color(flag ? red : blue)', 'Color(flag ? white : gray)',
                       'Color(nsColor: flag ? red : blue)']:
            self.assertEqual(self.findings(source), [], source)
        self.assertEqual([f.rule for f in self.findings('Color(.sRGB, red: flag ? white : gray, green: 0, blue: 0)')], ['raw-color'])

    def test_documented_uncovered_geometry_forms(self):
        for source in ['UnevenRoundedRectangle(topLeadingRadius: 8)',
                       'UnevenRoundedRectangle(cornerRadii: radii)',
                       '.clipShape(.rect(cornerRadius: 8))', 'layer.cornerRadius = 6']:
            self.assertEqual(self.findings(source), [], source)

    def test_unterminated_source_fails_closed(self):
        for source in ['/* unfinished', '"unfinished', 'Color(hex: "abc"', 'Text("abc") }']:
            with self.subTest(source=source), self.assertRaises(ValueError):
                self.findings(source)


class BaselinePolicy(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Miniti/Views').mkdir(parents=True)
        (self.root / 'MinitiMobile').mkdir()
        self.source = self.root / 'Miniti/Views/Example.swift'
        self.source.write_text('Color(hex: "71717A")\n')
        self.baseline = self.root / 'baseline.json'
        self.set_baseline()

    def set_baseline(self):
        _, findings = guard.inventory(self.root)
        self.baseline.write_text(json.dumps({'version': 1, 'entries': [
            dict(path=p, rule=r, signature=s, count=c)
            for (p, r, s), c in Counter(f.key for f in findings).items()
        ]}))

    def run_guard(self, *args):
        result = subprocess.run([sys.executable, str(SCRIPT), '--root', str(self.root),
                                 '--baseline', 'baseline.json', *args], capture_output=True, text=True)
        return result.returncode, result.stdout + result.stderr

    def test_existing_debt_passes_and_inventory_lists_it(self):
        code, output = self.run_guard('--inventory')
        self.assertEqual(code, 0, output)
        self.assertIn('Miniti/Views/Example.swift:1: raw-color:', output)

    def test_growth_new_value_and_new_file_fail(self):
        for kind in ['duplicate', 'changed', 'new-file']:
            with self.subTest(kind=kind):
                self.source.write_text('Color(hex: "71717A")\n')
                other = self.root / 'MinitiMobile/NewView.swift'
                other.unlink(missing_ok=True)
                if kind == 'duplicate':
                    self.source.write_text(self.source.read_text() * 2)
                elif kind == 'changed':
                    self.source.write_text('Color(hex: "abcdef")')
                else:
                    other.write_text(self.source.read_text())
                code, output = self.run_guard()
                self.assertEqual(code, 1, output)
                self.assertIn('ERROR:', output)

    def test_deleted_debt_requires_prune_and_cannot_return(self):
        self.source.write_text('ColorPalette.Text.dim')
        code, output = self.run_guard()
        self.assertEqual(code, 1, output)
        self.assertIn('STALE:', output)
        self.assertEqual(self.run_guard('--prune-baseline')[0], 0)
        self.assertEqual(json.loads(self.baseline.read_text())['entries'], [])
        self.source.write_text('Color(hex: "71717A")')
        self.assertEqual(self.run_guard()[0], 1)

    def test_prune_never_accepts_new_raw_color_or_writes_on_error(self):
        before = self.baseline.read_bytes()
        self.source.write_text('Color(hex: "new")')
        self.assertEqual(self.run_guard('--prune-baseline')[0], 1)
        self.assertEqual(self.baseline.read_bytes(), before)

    def test_prune_decreases_duplicate_count(self):
        self.source.write_text('Color(hex: "71717A")\n' * 2)
        self.set_baseline()
        self.source.write_text('Color(hex: "71717A")')
        self.assertEqual(self.run_guard('--prune-baseline')[0], 0)
        self.assertEqual(json.loads(self.baseline.read_text())['entries'][0]['count'], 1)

    def test_review_cues_are_visible_but_do_not_fail_or_auto_baseline(self):
        self.source.write_text(self.source.read_text() + '\n.focusable(false).font(.system(size: 9)).cornerRadius(6)')
        for args in [(), ('--prune-baseline',)]:
            code, output = self.run_guard(*args)
            self.assertEqual(code, 0, output)
            self.assertIn('3 review cues', output)
            self.assertIn('REVIEW:', output)
        self.assertEqual(len(json.loads(self.baseline.read_text())['entries']), 1)

    def test_palette_excluded_but_new_helper_outside_views_is_scanned(self):
        (self.root / 'Miniti/Models').mkdir()
        (self.root / 'Miniti/Models/ColorPalette.swift').write_text('Color(hex: "fff")')
        self.assertEqual(self.run_guard()[0], 0)
        (self.root / 'Miniti/Models/Helper.swift').write_text('Color(hex: "fff")')
        self.assertEqual(self.run_guard()[0], 1)

    def test_tests_watch_and_assets_are_outside_main_app_scope(self):
        for directory in ['MinitiTests', 'MinitiWatch', 'MinitiLiveActivity']:
            (self.root / directory).mkdir()
            (self.root / directory / 'Example.swift').write_text('Color(hex: "fff")')
        (self.root / 'Miniti/Assets.xcassets').mkdir()
        (self.root / 'Miniti/Assets.xcassets/Contents.json').write_text('{"red": 1}')
        self.assertEqual(self.run_guard()[0], 0)

    def test_growth_reports_every_matching_line(self):
        self.source.write_text('Color(hex: "71717A")\n\n\n\nColor(hex: "71717A")')
        code, output = self.run_guard()
        self.assertEqual(code, 1)
        self.assertIn('Example.swift:1,5: raw-color: +1 (all matching lines)', output)
        self.source.write_text('.font(.system(size: 9))')
        self.set_baseline()
        self.source.write_text('.font(.system(size: 9))\n\n\n\n.font(.system(size: 9))')
        code, output = self.run_guard()
        self.assertEqual(code, 0)
        self.assertIn('Example.swift:1,5: small-fixed-font: +1 (all matching lines)', output)

    def test_reviewed_path_only_move_preserves_debt_count(self):
        destination = self.root / 'MinitiMobile/Moved.swift'
        self.source.rename(destination)
        before = self.baseline.read_bytes()
        self.assertEqual(self.run_guard('--prune-baseline')[0], 1)
        self.assertEqual(self.baseline.read_bytes(), before)
        data = json.loads(before)
        data['entries'][0]['path'] = 'MinitiMobile/Moved.swift'
        self.baseline.write_text(json.dumps(data))
        self.assertEqual(self.run_guard()[0], 0)

    def test_unknown_baseline_version_fails(self):
        data = json.loads(self.baseline.read_text())
        data['version'] = 2
        self.baseline.write_text(json.dumps(data))
        self.assertEqual(self.run_guard()[0], 2)

    def test_missing_source_root_is_not_a_clean_pass(self):
        (self.root / 'MinitiMobile').rmdir()
        self.assertEqual(self.run_guard()[0], 2)

    def test_duplicate_invalid_or_zero_baseline_entry_fails(self):
        original = json.loads(self.baseline.read_text())
        for mode in ['duplicate', 'zero', 'path', 'rule']:
            data = json.loads(json.dumps(original))
            if mode == 'duplicate':
                data['entries'] *= 2
            elif mode == 'zero':
                data['entries'][0]['count'] = 0
            elif mode == 'path':
                data['entries'][0]['path'] = '../escape.swift'
            else:
                data['entries'][0]['rule'] = 'typo'
            self.baseline.write_text(json.dumps(data))
            self.assertEqual(self.run_guard()[0], 2, mode)


if __name__ == '__main__':
    unittest.main()
