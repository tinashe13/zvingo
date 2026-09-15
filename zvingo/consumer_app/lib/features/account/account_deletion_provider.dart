import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/order/orders_screen.dart'
    show consumerOrdersProvider;

part 'account_deletion_provider.g.dart';

/// What happened when the customer asked for their account to be deleted.
enum AccountDeletionOutcome {
  /// The server accepted and actioned the request.
  deleted,

  /// **The route is not deployed on this server.** Google Play requires
  /// in-app account deletion (finding X4) and no backend route exists yet —
  /// see the endpoint specification in the C4 report. The UI must say so
  /// plainly and offer the manual route rather than pretending it worked.
  endpointMissing,

  /// The session expired mid-request; the user must sign in again.
  needsReauth,

  /// Anything else: offline, 5xx, a server-side refusal.
  failed,
}

class AccountDeletionResult {
  const AccountDeletionResult(this.outcome, {this.message});

  final AccountDeletionOutcome outcome;

  /// Server-supplied detail when there is one, already plain language.
  final String? message;

  bool get succeeded => outcome == AccountDeletionOutcome.deleted;
}

/// Order states that mean food (or money) is still moving.
///
/// Mirrors `backend/app/order/state_machine.py`: everything except `DELIVERED`
/// and `CANCELLED` is in flight.
const Set<String> _terminalOrderStates = {'DELIVERED', 'CANCELLED'};

/// Orders that would be abandoned by deleting the account right now.
///
/// Deleting mid-delivery would strand a driver and an unrefunded payment, so
/// the UI blocks on this instead of finding out server-side.
@riverpod
Future<int> inFlightOrderCount(Ref ref) async {
  final orders = await ref.watch(consumerOrdersProvider.future);
  return orders.where((order) {
    final state = (order['state'] ?? '').toString().toUpperCase();
    return state.isNotEmpty && !_terminalOrderStates.contains(state);
  }).length;
}

/// Sends the deletion request.
///
/// **Contract this expects** (not yet implemented server-side):
/// `DELETE /auth/me` with `{"reason": "<optional free text>"}`, authenticated
/// as the account being deleted, answering `204` on success.
@riverpod
class AccountDeletion extends _$AccountDeletion {
  @override
  FutureOr<void> build() {}

  Future<AccountDeletionResult> submit({String? reason}) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(apiClientProvider).delete<dynamic>(
            '/auth/me',
            data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
          );
      state = const AsyncValue.data(null);
      return const AccountDeletionResult(AccountDeletionOutcome.deleted);
    } on DioException catch (error, stack) {
      state = AsyncValue.error(error, stack);
      final status = error.response?.statusCode;
      // 404 (no such route) and 405 (route exists for other verbs only) both
      // mean the same thing to a customer: this server cannot do it yet.
      if (status == 404 || status == 405 || status == 501) {
        return const AccountDeletionResult(
          AccountDeletionOutcome.endpointMissing,
        );
      }
      if (status == 401 || status == 403) {
        return const AccountDeletionResult(
          AccountDeletionOutcome.needsReauth,
        );
      }
      return AccountDeletionResult(
        AccountDeletionOutcome.failed,
        message: _detail(error.response?.data),
      );
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
      return const AccountDeletionResult(AccountDeletionOutcome.failed);
    }
  }

  static String? _detail(Object? data) {
    if (data is Map && data['detail'] is String) {
      final detail = data['detail'] as String;
      return detail.isEmpty ? null : detail;
    }
    return null;
  }
}
