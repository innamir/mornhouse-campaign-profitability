-- ============================================================
-- 02_DATA_QUALITY — цілеспрямована перевірка надійності полів,
-- які підуть у розрахунок cost/revenue/profit.
-- Mornhouse: аналіз прибутковості рекламних кампаній
-- Виконується після завершення profiling усіх таблиць (01_profiling.sql).
-- ============================================================


-- ============================================================
-- Дублікати рядків: in_app_events_report
-- Інтерпретація — README.md, розділ 2.5
-- ============================================================

-- Крок 1: групування лише по order_id (первинна перевірка)
SELECT order_id, COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.in_app_events_report`
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 20;
-- Результат: сотні order_id з 4-5 рядками. Drill-down показав: це стадії життєвого
-- циклу підписки (renewed → grace → canceled → churned → refunded), НЕ дублікати.

-- Крок 2: точний natural key (order_id + event_name + timestamp + event_revenue_usd)
SELECT
  order_id, event_name, timestamp, event_revenue_usd,
  COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.in_app_events_report`
GROUP BY order_id, event_name, timestamp, event_revenue_usd
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 20;
-- Результат: справжні дублікати ІСНУЮТЬ, включно з revenue-bearing подіями
-- (subscription_refunded, subscription_renewed), повторені 2-4 рази.
-- ПІДТВЕРДЖЕНА проблема подвійного обліку доходу.

-- Крок 3: кількісна оцінка впливу дублікатів на суму доходу
WITH dup_groups AS (
  SELECT
    order_id, event_name, timestamp, event_revenue_usd,
    COUNT(*) AS cnt
  FROM `mornhouse-test-environment.test_app_dataset.in_app_events_report`
  GROUP BY order_id, event_name, timestamp, event_revenue_usd
  HAVING COUNT(*) > 1
)
SELECT
  COUNT(*) AS duplicate_groups,
  SUM(cnt) AS total_duplicate_rows,
  SUM(cnt - 1) AS excess_rows,
  SUM((cnt - 1) * event_revenue_usd) AS excess_revenue_impact
FROM dup_groups;
-- Результат: 36 груп, 74 рядки залучено, 38 зайвих, excess_revenue_impact = -$218.98.
-- Дублікати переважно серед subscription_refunded (від'ємні суми) — наївний SUM
-- занижує дохід на $218.98 (~0.4% від загального доходу таблиці, ~$56488).
-- ВИСНОВОК: дедуплікація ОБОВ'ЯЗКОВА перед SUM(event_revenue_usd) у фінальній вітрині.


-- ============================================================
-- Дублікати рядків: ad_revenue_raw
-- Інтерпретація — README.md, розділ 2.5
-- ============================================================

-- Точний natural key: firebase_analytic_app_id + timestamp + ad_unit_id + event_revenue_usd
-- (order_id тут немає — беремо підтверджений device-level ID + точний час + рекламний блок)
SELECT
  firebase_analytic_app_id,
  timestamp,
  ad_unit_id,
  event_revenue_usd,
  COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.ad_revenue_raw`
GROUP BY firebase_analytic_app_id, timestamp, ad_unit_id, event_revenue_usd
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 20;
-- Результат: величезні групи (до 37260 рядків) — виглядає катастрофічно за кількістю.

-- Кількісна оцінка впливу на дохід
WITH dup_groups AS (
  SELECT
    firebase_analytic_app_id, timestamp, ad_unit_id, event_revenue_usd,
    COUNT(*) AS cnt
  FROM `mornhouse-test-environment.test_app_dataset.ad_revenue_raw`
  GROUP BY firebase_analytic_app_id, timestamp, ad_unit_id, event_revenue_usd
  HAVING COUNT(*) > 1
)
SELECT
  COUNT(*) AS duplicate_groups,
  SUM(cnt) AS total_duplicate_rows,
  SUM(cnt - 1) AS excess_rows,
  SUM((cnt - 1) * event_revenue_usd) AS excess_revenue_impact
FROM dup_groups;
-- Результат: 288680 груп, 3763349 рядків залучено, 3474669 зайвих (58% таблиці!),
-- але excess_revenue_impact = лише $88.62.

-- Пояснення грубого ключа: чи справді ad_unit_id низькокардинальний
SELECT
  COUNT(DISTINCT ad_unit_id) AS distinct_ad_unit_ids,
  COUNTIF(event_revenue_usd IS NULL) AS null_revenue_rows,
  COUNT(*) AS total_rows,
  ROUND(COUNTIF(event_revenue_usd IS NULL) / COUNT(*) * 100, 1) AS null_revenue_pct
FROM `mornhouse-test-environment.test_app_dataset.ad_revenue_raw`;
-- Результат: лише 12 distinct ad_unit_id, 40.0% рядків без доходу (NULL).
-- ВИСНОВОК: ключ занадто грубий для цієї таблиці (низька кардинальність + масовий NULL
-- revenue), а не реальний ETL-дублікат. Дедуплікація НЕ ПОТРІБНА для розрахунку revenue —
-- фінансовий вплив мізерний.


-- ============================================================
-- Аномалії cost_usd та коректність конвертації валют: cost_table
-- Інтерпретація — README.md, розділ 2.5
-- ============================================================

-- Перевірка cost_usd на від'ємні/аномальні значення
SELECT
  MIN(cost_usd) AS min_cost_usd,
  MAX(cost_usd) AS max_cost_usd,
  COUNTIF(cost_usd < 0) AS negative_cost_rows,
  ROUND(AVG(cost_usd), 2) AS avg_cost_usd
FROM `mornhouse-test-environment.test_app_dataset.cost_table`;
-- Результат: min=0.0, max=8.82, negative_cost_rows=0, avg≈0.0 (очікувано через тонку
-- грануляцію campaign×adset×geo×day). Аномалій немає.

-- Чи є більше однієї валюти
SELECT
  cost_currency,
  COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.cost_table`
GROUP BY cost_currency;
-- Результат: EUR — 894763 (17%), USD — 4358661 (83%). Разом = row_count. Питання
-- конвертації реальне, не риторичне.

-- Коректність конвертації: співвідношення cost_usd / cost за валютою
SELECT
  cost_currency,
  ROUND(AVG(cost_usd / NULLIF(cost, 0)), 4) AS avg_conversion_rate,
  ROUND(MIN(cost_usd / NULLIF(cost, 0)), 4) AS min_conversion_rate,
  ROUND(MAX(cost_usd / NULLIF(cost, 0)), 4) AS max_conversion_rate
FROM `mornhouse-test-environment.test_app_dataset.cost_table`
GROUP BY cost_currency;
-- Результат: USD — рівно 1.0 (без конвертації, як і має бути). EUR — 1.1354-1.1648,
-- вузький реалістичний діапазон курсу EUR/USD.
-- ВИСНОВОК: конвертація стабільна й коректна. Перевірено, проблем не знайдено.


-- ============================================================
-- Свідомо поза межами обсягу тестового завдання
-- ============================================================
-- Логічна узгодженість дат (event_date >= install_date) — вимагає дорогого
-- device-level JOIN, не потрібного для campaign-level вітрини.