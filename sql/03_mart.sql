-- Крок 1: дедуп in_app_events_report (за природним ключем — вже перевірено в DQ)
WITH iap_dedup AS (
  SELECT
    firebase_analytic_app_id,
    event_revenue_usd,
    ROW_NUMBER() OVER (
      PARTITION BY order_id, event_name, timestamp, CAST(event_revenue_usd AS STRING)
      ORDER BY order_id
    ) AS rn
  FROM `mornhouse-test-environment.test_app_dataset.in_app_events_report`
),

-- Крок 2: агрегуємо ad revenue по пристрою (firebase_analytic_app_id)
ad_revenue_agg AS (
  SELECT
    firebase_analytic_app_id,
    SUM(event_revenue_usd) AS total_ad_revenue
  FROM `mornhouse-test-environment.test_app_dataset.ad_revenue_raw`
  WHERE firebase_analytic_app_id IS NOT NULL
  GROUP BY firebase_analytic_app_id
),

-- Крок 3: агрегуємо iap/subscription revenue по пристрою (після дедупу)
iap_revenue_agg AS (
  SELECT
    firebase_analytic_app_id,
    SUM(event_revenue_usd) AS total_iap_revenue
  FROM iap_dedup
  WHERE rn = 1 AND firebase_analytic_app_id IS NOT NULL
  GROUP BY firebase_analytic_app_id
),

-- Крок 4: install-level — анкер це таблиця 1, доєднуємо revenue по пристрою (LEFT JOIN)
installs_with_revenue AS (
  SELECT
    i.campaign_id,
    i.media_source,
    i.firebase_analytic_app_id,
    COALESCE(ar.total_ad_revenue, 0) AS total_ad_revenue,
    COALESCE(ir.total_iap_revenue, 0) AS total_iap_revenue
  FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report` i
  LEFT JOIN ad_revenue_agg ar ON i.firebase_analytic_app_id = ar.firebase_analytic_app_id
  LEFT JOIN iap_revenue_agg ir ON i.firebase_analytic_app_id = ir.firebase_analytic_app_id
),

-- Крок 5: агрегуємо install-level до рівня кампанії
campaign_agg AS (
  SELECT
    campaign_id,
    media_source,
    COUNT(*) AS install_count,
    SUM(total_ad_revenue) AS total_ad_revenue,
    SUM(total_iap_revenue) AS total_iap_revenue
  FROM installs_with_revenue
  GROUP BY campaign_id, media_source
),

-- Крок 6: агрегуємо cost_table до рівня кампанії
cost_agg AS (
  SELECT
    campaign_id,
    media_source,
    SUM(cost_usd) AS total_cost_usd
  FROM `mornhouse-test-environment.test_app_dataset.cost_table`
  GROUP BY campaign_id, media_source
)

-- Крок 7 (оновлено): LEFT JOIN — лишаємо ВСІ 48 кампаній з cost_table
SELECT
  c.campaign_id,
  c.media_source,
  c.total_cost_usd,
  COALESCE(a.install_count, 0) AS install_count,
  ROUND(c.total_cost_usd / NULLIF(COALESCE(a.install_count, 0), 0), 4) AS cac,
  COALESCE(a.total_ad_revenue, 0) AS total_ad_revenue,
  COALESCE(a.total_iap_revenue, 0) AS total_iap_revenue,
  COALESCE(a.total_ad_revenue, 0) + COALESCE(a.total_iap_revenue, 0) AS total_revenue,
  (COALESCE(a.total_ad_revenue, 0) + COALESCE(a.total_iap_revenue, 0)) - c.total_cost_usd AS profit,
  ROUND(
    (COALESCE(a.total_ad_revenue, 0) + COALESCE(a.total_iap_revenue, 0)) / NULLIF(c.total_cost_usd, 0),
    4
  ) AS roas
FROM cost_agg c
LEFT JOIN campaign_agg a
  ON c.campaign_id = a.campaign_id AND c.media_source = a.media_source
ORDER BY profit DESC;