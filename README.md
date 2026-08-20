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

**Query:**
```sql
SELECT
  MIN(install_date) AS min_install_date,
  MAX(install_date) AS max_install_date,
  COUNT(*) AS row_count,
  COUNT(DISTINCT analytics_installation_id) AS distinct_installations,
  COUNT(DISTINCT campaign_id) AS distinct_campaigns,
  COUNT(DISTINCT media_source) AS distinct_media_sources
FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`;
```

**Результат:**
| min_install_date | max_install_date | row_count | distinct_installations | distinct_campaigns | distinct_media_sources |
|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 777724 | 0 | 54 | 3 |

**Follow-up query (перевірка підозрілого нуля):**
```sql
SELECT
  COUNT(*) AS row_count,
  COUNTIF(analytics_installation_id IS NULL) AS null_installations,
  COUNTIF(analytics_installation_id IS NOT NULL) AS non_null_installations
FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`;
```
**Результат:** 777724 / 777724 null / 0 non-null.

**Висновок:**
- Grain таблиці: одна подія атрибутованого інсталу.
- Реальний діапазон дат (2026-06-01 – 2026-07-26) не покриває весь заявлений період (до кінця липня) — зафіксувати, перевірити на інших таблицях.
- `analytics_installation_id` повністю NULL → непридатне як ключ з'єднання з цієї таблиці.
- 54 кампанії, 3 media_source — це орієнтовний "всесвіт" кампаній для звірки з cost_table.

**Гіпотези, що виникли:** див. розділ 3.

### 2.2 cost_table

**Query:** `sql/01_profiling.sql`

**Результат (базові метрики):**
| min_date | max_date | row_count | distinct_apps | distinct_campaigns | distinct_media_sources | null_campaign_id | null_media_source |
|---|---|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 5253424 | 1 | 48 | 1 | 0 | 0 |

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
*(TODO)*

### 2.4 in_app_events_report
*(TODO)*

---

## 3. Журнал гіпотез (Hypothesis Log)

| # | Гіпотеза | Як перевірено | Результат | Статус |
|---|---|---|---|---|
| 1 | `analytics_installation_id` — Firebase Analytics ID, не завжди проставляється в момент інсталу, тому може бути NULL структурно | Перевірка на ad_revenue_raw / in_app_events_report (чи там теж NULL) | — | потребує перевірки |
| 2 | Вітрина будується на рівні grain = campaign (+ media_source, + date), а не на рівні окремого користувача | Логічний висновок з формулювання задачі ("які кампанії прибуткові") | — | робоче припущення, переглянути якщо знадобиться LTV/cohort розріз |
| 3 | campaign_id в cost_table і non_org_installs_report — різні системи нумерації | Порівняно кількість: 48 vs 54 | Числа близькі, але не рівні — точний overlap множин ще не перевірено | частково перевірено |
| 4 | media_source = "other"/"unknown" в non_org_installs_report — це службові категорії атрибуції (не справжні платні мережі з окремим cost-трекінгом), а не відсутні cost-дані по реальних джерелах | Перевірити campaign_id у рядків з цими значеннями media_source | — | потребує перевірки |
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

---

## 9. Дашборд у Tableau

*(заповнити на етапі побудови дашборду)*

- Візуалізація 1: ... — навіщо
- Візуалізація 2: ... — навіщо
- Візуалізація 3: ... — навіщо

---

## 10. Висновки і рекомендації

*(заповнити в кінці)*