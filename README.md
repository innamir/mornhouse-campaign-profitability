# Mornhouse — аналіз прибутковості рекламних кампаній
## Робочий журнал аналізу (methodology log)

> Правило ведення цього журналу: гіпотеза фіксується ДО запуску запиту, висновок — одразу ПІСЛЯ. Не переписувати заднім числом.

---

## 1. Контекст і бізнес-питання

- **Мета:** побудувати єдину вітрину, яка показує прибутковість рекламних кампаній Mornhouse (cost vs revenue), і на її основі — дашборд у Tableau.
- **Що вважаємо "прибутковою кампанією":** визначення метрики буде зафіксовано в розділі 6, коли стане зрозуміло, які дані реально доступні для розрахунку доходу.
- **Джерела:** BigQuery, проєкт `mornhouse-test-environment`, датасет `test_app_dataset`, доступ viewer.
- **Обмеження середовища:** sandbox-режим без білінгу → ліміт на обсяг сканованих даних. Уникаємо `SELECT *` на великих таблицях, спершу перевіряємо обсяг агрегатними запитами.
- **Заявлений період даних:** червень–липень 2026 (буде звірено з фактичними даними в кожній таблиці).

---

## 2. Аудит вихідних даних (Data Profiling)

Мета етапу: зрозуміти grain, обсяг, діапазон дат і якість потенційних ключів кожної таблиці окремо, до будь-яких JOIN.

### 2.1 non_org_installs_report

**Query:** `sql/01_profiling.sql`
### 2.1 non_org_installs_report

| min_install_date | max_install_date | row_count | distinct_campaigns | distinct_media_sources |
|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 777724 | 54 | 3 |

**Query 2 — аудит кандидатів на join-ключ:**
| row_count | analytics_installation_id_non_null | analytics_installation_id_distinct | advertising_id_non_null | advertising_id_distinct | firebase_app_id_non_null | firebase_app_id_distinct | appsflyer_id_non_null | appsflyer_id_distinct |
|---|---|---|---|---|---|---|---|---|
| 777724 | 0 | 0 | 489544 | 473477 | 777724 | 777724 | 0 | 0 |

**Висновок:**
- Grain таблиці: одна подія атрибутованого інсталу.
- Діапазон дат (2026-06-01 – 2026-07-26) узгоджений з іншими таблицями (див. 2.2).
- `analytics_installation_id` і `appsflyer_id` — повністю NULL, непридатні як join-ключ, попри те, що останній зазвичай головний ключ AppsFlyer-даних.
- `advertising_id` — заповнений на 63%, робочий, але з відчутною втратою.
- **`firebase_analytic_app_id` — 100% заповнений, унікальний на рядок. Найсильніший кандидат на join-ключ рівня пристрою.** Узгоджується з поведінкою того ж поля в ad_revenue_raw (~22 повтори на значення). Реальний value-level overlap між таблицями — перевірити в Join Key Mapping.
- 54 кампанії, 3 media_source — орієнтир для звірки з cost_table (розбіжність 48 vs 54, див. 2.2).

**Гіпотези, що виникли:** див. розділ 3, пункти №1 (оновлено), №5 (новий).

### 2.2 cost_table

**Query:** `sql/01_profiling.sql`

```sql
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
```

**Результат (базові метрики):**
| min_date | max_date | row_count | distinct_apps | distinct_campaigns | distinct_media_sources | null_campaign_id | null_media_source |
|---|---|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 5253424 | 1 | 48 | 1 | 0 | 0 |

```sql
SELECT 'cost_table' AS source_table, media_source, COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.cost_table`
GROUP BY media_source

UNION ALL

SELECT 'non_org_installs_report' AS source_table, media_source, COUNT(*) AS row_count
FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`
GROUP BY media_source

ORDER BY source_table, media_source;
```
**Результат (звірка media_source з non_org_installs_report):**
| source_table | media_source | row_count |
|---|---|---|
| cost_table | googleadwords_int | 5253424 |
| non_org_installs_report | googleadwords_int | 416142 |
| non_org_installs_report | other | 95528 |
| non_org_installs_report | unknown | 266054 |

**Висновок:**
- Діапазон дат повністю збігається з non_org_installs_report — довіряємо заявленому періоду (2026-06-01 – 2026-07-26).
- row_count значно більший за installs (5.25 млн vs 777 тис.) — очікувано: grain тут campaign × adset × geo × day, а не одна подія інсталу.
- distinct_campaigns = 48 vs 54 в installs — розбіжність 6 кампаній, причина ще не з'ясована.
- distinct_media_sources = 1 vs 3 в installs — критична розбіжність. cost_table покриває лише `googleadwords_int`. `other` і `unknown` в installs, імовірно, не реальні платні мережі, а службові категорії атрибуції (гіпотеза).
- `campaign_id` і `media_source` структурно чисті (без NULL) в cost_table.

