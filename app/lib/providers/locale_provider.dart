import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('th')) {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    try {
      final langCode = await StorageService().getLanguage();
      if (langCode != null) state = Locale(langCode);
    } catch (e) {
      // ใช้ค่าเริ่มต้น th
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    try {
      await StorageService().saveLanguage(locale.languageCode);
    } catch (e) {
      // ไม่เป็นไร
    }
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) => LocaleNotifier());
