from pathlib import Path

ROOT = Path.cwd()
profile_path = ROOT / 'lib/screens/shared/user_profile_screen.dart'
verifier_path = ROOT / 'scripts/verify_online_only.py'

profile = profile_path.read_text(encoding='utf-8')
verifier = verifier_path.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)

if 'Timer? _financialSearchDebounce;' not in profile:
    profile = replace_once(
        profile,
        '  Timer? _financialRealtimeDebounce;\n',
        '  Timer? _financialRealtimeDebounce;\n  Timer? _financialSearchDebounce;\n',
        'search debounce field',
    )

if '''  @override\n  void dispose() {\n    _financialRealtimeDebounce?.cancel();\n    _financialSearchDebounce?.cancel();\n''' not in profile:
    profile = replace_once(
        profile,
        '''  @override\n  void dispose() {\n    _financialRealtimeDebounce?.cancel();\n''',
        '''  @override\n  void dispose() {\n    _financialRealtimeDebounce?.cancel();\n    _financialSearchDebounce?.cancel();\n''',
        'search debounce dispose',
    )

hydrate_marker = '''  Future<void> _hydrateFinancialHistoryForFilters() async {\n'''
schedule_method = '''  void _scheduleFinancialSearchHydration() {\n    _financialSearchDebounce?.cancel();\n    if (!mounted || !_hasFinancialFilters || !_financialTimelineHasMore) return;\n    _financialSearchDebounce = Timer(const Duration(milliseconds: 350), () {\n      if (!mounted) return;\n      unawaited(_hydrateFinancialHistoryForFilters());\n    });\n  }\n\n'''
if schedule_method not in profile:
    profile = replace_once(
        profile,
        hydrate_marker,
        schedule_method + hydrate_marker,
        'insert search hydration scheduler',
    )

old_on_changed = '''          onChanged: (_) {\n            setState(() {});\n            unawaited(_hydrateFinancialHistoryForFilters());\n          },\n'''
new_on_changed = '''          onChanged: (_) {\n            setState(() {});\n            _scheduleFinancialSearchHydration();\n          },\n'''
if new_on_changed not in profile:
    profile = replace_once(
        profile,
        old_on_changed,
        new_on_changed,
        'debounce search onChanged',
    )

old_clear_filters = '''    _financialSearchController.clear();\n    setState(() {\n      _financialDateRange = null;\n'''
new_clear_filters = '''    _financialSearchDebounce?.cancel();\n    _financialSearchController.clear();\n    setState(() {\n      _financialDateRange = null;\n'''
if new_clear_filters not in profile:
    profile = replace_once(
        profile,
        old_clear_filters,
        new_clear_filters,
        'cancel debounce when clearing filters',
    )

old_clear_search = '''                    onPressed: () {\n                      _financialSearchController.clear();\n                      setState(() {});\n                    },\n'''
new_clear_search = '''                    onPressed: () {\n                      _financialSearchDebounce?.cancel();\n                      _financialSearchController.clear();\n                      setState(() {});\n                    },\n'''
if new_clear_search not in profile:
    profile = replace_once(
        profile,
        old_clear_search,
        new_clear_search,
        'cancel debounce when clearing search',
    )

anchor = '''if '_buildFinancialChatMessages(' in profile:\n    fail('lib/screens/shared/user_profile_screen.dart: eager Financial Chat message widget list must not return')\n\n\n'''
guard = '''# Text search must debounce full-history hydration so typing does not start\n# an expensive page walk on the first keypress. Existing filter hydration is\n# single-flight; this guard keeps the text entry path debounced as well.\nfor marker in (\n    'Timer? _financialSearchDebounce;',\n    '_scheduleFinancialSearchHydration',\n    'Duration(milliseconds: 350)',\n    '_financialSearchDebounce?.cancel();',\n):\n    if marker not in profile:\n        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat search debounce marker missing: {marker}')\nif \"\"\"onChanged: (_) {\n            setState(() {});\n            unawaited(_hydrateFinancialHistoryForFilters());\n          },\"\"\" in profile:\n    fail('lib/screens/shared/user_profile_screen.dart: text search must not hydrate full history on every keypress')\n\n\n'''
if guard not in verifier:
    verifier = replace_once(
        verifier,
        anchor,
        anchor + guard,
        'insert search debounce verifier',
    )

profile_path.write_text(profile, encoding='utf-8')
verifier_path.write_text(verifier, encoding='utf-8')
print('Financial Chat search debounce patch applied.')