**Гіпотези, що виникли:** див. розділ 3, пункти №3, №4.

### 2.3 ad_revenue_raw
### 2.3 ad_revenue_raw

**Query:** `sql/01_profiling.sql` — секція `ad_revenue_raw`

**Результат:**
| min_event_date | max_event_date | row_count | distinct_apps | distinct_campaigns | distinct_media_sources | null_campaign_id |
|---|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 5955170 | 1 | 137 | 3 | 351694 |

| distinct_analytics_installation_id | null_analytics_installation_id | distinct_firebase_app_id | null_firebase_app_id | distinct_advertising_id | null_advertising_id | distinct_appsflyer_id | null_appsflyer_id |
|---|---|---|---|---|---|---|---|
| 0 | 5955170 | 268249 | 0 | 242204 | 377612 | 0 | 5955170 |

**Висновок:**
- Діапазон дат збігається з іншими таблицями (2026-06-01 – 2026-07-26).
- Grain: одна подія показу/завершення реклами — звідси набагато більший обсяг (5.95 млн), ніж у installs (777 тис.): один пристрій генерує багато рекламних подій за період.
- `null_campaign_id = 351694` (~5.9%) — на відміну від installs і cost_table, тут є NULL. Частина подій доходу не атрибутована до жодної кампанії; ці рядки випадуть з campaign-level вітрини при INNER JOIN, якщо не обробити явно.
- **`distinct_campaigns = 137`**, що більше за 54 (installs) і 48 (cost_table). Гіпотеза: `event_date` — дата події доходу, а не інсталу, тому дохід у червні-липні можуть генерувати користувачі, які встановили застосунок ще до початку періоду даних (1 червня) через кампанії, відсутні в installs/cost за цей проміжок. Це потенційна пастка "порівняння когорт різної зрілості" — критично для розділу 6 (Metric Definitions).
- Кандидати на join-ключ: `analytics_installation_id` і `appsflyer_id` — 100% NULL (узгоджено з non_org_installs_report). `advertising_id` — 242204 distinct, 6.3% NULL. **`firebase_analytic_app_id` — 268249 distinct, 0% NULL**, узгоджується з поведінкою цього поля в installs (~22 події на пристрій у середньому) — підтверджує гіпотезу №5.

**Гіпотези, що виникли:** див. розділ 3, пункти №5 (додатково підтверджено), №6 (новий).

### 2.4 in_app_events_report
*(TODO)*

## 2.5 Перевірка якості даних (Data Quality Checks)

На відміну від профайлінгу (2.1–2.4), який досліджує структуру кожної таблиці окремо,
цей розділ — цілеспрямована перевірка надійності конкретних полів, які підуть у розрахунок
cost/revenue/profit у фінальній вітрині. Виконується після завершення profiling усіх таблиць.

Перелік перевірок (для ad_revenue_raw, in_app_events_report, cost_table):

- **Дублікати рядків** — чи не задвоюються події доходу (напр. через повторну відправку SDK)?
  Класична пастка: подвійний облік доходу через дублікати в revenue-таблицях.
- **Від'ємні/нульові/аномальні значення** — cost_usd, event_revenue_usd < 0 чи екстремальні.
- **Логічна узгодженість дат** — чи event_date/timestamp завжди >= install_date.
- **Повнота ключів з'єднання** — NULL-rate campaign_id/media_source саме в revenue-таблицях.
- **Коректність конвертації валют** — чи cost/cost_usd співвідношення адекватне.

*(Результати — заповнити по мірі виконання)*
---

## 3. Журнал гіпотез (Hypothesis Log)

