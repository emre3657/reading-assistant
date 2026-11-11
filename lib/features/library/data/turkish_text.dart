String normalizeTurkishCase(String value) =>
    value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
