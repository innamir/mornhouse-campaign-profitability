# Mornhouse — аналіз прибутковості рекламних кампаній
## Робочий журнал аналізу (methodology log)

> Правило ведення цього журналу: гіпотеза фіксується ДО запуску запиту, висновок — одразу ПІСЛЯ. Не переписувати заднім числом.

---

## 1. Контекст і бізнес-питання

- **Мета:** побудувати єдину вітрину, яка показує прибутковість рекламних кампаній Mornhouse (cost vs revenue), і на її основі — дашборд у Tableau.
- **Що вважаємо "прибутковою кампанією":** визначення метрики буде зафіксовано в розділі 6, коли стане зрозуміло, які дані реально доступні для розрахунку доходу.
- **Джерела:** BigQuery, проєкт `mornhouse-test-environment`, датасет `test_app_dataset`, доступ viewer.
- **Заявлений період даних:** червень–липень 2026 (буде звірено з фактичними даними в кожній таблиці).
**Примітка щодо методу:** у реальному проєкті першим кроком був би запит документації/data dictionary та контакту власника даних, перш ніж витрачати час на реверс-інжиніринг структури й бізнес-логіки. У межах цього тестового завдання - самостійний data profiling з нуля.
---

## 2. Аудит вихідних даних (Data Profiling)

Мета етапу: зрозуміти grain, обсяг, діапазон дат і якість потенційних ключів кожної таблиці окремо, до будь-яких JOIN. Усі запити — в `sql/01_profiling.sql`, з коментарями, що пояснюють кожен крок і його результат.

### 2.1 non_org_installs_report

**Query 1 — базові метрики:** `sql/01_profiling.sql` — секція `non_org_installs_report`
| min_install_date | max_install_date | row_count | distinct_campaigns | distinct_media_sources |
|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 777724 | 54 | 3 |

**Query 2 — аудит кандидатів на join-ключ (з відсотками):**
| row_count | analytics_installation_id_non_null | analytics_installation_id_pct | analytics_installation_id_distinct | advertising_id_non_null | advertising_id_pct | advertising_id_distinct |
|---|---|---|---|---|---|---|
| 777724 | 0 | 0.0% | 0 | 489544 | 62.9% | 473477 |

| firebase_app_id_non_null | firebase_app_id_pct | firebase_app_id_distinct | appsflyer_id_non_null | appsflyer_id_pct | appsflyer_id_distinct |
|---|---|---|---|---|---|
| 777724 | 100.0% | 777724 | 0 | 0.0% | 0 |

**Висновок:**
- Grain: одна подія атрибутованого інсталу.
- Діапазон дат (2026-06-01 – 2026-07-26) — базовий орієнтир для звірки з іншими таблицями.
- `analytics_installation_id` і `appsflyer_id` — 100% NULL, непридатні як join-ключ.
- `advertising_id` — заповнений на 62.9%, робочий, але з відчутною втратою.
- **`firebase_analytic_app_id` — 100% заповнений, унікальний на рядок. Найсильніший кандидат на join-ключ рівня пристрою.**
- 54 кампанії, 3 media_source — орієнтир для звірки з cost_table.

**Гіпотези, що виникли:** розділ 3, №1 , №2.

### 2.2 cost_table

**Query 1 — базові метрики:** `sql/01_profiling.sql` — секція `cost_table`
| min_date | max_date | row_count | distinct_apps | distinct_campaigns | distinct_media_sources | null_campaign_id | null_media_source |
|---|---|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 5253424 | 1 | 48 | 1 | 0 | 0 |

**Query 2 — звірка media_source з non_org_installs_report:**
| source_table | media_source | row_count |
|---|---|---|
| cost_table | googleadwords_int | 5253424 |
| non_org_installs_report | googleadwords_int | 416142 |
| non_org_installs_report | other | 95528 |
| non_org_installs_report | unknown | 266054 |

**Висновок:**
- Діапазон дат повністю збігається з non_org_installs_report.
- row_count значно більший за installs — grain тут campaign × adset × geo × day.
- distinct_campaigns = 48 vs 54 в installs — розбіжність, причина не з'ясована.
- distinct_media_sources = 1 vs 3 в installs — критична розбіжність. cost_table покриває лише `googleadwords_int`. `other`/`unknown` — ймовірно службові категорії атрибуції, не платні мережі (гіпотеза).
- `campaign_id`/`media_source` структурно чисті (без NULL).

**Гіпотези, що виникли:** розділ 3, №3, №4.

### 2.3 ad_revenue_raw

**Query:** `sql/01_profiling.sql` — секція `ad_revenue_raw`
**Результат:**
| min_event_date | max_event_date | row_count | distinct_apps | distinct_campaigns | distinct_media_sources | null_campaign_id | null_campaign_id_pct |
|---|---|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 5955170 | 1 | 137 | 3 | 351694 | 5.9% |

| distinct_analytics_installation_id | null_analytics_installation_id_pct | distinct_firebase_app_id | null_firebase_app_id_pct | distinct_advertising_id | null_advertising_id_pct | distinct_appsflyer_id | null_appsflyer_id_pct |
|---|---|---|---|---|---|---|---|
| 0 | 100.0% | 268249 | 0.0% | 242204 | 6.3% | 0 | 100.0% |

**Висновок:**
- Діапазон дат збігається з іншими таблицями.
- Grain: одна подія показу/завершення реклами — звідси набагато більший обсяг.
- `null_campaign_id = 351694` (~5.9%) — частина подій доходу не атрибутована.
- `distinct_campaigns = 137` > 54 (installs), > 48 (cost) — гіпотеза про когорти різної зрілості (дохід від installs до початку періоду).
- `firebase_analytic_app_id` — 268249 distinct, 0% NULL, узгоджено з installs (~22 події на пристрій) — підтверджує гіпотезу №2. `analytics_installation_id`/`appsflyer_id` — 100% NULL.

