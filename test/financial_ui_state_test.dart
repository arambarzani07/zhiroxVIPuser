import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/financial_ui_state.dart';

void main() {
  group('financial filter disclosure', () {
    test('counts only active filter dimensions', () {
      expect(
        countActiveFinancialFilters(
          query: '',
          hasDateRange: false,
          typeFilter: 'all',
        ),
        0,
      );
      expect(
        countActiveFinancialFilters(
          query: '10000',
          hasDateRange: true,
          typeFilter: 'payment',
        ),
        3,
      );
    });

    test('active filters keep the compact panel exposed', () {
      expect(
        shouldExpandFinancialFilters(
          requestedExpanded: false,
          activeFilterCount: 2,
        ),
        isTrue,
      );
      expect(
        shouldExpandFinancialFilters(
          requestedExpanded: false,
          activeFilterCount: 0,
        ),
        isFalse,
      );
      expect(
        shouldExpandFinancialFilters(
          requestedExpanded: true,
          activeFilterCount: 0,
        ),
        isTrue,
      );
    });
  });

  group('payment flow presentation', () {
    test('progresses target to amount to review without extra dialog', () {
      expect(
        resolveFinancialPaymentStep(
          targetSelected: false,
          amount: 0,
          maximum: 10000,
          reviewRequested: false,
        ),
        FinancialPaymentStep.target,
      );
      expect(
        resolveFinancialPaymentStep(
          targetSelected: true,
          amount: 0,
          maximum: 10000,
          reviewRequested: false,
        ),
        FinancialPaymentStep.amount,
      );
      expect(
        resolveFinancialPaymentStep(
          targetSelected: true,
          amount: 5000,
          maximum: 10000,
          reviewRequested: true,
        ),
        FinancialPaymentStep.review,
      );
    });

    test('invalid amount never advances to review', () {
      expect(
        resolveFinancialPaymentStep(
          targetSelected: true,
          amount: 12000,
          maximum: 10000,
          reviewRequested: true,
        ),
        FinancialPaymentStep.amount,
      );
    });
  });
}
