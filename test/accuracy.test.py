#!/usr/bin/env python3
"""Accuracy acceptance tests. Fixtures and process shims never use the network."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'bin/what-changed'
BASE = int(dt.datetime(2026, 9, 16, 5, 57, 19, tzinfo=dt.timezone.utc).timestamp())
KEYRING = 'pacman -Sy --noconfirm archlinux-keyring'
SYSTEM = 'pacman -Syu --noconfirm --overwrite /usr/share/omarchy/*'


def stamp(second):
    return dt.datetime.fromtimestamp(BASE + second, dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S+0000')


def command(second, argv):
    return f"[{stamp(second)}] [PACMAN] Running '{argv}'\n"


def alpm(second, message):
    return f'[{stamp(second)}] [ALPM] {message}\n'


def transaction(second, argv, events, end=None, complete=True):
    end = second + 1 if end is None else end
    return (command(second, argv) + alpm(second, 'transaction started')
            + ''.join(alpm(second, e) for e in events)
            + (alpm(end, 'transaction completed') if complete else ''))


def update(events=None, complete=True):
    return transaction(0, KEYRING, ['reinstalled archlinux-keyring (20260902-1)']) + transaction(
        2, SYSTEM, ['upgraded omarchy (4.0.3-1 -> 4.0.4-1)'] if events is None else events,
        end=3, complete=complete)


def rows(payload):
    return [r for g in payload['groups'] for r in g['items'] if r['kind'] == 'pkg']


class Accuracy(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / 'state'
        (self.state / 'migrations').mkdir(parents=True)
        self.log = self.root / 'pacman.log'
        self.proc = self.root / 'proc-stat'
        self.proc.write_text(f'btime {BASE - 100}\n')
        shim = self.root / 'bin'
        shim.mkdir()
        for name, body in [('curl', 'exit 6'), ('omarchy-channel-current', 'echo stable'),
                           ('pacman', 'echo "omarchy 99.99.99-1"')]:
            file = shim / name
            file.write_text('#!/bin/sh\n' + body + '\n')
            file.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(shim) + ':' + os.environ['PATH'],
                    'WHAT_CHANGED_STATE_DIR': str(self.state), 'WHAT_CHANGED_PROC_STAT': str(self.proc),
                    'WHAT_CHANGED_PACMAN_LOG': str(self.log), 'WHAT_CHANGED_STATE_HOME': str(self.root / 'read'),
                    'WHAT_CHANGED_CACHE_DIR': str(self.root / 'cache'), 'WHAT_CHANGED_OWN_WINDOW': '3600'}
        self.env.pop('WHAT_CHANGED_REBOOT_MARKER_EPOCH', None)

    def marker(self, second=20):
        path = self.state / 'migrations/1789325478.sh'
        path.touch()
        os.utime(path, (BASE + second, BASE + second))

    def cli(self, *args, json_output=True):
        result = subprocess.run([str(CLI), *args, *(['--json'] if json_output else [])],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return json.loads(result.stdout) if json_output else result.stdout

    def show(self):
        return self.cli('show', '--expand', 'other')

    def test_real_404_migration_and_boot(self):
        self.log.write_text((ROOT / 'test/fixtures/update-4.0.4.log').read_text())
        self.marker(22)  # 07:57:41 local
        out = self.show()
        self.assertEqual(out['session']['id'], '20260916T055719Z')
        self.assertEqual(out['session']['counts']['total'], 6)
        self.assertEqual(out['session']['nearbyCounts']['total'], 0)
        self.assertEqual(out['session']['rebootReason'], ['linux-omarchy'])
        self.assertEqual(out['session']['rebootStatus'], 'pending')
        self.assertTrue(out['session']['rebootRequired'])
        self.assertEqual(len(rows(out)), 6)
        migrated = [r['name'] for r in rows(out) if r['attribution'] == 'migration-inferred']
        self.assertEqual(sorted(migrated), ['linux-omarchy', 'linux-omarchy-headers', 'pahole'])
        self.assertEqual([r['name'] for g in out['groups'] if g['id'] == 'reboot' for r in g['items']], ['linux-omarchy'])
        self.proc.write_text(f'btime {BASE + 100}\n')
        rebooted = self.show()['session']
        self.assertEqual(rebooted['rebootStatus'], 'rebooted')
        self.assertFalse(rebooted['rebootRequired'])
        self.assertEqual(rebooted['rebootReason'], ['linux-omarchy'])

    def test_kernel_families_and_classification_retention(self):
        events = [f'upgraded filler{i} (1 -> 2)' for i in range(600)] + [
            f'installed {n} (7.2.5-3)' for n in ['linux-omarchy', 'linux-t2', 'linux-omarchy-headers', 'linux-t2-headers', 'mesa-utils', 'linux-firmwarefake', 'nvidiafake']]
        self.log.write_text(update(events))
        out = self.show()
        reboot = next(g for g in out['groups'] if g['id'] == 'reboot')
        self.assertEqual([r['name'] for r in reboot['items']], ['linux-omarchy', 'linux-t2'])
        self.assertEqual(out['session']['counts']['total'], 608)
        self.assertEqual(out['session']['counts']['omitted'], 108)
        self.assertEqual(len(rows(out)), 500)

    def test_candidate_command_forms_and_independent_aur_provenance(self):
        forms = ['pacman -S --noconfirm --needed candidate', 'pacman -S --noconfirm --needed -- candidate',
                 'pacman -Rns --noconfirm candidate', 'pacman -S --noconfirm --ask 4 candidate',
                 'pacman -S --noconfirm --ask=4 candidate', 'pacman --sync candidate',
                 'pacman -U --needed --config /etc/pacman.conf /home/test/.cache/yay/candidate/file.pkg.tar.zst',
                 'pacman -U --needed /home/test/.cache/paru/candidate/file.pkg.tar.zst']
        for form in forms:
            with self.subTest(form=form):
                self.log.write_text(update() + transaction(4, form, ['installed candidate (1.0-1)']))
                self.marker()
                out = self.show()
                row = next(r for r in rows(out) if r['name'] == 'candidate')
                self.assertEqual(row['attribution'], 'migration-inferred')
                self.assertEqual(row['aur'], '.cache/' in form)
                self.assertEqual(out['session']['counts']['total'], 3)
                self.assertEqual(out['session']['counts']['aur'], int('.cache/' in form))
                self.assertEqual(next(g for g in out['groups'] if g['id'] == 'migration-packages')['count'], 1)

    def test_keyring_separator_is_recognized_without_markers(self):
        for separator in ['', '-- ']:
            with self.subTest(separator=separator):
                self.log.write_text(update() + transaction(4, f'pacman -S --noconfirm --needed {separator}omarchy-keyring', ['installed omarchy-keyring (1-1)']))
                row = next(r for r in rows(self.show()) if r['name'] == 'omarchy-keyring')
                self.assertEqual(row['attribution'], 'update-command')

    def test_inclusive_bracket_and_unfinished_candidates(self):
        self.marker(10)
        self.log.write_text(update() + transaction(3, 'pacman -S first', ['installed first (1)'], end=3)
                            + transaction(10, 'pacman -S last', ['installed last (1)'], end=10)
                            + transaction(10, 'pacman -S unfinished', ['installed unfinished (1)'], complete=False))
        out = self.show()
        attribution = {r['name']: r['attribution'] for r in rows(out)}
        self.assertEqual(attribution['first'], 'migration-inferred')
        self.assertEqual(attribution['last'], 'migration-inferred')
        self.assertEqual(attribution['unfinished'], 'nearby-uncertain')
        self.assertEqual(out['session']['counts']['total'], 4)
        self.assertEqual(out['session']['nearbyCounts']['total'], 1)
        self.assertFalse(out['session']['incomplete'])

    def test_missing_failed_and_partial_migration_markers(self):
        self.log.write_text(update() + transaction(4, 'pacman -S linux-t2', ['installed linux-t2 (7)'])
                            + transaction(11, 'pacman -S mesa', ['installed mesa (1)']))
        missing = self.show()
        self.assertEqual(missing['session']['counts']['total'], 2)
        self.assertEqual(missing['session']['nearbyCounts']['total'], 2)
        self.assertFalse(missing['session']['rebootRequired'])
        self.marker(5)
        partial = self.show()
        self.assertEqual(partial['session']['rebootReason'], ['linux-t2'])
        self.assertEqual(partial['session']['nearbyCounts']['total'], 1)
        self.log.write_text(update(complete=False) + transaction(4, 'pacman -S linux-t2', ['installed linux-t2 (7)']))
        failed = self.show()
        self.assertTrue(failed['session']['incomplete'])
        self.assertEqual(failed['session']['counts']['total'], 2)
        self.assertEqual(failed['session']['rebootReason'], [])

    def test_noop_system_step_uses_last_activity_with_completed_marker(self):
        no_op = transaction(0, KEYRING, ['reinstalled archlinux-keyring (1)']) + command(2, SYSTEM)
        no_op += f'[{stamp(3)}] [PACMAN] starting full system upgrade\n'
        self.log.write_text(no_op + transaction(3, 'pacman -S linux-omarchy', ['installed linux-omarchy (7)'], end=4))
        self.marker(4)
        out = self.show()
        self.assertEqual(out['session']['counts']['total'], 2)
        self.assertEqual(out['session']['nearbyCounts']['total'], 0)
        self.assertEqual(out['session']['rebootStatus'], 'pending')
        self.assertEqual(out['session']['rebootReason'], ['linux-omarchy'])
        self.assertEqual(out['session']['finishedAt'], stamp(3))
        self.assertFalse(out['session']['incomplete'])
        kernel = next(r for r in rows(out) if r['name'] == 'linux-omarchy')
        self.assertEqual(kernel['attribution'], 'migration-inferred')

    def test_noop_system_step_without_marker_remains_uncertain(self):
        self.log.write_text(transaction(0, KEYRING, ['reinstalled archlinux-keyring (1)']) + command(2, SYSTEM)
                            + transaction(4, 'pacman -S linux-omarchy', ['installed linux-omarchy (7)']))
        out = self.show()
        self.assertEqual(out['session']['counts']['total'], 1)
        self.assertEqual(out['session']['nearbyCounts']['total'], 1)
        self.assertFalse(out['session']['rebootRequired'])
        self.assertEqual(out['session']['rebootReason'], [])

    def test_unfinished_final_system_step_cannot_use_noop_fallback(self):
        self.log.write_text(update() + transaction(6, SYSTEM, ['upgraded zlib (1 -> 2)'], complete=False)
                            + transaction(8, 'pacman -S linux-omarchy', ['installed linux-omarchy (7)']))
        self.marker(10)
        out = self.show()
        self.assertTrue(out['session']['incomplete'])
        self.assertEqual(out['session']['nearbyCounts']['total'], 1)
        self.assertEqual(out['session']['rebootReason'], [])

    def test_final_system_upgrade_sets_bracket(self):
        self.log.write_text(update() + transaction(4, 'pacman -S early', ['installed early (1)'])
                            + transaction(6, SYSTEM, ['upgraded omarchy (4.0.4-1 -> 4.0.5-1)'])
                            + transaction(8, 'pacman -S late', ['installed late (1)']))
        self.marker(10)
        attrs = {r['name']: r['attribution'] for r in rows(self.show())}
        self.assertEqual(attrs['early'], 'nearby-uncertain')
        self.assertEqual(attrs['late'], 'migration-inferred')

    def test_fixed_window_never_rolls_with_candidates(self):
        self.log.write_text(update() + transaction(1803, 'pacman -S at-end', ['installed at-end (1)'], end=1803)
                            + transaction(1804, 'pacman -S too-late', ['installed too-late (1)'])
                            + transaction(4000, 'pacman -Rns fake-orphan', ['removed fake-orphan (1)']))
        self.marker(1803)
        out = self.show()
        self.assertEqual(out['session']['counts']['total'], 3)
        self.assertEqual(out['session']['nearbyCounts']['total'], 0)
        self.assertEqual(out['session']['finishedAt'], stamp(3))
        self.assertNotIn('too-late', [r['name'] for r in rows(out)])
        self.assertNotIn('fake-orphan', [r['name'] for r in rows(out)])

    def test_candidate_before_system_completion_remains_uncertain(self):
        self.log.write_text(transaction(0, KEYRING, []) + transaction(1, 'pacman -S before', ['installed before (1)'])
                            + transaction(4, SYSTEM, ['upgraded omarchy (4.0.3-1 -> 4.0.4-1)']))
        self.marker()
        row = next(r for r in rows(self.show()) if r['name'] == 'before')
        self.assertEqual(row['attribution'], 'nearby-uncertain')

    def test_nested_keyring_and_same_second_exclusive_ownership(self):
        self.log.write_text(update() + transaction(10, 'pacman -S first', ['installed first (1)'], end=10)
                            + transaction(10, KEYRING, ['reinstalled archlinux-keyring (1)'], end=10)
                            + transaction(10, 'pacman -S second', ['installed second (1)'], end=10))
        self.marker(10)
        sessions = self.cli('sessions')['sessions']
        self.assertEqual(len(sessions), 2)
        all_rows = []
        for session in sessions:
            out = self.cli('show', session['id'], '--expand', 'other')
            all_rows.extend(rows(out))
            if session['id'] == '20260916T055729Z':
                self.assertEqual(out['session']['counts']['total'], 1)
                self.assertEqual(out['session']['nearbyCounts']['total'], 1)
        self.assertEqual(sum(r['name'] == 'first' for r in all_rows), 1)
        self.assertEqual(sum(r['name'] == 'second' for r in all_rows), 1)
        self.assertEqual(sum(r['name'] == 'archlinux-keyring' for r in all_rows), 2)
        self.assertTrue(all(r['attribution'] == 'nearby-uncertain' for r in all_rows if r['name'] in ['first', 'second']))

    def test_large_summary_version_sequence_and_nearby_counts(self):
        events = [f'upgraded filler{i} (1 -> 2)' for i in range(600)] + [
            'upgraded omarchy (4.0.2-1 -> 4.0.3-1)', 'upgraded linux-omarchy (7.1-1 -> 7.2-1)',
            'upgraded omarchy (4.0.3-1 -> 4.0.4-1)']
        self.log.write_text(update(events) + transaction(30, 'pacman -S manual', [f'installed manual{i} (1)' for i in range(600)]))
        out = self.show()
        self.assertEqual(out['session']['counts']['total'], 604)
        self.assertEqual(out['session']['counts']['upgraded'], 603)
        self.assertEqual(out['session']['counts']['omitted'], 104)
        self.assertEqual(out['session']['omarchy']['from'], '4.0.2-1')
        self.assertEqual(out['session']['omarchy']['to'], '4.0.4-1')
        self.assertEqual(out['session']['nearbyCounts']['total'], 600)
        self.assertEqual(out['session']['nearbyCounts']['omitted'], 100)
        self.assertEqual(len(rows(out)), 1000)
        self.assertEqual(sum(r['name'] == 'omarchy' for r in rows(out)), 2)
        self.assertEqual(sum(g['count'] for g in out['groups']), 1204)
        self.assertEqual(self.cli('compare-url', json_output=False).strip(), 'https://github.com/omacom/omarchy/compare/v4.0.2...v4.0.4')

    def test_stable_dev_switches_and_version_removal(self):
        for source, dest in [('omarchy', 'omarchy-dev'), ('omarchy-dev', 'omarchy')]:
            with self.subTest(source=source):
                self.log.write_text(update([f'removed {source} (4.0.3-1)', f'installed {dest} (4.0.4-1)']))
                version = self.show()['session']['omarchy']
                self.assertEqual((version['from'], version['to'], version['package'], version['jumped']), ('4.0.3-1', '4.0.4-1', dest, True))
        self.log.write_text(update(['removed omarchy (4.0.3-1)']) + transaction(30, KEYRING, [])
                            + transaction(31, SYSTEM, ['upgraded zlib (1 -> 2)']))
        sessions = self.cli('sessions')['sessions']
        self.assertEqual(sessions[0]['omarchy']['to'], '')
        self.assertEqual(sessions[0]['omarchy']['from'], '')
        self.assertFalse(sessions[0]['omarchy']['jumped'])
        self.assertEqual(sessions[1]['omarchy']['from'], '4.0.3-1')
        self.assertEqual(sessions[1]['omarchy']['to'], '')
        self.assertFalse(sessions[1]['omarchy']['jumped'])

    def test_installer_history_seeds_first_updates_without_creating_a_jump(self):
        self.log.write_text(transaction(-20, 'pacman -S omarchy', ['installed omarchy (4.0.1-1)'])
                            + update(['upgraded zlib (1 -> 2)'])
                            + transaction(30, KEYRING, ['reinstalled archlinux-keyring (1)']))
        sessions = self.cli('sessions')['sessions']
        self.assertEqual(len(sessions), 2)
        for session in sessions:
            self.assertEqual(session['omarchy']['package'], 'omarchy')
            self.assertEqual(session['omarchy']['from'], '4.0.1-1')
            self.assertEqual(session['omarchy']['to'], '4.0.1-1')
            self.assertFalse(session['omarchy']['jumped'])
        self.assertEqual(sessions[1]['counts']['total'], 2)
        self.assertEqual(self.cli('status')['newest']['omarchy']['to'], '4.0.1-1')
        self.assertEqual(self.cli('notes')['status'], 'no-jump')
        self.assertIn('omarchy 4.0.1', self.cli('show', json_output=False).splitlines()[0])
        self.assertNotIn('installed omarchy', self.cli('show', '--expand', 'other', json_output=False))

    def test_channel_switch_outside_window_seeds_next_session(self):
        for source, dest in [('omarchy', 'omarchy-dev'), ('omarchy-dev', 'omarchy')]:
            with self.subTest(source=source):
                self.log.write_text(update([f'upgraded {source} (4.0.3-1 -> 4.0.4-1)'])
                                    + transaction(5000, f'pacman -S --needed --noconfirm --ask 4 {dest}',
                                                  [f'removed {source} (4.0.4-1)', f'installed {dest} (4.0.5-1)'])
                                    + transaction(6000, KEYRING, ['reinstalled archlinux-keyring (1)'])
                                    + transaction(6002, SYSTEM, ['upgraded zlib (1 -> 2)']))
                sessions = self.cli('sessions')['sessions']
                self.assertEqual(sessions[0]['omarchy']['package'], dest)
                self.assertEqual(sessions[0]['omarchy']['from'], '4.0.5-1')
                self.assertEqual(sessions[0]['omarchy']['to'], '4.0.5-1')
                self.assertFalse(sessions[0]['omarchy']['jumped'])
                self.assertEqual(sessions[0]['counts']['total'], 2)
                self.assertEqual(sessions[0]['nearbyCounts']['total'], 0)
                self.assertEqual(sessions[1]['omarchy']['to'], '4.0.4-1')
                self.assertTrue(sessions[1]['omarchy']['jumped'])
                self.assertEqual(sessions[1]['counts']['total'], 2)
                self.assertEqual(sessions[1]['nearbyCounts']['total'], 0)
                self.assertEqual(self.cli('notes')['status'], 'no-jump')

    def test_manual_removal_seeds_unknown_and_does_not_rewrite_history(self):
        self.log.write_text(update() + transaction(5000, 'pacman -Rns --noconfirm omarchy', ['removed omarchy (4.0.4-1)'])
                            + transaction(6000, KEYRING, []) + transaction(6002, SYSTEM, ['upgraded zlib (1 -> 2)']))
        sessions = self.cli('sessions')['sessions']
        self.assertEqual(sessions[0]['omarchy']['from'], '')
        self.assertEqual(sessions[0]['omarchy']['to'], '')
        self.assertFalse(sessions[0]['omarchy']['jumped'])
        self.assertEqual(sessions[1]['omarchy']['to'], '4.0.4-1')
        self.assertTrue(sessions[1]['omarchy']['jumped'])

    def test_installer_removal_and_inactive_package_removal(self):
        self.log.write_text(transaction(-20, 'pacman -S omarchy', ['installed omarchy (4.0.1-1)'])
                            + transaction(-10, 'pacman -R omarchy', ['removed omarchy (4.0.1-1)'])
                            + update(['upgraded zlib (1 -> 2)']))
        self.assertEqual(self.show()['session']['omarchy']['to'], '')
        self.log.write_text(transaction(-20, 'pacman -S omarchy-dev', ['installed omarchy-dev (4.0.2-1)'])
                            + transaction(-10, 'pacman -R omarchy', ['removed omarchy (4.0.1-1)'])
                            + update(['upgraded zlib (1 -> 2)']))
        self.assertEqual(self.show()['session']['omarchy']['package'], 'omarchy-dev')
        self.assertEqual(self.show()['session']['omarchy']['to'], '4.0.2-1')

    def test_unknown_initial_history_is_never_todays_installed_version(self):
        self.log.write_text(update(['upgraded zlib (1 -> 2)']))
        self.assertEqual(self.show()['session']['omarchy']['to'], '')

    def test_same_release_reinstall_and_unsupported_version(self):
        for event in ['reinstalled omarchy (4.0.4-1)', 'upgraded omarchy (4.0.4-1 -> 4.0.4-2)',
                      'upgraded omarchy-dev (4.0.3-1 -> 4.0.4.r23-1)',
                      'upgraded omarchy-dev (4.0.3-custom -> 4.0.4-1)']:
            with self.subTest(event=event):
                self.log.write_text(update([event]))
                self.assertFalse(self.show()['session']['omarchy']['jumped'])
                self.assertEqual(self.cli('notes')['status'], 'no-jump')
                result = subprocess.run([str(CLI), 'compare-url'], env=self.env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)

    def test_uncertain_omarchy_seeds_future_session_without_changing_its_own_jump(self):
        self.log.write_text(update() + transaction(4, 'pacman -S omarchy-dev', ['removed omarchy (4.0.4-1)', 'installed omarchy-dev (4.0.5-1)'])
                            + transaction(30, KEYRING, []))
        sessions = self.cli('sessions')['sessions']
        self.assertEqual(sessions[0]['omarchy']['package'], 'omarchy-dev')
        self.assertEqual(sessions[0]['omarchy']['from'], '4.0.5-1')
        self.assertEqual(sessions[0]['omarchy']['to'], '4.0.5-1')
        self.assertFalse(sessions[0]['omarchy']['jumped'])
        self.assertEqual(sessions[0]['counts']['total'], 0)
        self.assertEqual(sessions[1]['omarchy']['from'], '4.0.3-1')
        self.assertEqual(sessions[1]['omarchy']['to'], '4.0.4-1')
        self.assertEqual(sessions[1]['counts']['total'], 2)
        self.assertEqual(sessions[1]['nearbyCounts']['total'], 2)

    def test_boot_before_after_equal_missing_and_invalid_event_time(self):
        self.log.write_text(update(['installed linux-t2 (7)']))
        for boot, status in [(BASE - 1, 'pending'), (BASE + 5, 'rebooted'), (BASE + 2, 'unknown')]:
            with self.subTest(boot=boot):
                self.proc.write_text(f'btime {boot}\n')
                session = self.show()['session']
                self.assertEqual(session['rebootStatus'], status)
                self.assertEqual(session['rebootRequired'], status == 'pending')
        for content in ['', 'btime invalid\n']:
            self.proc.write_text(content)
            self.assertEqual(self.show()['session']['rebootStatus'], 'unknown')
        self.proc.unlink()
        self.assertEqual(self.show()['session']['rebootStatus'], 'unknown')
        self.proc.write_text(f'btime {BASE-100}\n')
        self.log.write_text(update(['installed linux-t2 (7)']).replace(alpm(2, 'installed linux-t2 (7)'), '[not-a-time] [ALPM] installed linux-t2 (7)\n'))
        self.assertEqual(self.show()['session']['rebootStatus'], 'unknown')

    def test_empty_history_still_reports_current_marker_without_unread(self):
        self.log.write_text('')
        (self.state / 'reboot-required').touch()
        self.env['WHAT_CHANGED_REBOOT_MARKER_EPOCH'] = str(BASE + 1)
        status = self.cli('status')
        self.assertEqual(status['currentRebootRequest'], 'pending')
        self.assertIsNone(status['newest'])
        self.assertFalse(status['unread'])

    def test_current_marker_is_separate_and_never_makes_unread(self):
        self.log.write_text(update(['upgraded zlib (1 -> 2)']))
        self.cli('mark-read', json_output=False)
        marker = self.state / 'reboot-required'
        marker.touch()
        self.proc.write_text(f'btime {BASE}\n')
        for second, expected in [(-1, 'stale'), (1, 'pending'), (0, 'unknown')]:
            with self.subTest(second=second):
                self.env['WHAT_CHANGED_REBOOT_MARKER_EPOCH'] = str(BASE + second)
                show = self.show()
                self.assertEqual(show['currentRebootRequest'], expected)
                self.assertEqual(show['session']['rebootStatus'], 'not-indicated')
                self.assertEqual(show['session']['rebootReason'], [])
                self.assertFalse(show['session']['rebootRequired'])
                self.assertFalse(self.cli('status')['unread'])
                self.assertEqual(self.cli('sessions')['currentRebootRequest'], expected)
        self.proc.unlink()
        self.assertEqual(self.show()['currentRebootRequest'], 'unknown')
        marker.unlink()
        self.assertEqual(self.show()['currentRebootRequest'], 'absent')
        self.assertEqual((self.root / 'read/last-read').read_text(), '20260916T055719Z\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