| # | Гіпотеза | Як перевірено | Результат | Статус |
|---|---|---|---|---|
| 1 | `analytics_installation_id` — Firebase Analytics ID, не завжди проставляється в момент інсталу, тому NULL структурно | Перевірено NULL-rate на non_org_installs_report і ad_revenue_raw | 100% NULL в обох таблицях (777724/777724 та 5955170/5955170) | емпірично підтверджено (поле системно порожнє); причина (SDK timing) — припущення, документально не підтверджена. Перевірити ще в in_app_events_report |
| 2 | Вітрина будується на рівні grain = campaign (+ media_source, + date), а не на рівні окремого користувача | Логічний висновок з формулювання задачі ("які кампанії прибуткові") | — | робоче припущення, переглянути якщо знадобиться LTV/cohort розріз |
| 3 | campaign_id в cost_table і non_org_installs_report — різні системи нумерації (ad network ID vs attribution ID) | Порівняно кількість distinct: 48 (cost) vs 54 (installs) | Числа близькі, але не рівні — точний overlap множин значень ще не перевірено запитом | частково перевірено — потрібен прямий overlap-запит у Join Key Mapping |
| 4 | media_source = "other"/"unknown" в non_org_installs_report — службові категорії атрибуції, а не реальні платні мережі з відсутнім cost-трекінгом | Перевірити campaign_id/інші поля у рядків з цими значеннями media_source | — | потребує перевірки |
| 5 | `firebase_analytic_app_id` — стабільний device-level ідентифікатор, придатний як join-ключ між installs і revenue-таблицями | Перевірено заповненість і кардинальність на non_org_installs_report і ad_revenue_raw | 100% заповнено в обох; унікальний на рядок в installs (777724/777724), ~22 повтори на значення в ad_revenue_raw (268249 distinct / 5955170 рядків) — узгоджена поведінка device ID | сильно підтверджено за формою; реальний value-level overlap між таблицями ще не перевірено (Join Key Mapping) |
| 6 | distinct_campaigns у ad_revenue_raw (137) перевищує installs (54) і cost_table (48) через дохід від installs, здійснених до початку періоду даних (до 2026-06-01) | Логічний висновок з різниці показників; прямий запит (install_date для campaign_id, наявних лише в ad_revenue_raw) ще не виконано | — | потребує перевірки |
---

## 4. Ключі з'єднання (Join Key Mapping)

*(заповнити після завершення профілювання всіх 4 таблиць)*

- Обраний grain фінальної вітрини:
- Ключ(і) з'єднання cost_table ↔ revenue-таблиці:
- Обґрунтування вибору:
- Що робимо з рядками, які не знайшли пари (unmatched cost / unmatched revenue):

---

## 5. Виявлені проблеми даних (Data Issues Log)

| Таблиця | Поле | Проблема | Вплив на аналіз | Рішення |
|---|---|---|---|---|
| non_org_installs_report | analytics_installation_id | 100% NULL (777724/777724) | Не можна використовувати як ключ для user-level join | Використати campaign_id/media_source як ключ на рівні агрегату (див. гіпотезу №2) |
| cost_table | media_source | Покриває лише 1 з 3 джерел, наявних в non_org_installs_report (тільки googleadwords_int) | Неможливо порахувати cost/profitability для installs з media_source = other/unknown без додаткового уточнення природи цих категорій | Дослідити campaign_id у рядків other/unknown; можливо, виключити їх з periметру paid-кампаній аналізу |
| ad_revenue_raw | campaign_id | ~5.9% NULL (351694/5955170) | Ці події доходу не атрибутуються до жодної кампанії, випадуть з campaign-level вітрини при INNER JOIN | Явно виключити або показати окремим рядком "unattributed revenue" в фінальній вітрині |

---

## 6. Визначення метрик (Metric Definitions)

*(заповнити, коли зрозуміло, які джерела доходу доступні і як вони рахуються)*

- **Cost** =
- **Revenue** (ad revenue + in-app purchases) =
- **Profit** =
- **ROAS** =
- Інші метрики (CPI, ARPU тощо):

---

## 7. Фінальна схема вітрини (Mart Schema)

*(заповнити після побудови)*

| Поле | Тип | Опис |
|---|---|---|
| | | |

---

## 8. Журнал запитів (SQL Query Log)

Хронологічний список усіх значущих запитів із коротким коментарем навіщо він і що показав.

1. **Профілювання non_org_installs_report (grain, дати, обсяг, кандидати на ключ)** — див. 2.1
2. **Перевірка NULL-rate analytics_installation_id** — див. 2.1.

3. **Профілювання cost_table (grain, дати, обсяг, NULL-rate campaign_id/media_source)** — див. 2.2.
4. **Звірка значень media_source між cost_table і non_org_installs_report** — див. 2.2.
6. **Профілювання ad_revenue_raw (grain, дати, обсяг, кандидати на ключ)** — див. 2.3.

---

## 9. Дашборд у Tableau

*(заповнити на етапі побудови дашборду)*

- Візуалізація 1: ... — навіщо
- Візуалізація 2: ... — навіщо
- Візуалізація 3: ... — навіщо

---

## 10. Висновки і рекомендації

*(заповнити в кінці)*