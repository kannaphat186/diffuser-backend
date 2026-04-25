// lib/providers/customer_provider.dart — with cache (60 วิ)
//
// v5.1 fixes:
//   1. Do NOT call loadCustomers() from the constructor. The provider is
//      instantiated before the user logs in, so the initial /api/customers
//      request was hitting the backend with no Authorization header and
//      landing a 401. That 401 then polluted `state.error` and was surfaced
//      to later UI code that tried to read it. The home screen + customers
//      screen now call refresh() themselves after login.
//   2. copyWith({String? error, bool clearError=false}) — the previous
//      copyWith always wrote `error: error` which silently cleared the
//      error on every unrelated state update. Now callers must explicitly
//      opt into clearing.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/customer_model.dart';
import '../services/customer_service.dart';

class CustomerState {
  final bool isLoading;
  final List<CustomerModel> customers;
  final String? error;
  final DateTime? lastFetched;

  CustomerState({
    this.isLoading = false,
    this.customers = const [],
    this.error,
    this.lastFetched,
  });

  CustomerState copyWith({
    bool? isLoading,
    List<CustomerModel>? customers,
    String? error,
    DateTime? lastFetched,
    bool clearError = false,
  }) {
    return CustomerState(
      isLoading: isLoading ?? this.isLoading,
      customers: customers ?? this.customers,
      error: clearError ? null : (error ?? this.error),
      lastFetched: lastFetched ?? this.lastFetched,
    );
  }

  bool get isCacheValid {
    if (lastFetched == null || customers.isEmpty) return false;
    return DateTime.now().difference(lastFetched!) < const Duration(seconds: 60);
  }
}

class CustomerNotifier extends StateNotifier<CustomerState> {
  final CustomerService _customerService;

  // Constructor intentionally does NOT auto-load. main.dart listens to
  // authProvider and triggers loads after the user actually signs in.
  CustomerNotifier(this._customerService) : super(CustomerState());

  Future<void> loadCustomers({bool skipCache = false}) async {
    if (!skipCache && state.isCacheValid) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final customers = await _customerService.getCustomers();
      state = state.copyWith(
        isLoading: false,
        customers: customers,
        lastFetched: DateTime.now(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => loadCustomers(skipCache: true);

  Future<CustomerModel> createCustomer({
    required String name,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
    String? address,
    int? packageQty,
    String? notes,
  }) async {
    try {
      final newCustomer = await _customerService.createCustomer(
        name: name,
        contactName: contactName,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        address: address,
        packageQty: packageQty,
        notes: notes,
      );
      state = state.copyWith(
        customers: [newCustomer, ...state.customers],
        lastFetched: DateTime.now(),
        clearError: true,
      );
      return newCustomer;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateCustomer(
    String id, {
    String? name,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
    String? address,
    int? packageQty,
    String? notes,
  }) async {
    try {
      final updated = await _customerService.updateCustomer(
        id,
        name: name,
        contactName: contactName,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        address: address,
        packageQty: packageQty,
        notes: notes,
      );
      final updatedList =
          state.customers.map((c) => c.id == id ? updated : c).toList();
      state = state.copyWith(customers: updatedList, clearError: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      await _customerService.deleteCustomer(id);
      final updatedList = state.customers.where((c) => c.id != id).toList();
      state = state.copyWith(customers: updatedList, clearError: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  void clearState() {
    state = CustomerState();
  }
}

final customerServiceProvider = Provider((ref) => CustomerService());

final customerProvider =
    StateNotifierProvider<CustomerNotifier, CustomerState>((ref) {
  return CustomerNotifier(ref.watch(customerServiceProvider));
});