**Гіпотези, що виникли:** розділ 3, №2 (додатково підтверджено), №6 .

### 2.4 in_app_events_report

**Query 1 — базові метрики:** `sql/01_profiling.sql` — секція `in_app_events_report`
**Результат:**
| min_event_date | max_event_date | row_count | distinct_apps | distinct_campaigns | distinct_media_sources | null_campaign_id | null_campaign_id_pct |
|---|---|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 24963 | 1 | 91 | 3 | 2713 | 10.9% |

| firebase_app_id_non_null | firebase_app_id_pct | firebase_app_id_distinct | advertising_id_non_null | advertising_id_pct | advertising_id_distinct | distinct_event_names |
|---|---|---|---|---|---|---|
| 23943 | 95.9% | 14115 | 21484 | 86.1% | 12680 | 10 |

**Query 2 — дохід по типах подій:**
| event_name | row_count | total_revenue | null_revenue | voided_count |
|---|---|---|---|---|
| trial_started | 6866 | — | 6866 | 0 |
| subscription_billing_grace | 6179 | — | 6179 | 0 |
| trial_churned | 6064 | — | 6064 | 0 |
| subscription_renewed | 2021 | 41098.97 | 0 | 0 |
| trial_canceled | 2017 | — | 2017 | 0 |
| trial_converted | 679 | 21308.24 | 0 | 0 |
| subscription_canceled | 512 | — | 512 | 0 |
| subscription_churned | 422 | — | 422 | 0 |
| subscription_refunded | 189 | −6014.65 | 0 | 189 |
| no_trial_sub_started | 14 | 95.83 | 0 | 0 |

**Висновок:**
- Grain: одна подія в життєвому циклі підписки/покупки. Малий обсяг — очікувано.
- `null_campaign_id` — найвищий серед усіх таблиць (~10.9%).
- `distinct_campaigns = 91` — точка в послідовності 54 → 48 → 91 → 137 (гіпотеза №6).
- Лише 4 з 10 `event_name` несуть дохід; `SUM(event_revenue_usd)` без фільтрів коректний (NULL ігнорується, refund зі знаком мінус).
- Перевірка дублікатів рядків — розділ 2.5.

**Гіпотези, що виникли:** розділ 3, №6.

## 2.5 Перевірка якості даних (Data Quality Checks)

Цілеспрямована перевірка надійності конкретних полів, які підуть у розрахунок cost/revenue/profit, виконана після завершення профайлінгу всіх таблиць.

### Дублікати рядків (in_app_events_report)

**Query 1 (крок 1) — групування лише по order_id:** `sql/01_profiling.sql`
Сотні order_id з 4-5 рядками — виявилось, що це стадії життєвого циклу підписки, не дублікати.

**Query 2 (крок 2) — точний natural key (order_id + event_name + timestamp + event_revenue_usd):**
Виявила справжні дублікати рядків, включно з revenue-bearing подіями.

**Query 3 — кількісна оцінка впливу на дохід:** TODO, наступний крок.

**Висновок:** підтверджена пастка "подвійний облік доходу" — потрібна дедуплікація перед `SUM` у фінальній вітрині.

**Інші перевірки чеклиста (TODO):**
- Від'ємні/аномальні значення в cost_usd, event_revenue_usd
- Логічна узгодженість дат (event_date >= install_date)
- Дублікати рядків в ad_revenue_raw
- Коректність конвертації валют (cost vs cost_usd)

## 3. Журнал гіпотез (Hypothesis Log)

| # | Гіпотеза | Як перевірено | Результат | Статус |
|---|---|---|---|---|
| 1 | `analytics_installation_id` — Firebase Analytics ID, не завжди проставляється в момент інсталу, тому NULL структурно | Перевірено NULL-rate на non_org_installs_report і ad_revenue_raw | 100% NULL в обох таблицях (777724/777724 та 5955170/5955170) | емпірично підтверджено (поле системно порожнє); причина (SDK timing) — припущення, документально не підтверджена. Перевірити ще в in_app_events_report |
| 2 |`firebase_analytic_app_id` — стабільний device-level ідентифікатор, придатний як join-ключ між installs і revenue-таблицями | Перевірено заповненість і кардинальність на non_org_installs_report і ad_revenue_raw | 100% заповнено в обох; унікальний на рядок в installs (777724/777724), ~22 повтори на значення в ad_revenue_raw (268249 distinct / 5955170 рядків) — узгоджена поведінка device ID | сильно підтверджено за формою; реальний value-level overlap між таблицями ще не перевірено (Join Key Mapping) 
| 3 | campaign_id в cost_table і non_org_installs_report — різні системи нумерації (ad network ID vs attribution ID) | Порівняно кількість distinct: 48 (cost) vs 54 (installs) | Числа близькі, але не рівні — точний overlap множин значень ще не перевірено запитом | частково перевірено — потрібен прямий overlap-запит у Join Key Mapping |
| 4 | media_source = "other"/"unknown" в non_org_installs_report — службові категорії атрибуції, а не реальні платні мережі з відсутнім cost-трекінгом | Перевірити campaign_id/інші поля у рядків з цими значеннями media_source | — | потребує перевірки |
| 5 | Вітрина будується на рівні grain = campaign (+ media_source, + date), а не на рівні окремого користувача | Логічний висновок з формулювання задачі ("які кампанії прибуткові") | — | робоче припущення, переглянути якщо знадобиться LTV/cohort розріз |
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