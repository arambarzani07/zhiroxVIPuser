import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/widgets/zhirox_shell.dart';

class _ShellHost extends StatefulWidget {
  const _ShellHost();

  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ZhiroxAppShell(
        index: index,
        showConnectivity: false,
        pages: const [
          Center(child: Text('home-page')),
          Center(child: Text('customers-page')),
          Center(child: Text('more-page')),
        ],
        destinations: const [
          ZhiroxDestination(
            label: 'سەرەکی',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
          ),
          ZhiroxDestination(
            label: 'کڕیار',
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
          ),
          ZhiroxDestination(
            label: 'زیاتر',
            icon: Icons.grid_view_outlined,
            selectedIcon: Icons.grid_view,
            badgeCount: 4,
          ),
        ],
        onSelected: (value) => setState(() => index = value),
      ),
    );
  }
}

void main() {
  testWidgets('unified shell switches pages and preserves Kurdish labels',
      (tester) async {
    await tester.pumpWidget(const _ShellHost());

    expect(find.text('home-page'), findsOneWidget);
    expect(find.text('سەرەکی'), findsOneWidget);
    expect(find.text('کڕیار'), findsOneWidget);
    expect(find.text('زیاتر'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.text('کڕیار'));
    await tester.pumpAndSettle();

    expect(find.text('customers-page'), findsOneWidget);
    expect(find.text('home-page'), findsNothing);
  });
}
