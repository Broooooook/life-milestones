/// 消費者物價指數（年平均，民國110年=100），行政院主計總處《物價統計月報》
const Map<int, double> cpiByYear = <int, double>{
  2001: 81.92, 2002: 81.76, 2003: 81.53, 2004: 82.84, 2005: 84.75,
  2006: 85.26, 2007: 86.79, 2008: 89.86, 2009: 89.07, 2010: 89.93,
  2011: 91.21, 2012: 92.97, 2013: 93.71, 2014: 94.83, 2015: 94.54,
  2016: 95.86, 2017: 96.45, 2018: 97.76, 2019: 98.30, 2020: 98.07,
  2021: 100.00, 2022: 102.95, 2023: 105.51, 2024: 107.81, 2025: 109.60,
};

/// 換算基準：最新公布的月指數
const double cpiNow = 112.90;
const String cpiNowLabel = '2026 年 10 月';

/// 當年的金額，用今天的物價換算；沒有資料或差不到 1% 時回傳 null
int? toTodayMoney(int amount, int year) {
  final c = cpiByYear[year];
  if (c == null || amount <= 0) return null;
  final v = amount * cpiNow / c;
  if ((v - amount).abs() / amount < 0.01) return null;
  return v.round();
}
