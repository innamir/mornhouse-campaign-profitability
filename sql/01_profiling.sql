-- ============================================================
-- 01_PROFILING — базовий аудит вихідних даних (data profiling)
-- Mornhouse: аналіз прибутковості рекламних кампаній
-- ============================================================


-- ============================================================
-- non_org_installs_report
-- Інтерпретація — README.md, розділ 2.1
-- ============================================================

-- 1. Базові метрики: діапазон дат, обсяг, кампанії, джерела трафіку
SELECT
  MIN(install_date) AS min_install_date,
  MAX(install_date) AS max_install_date,
  COUNT(*) AS row_count,
  COUNT(DISTINCT campaign_id) AS distinct_campaigns,
  COUNT(DISTINCT media_source) AS distinct_media_sources
FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`;
-- Результат: 2026-06-01 – 2026-07-26, 777724 рядки, 54 кампанії, 3 media_source.

-- 2. Аудит кандидатів на join-ключ
SELECT
  COUNT(*) AS row_count,
  COUNTIF(analytics_installation_id IS NOT NULL) AS analytics_installation_id_non_null,
  COUNT(DISTINCT analytics_installation_id) AS analytics_installation_id_distinct,
  COUNTIF(advertising_id IS NOT NULL) AS advertising_id_non_null,
  COUNT(DISTINCT advertising_id) AS advertising_id_distinct,
  COUNTIF(firebase_analytic_app_id IS NOT NULL) AS firebase_app_id_non_null,
  COUNT(DISTINCT firebase_analytic_app_id) AS firebase_app_id_distinct,
  COUNTIF(appsflyer_id IS NOT NULL) AS appsflyer_id_non_null,
  COUNT(DISTINCT appsflyer_id) AS appsflyer_id_distinct
FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`;
-- Результат: analytics_installation_id і appsflyer_id — 100% NULL.
-- advertising_id — 63% заповнено. firebase_analytic_app_id — 100% заповнено, унікальний
-- на рядок. Найсильніший кандидат на join-ключ рівня пристрою.


-- ============================================================
-- cost_table
-- Інтерпретація — README.md, розділ 2.2
-- ============================================================

-- 1. Базові метрики + якість campaign_id/media_source
SELECT
  MIN(date) AS min_date,
  MAX(date) AS max_date,
  COUNT(*) AS row_count,
  COUNT(DISTINCT app_id) AS distinct_apps,
  COUNT(DISTINCT campaign_id) AS distinct_campaigns,
  COUNT(DISTINCT media_source) AS distinct_media_sources,
  COUNTIF(campaign_id IS NULL) AS null_campaign_id,
  COUNTIF(media_source IS NULL) AS null_media_source
FROM `mornhouse-test-environment.test_app_dataset.cost_table`;
-- Результат: 2026-06-01 – 2026-07-26 (збігається з installs), 5253424 рядки, 1 app,
-- 48 кампаній (installs: 54), 1 media_source (installs: 3), NULL відсутні.

-- 2. Звірка значень media_source між cost_table і non_org_installs_report
SELECT 'cost_table' AS source_table, media_source, COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.cost_table`
GROUP BY media_source
UNION ALL
SELECT 'non_org_installs_report' AS source_table, media_source, COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`
GROUP BY media_source
ORDER BY source_table, media_source;
-- Результат: cost_table покриває лише googleadwords_int. non_org_installs_report має ще
-- other (95528) і unknown (266054) — ймовірно службові категорії атрибуції, не платні мережі.


-- ============================================================
-- ad_revenue_raw
-- Інтерпретація — README.md, розділ 2.3
-- ============================================================

SELECT
  MIN(event_date) AS min_event_date,
  MAX(event_date) AS max_event_date,
  COUNT(*) AS row_count,
  COUNT(DISTINCT app_id) AS distinct_apps,
  COUNT(DISTINCT campaign_id) AS distinct_campaigns,
  COUNT(DISTINCT media_source) AS distinct_media_sources,
  COUNTIF(campaign_id IS NULL) AS null_campaign_id,
  COUNT(DISTINCT analytics_installation_id) AS distinct_analytics_installation_id,
  COUNTIF(analytics_installation_id IS NULL) AS null_analytics_installation_id,
  COUNT(DISTINCT firebase_analytic_app_id) AS distinct_firebase_analytic_app_id,
  COUNTIF(firebase_analytic_app_id IS NULL) AS null_firebase_analytic_app_id,
  COUNT(DISTINCT advertising_id) AS distinct_advertising_id,
  COUNTIF(advertising_id IS NULL) AS null_advertising_id,
  COUNT(DISTINCT appsflyer_id) AS distinct_appsflyer_id,
  COUNTIF(appsflyer_id IS NULL) AS null_appsflyer_id
FROM `mornhouse-test-environment.test_app_dataset.ad_revenue_raw`;

-- Результат: 2026-06-01 – 2026-07-26, 5955170 рядків, 1 app, 137 кампаній (!),
-- 3 media_source, 5.9% NULL campaign_id. analytics_installation_id і appsflyer_id — NULL.
-- firebase_analytic_app_id: 268249 distinct, 0 NULL (~22 події на пристрій — узгоджено
-- з installs). advertising_id: 242204 distinct, 6.3% NULL.
-- ВАЖЛИВО: 137 кампаній > 54 (installs) і 48 (cost) — сигнал можливого змішування когорт
-- різної зрілості (дохід від installs до початку періоду). Див. Hypothesis Log.


-- ============================================================
-- in_app_events_report
-- Інтерпретація — README.md, розділ 2.4
-- (TODO — наступний крок)
-- ============================================================