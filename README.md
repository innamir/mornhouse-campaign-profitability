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
| min_install_date | max_install_date | row_count | distinct_campaigns | distinct_media_sources | null_campaign_id | null_campaign_id_pct |
|---|---|---|---|---|---|---|
| 2026-06-01 | 2026-07-26 | 777724 | 54 | 3 | 448708 | 57.7% |

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
- **57.7% install-подій (448708 з 777724) не мають campaign_id взагалі** — критична знахідка, виявлена не одразу. Це не помилка, а структурна межа: атрибуція на рівні кампанії доступна лише для 42.3% інсталів. 
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

**Query 1 (крок 1) — групування лише по order_id:** `sql/02_data_quality.sql`
Сотні order_id з 4-5 рядками — виявилось, що це стадії життєвого циклу підписки, не дублікати.

**Query 2 (крок 2) — точний natural key (order_id + event_name + timestamp + event_revenue_usd):** `sql/02_data_quality.sql`
Виявила справжні дублікати рядків, включно з revenue-bearing подіями.

**Query 3 — кількісна оцінка впливу на дохід:**
| duplicate_groups | total_duplicate_rows | excess_rows | excess_revenue_impact |
|---|---|---|---|
| 36 | 74 | 38 | −$218.98 |

**Висновок:** підтверджена пастка "подвійний облік доходу". Дублікати переважно серед `subscription_refunded` (від'ємні суми), тому наївний `SUM` без дедуплікації занижує дохід на $218.98 (~0.4% від загального доходу таблиці, ~$56488). **Дедуплікація обов'язкова** перед `SUM(event_revenue_usd)` у фінальній вітрині (напр. `ROW_NUMBER() OVER (PARTITION BY order_id, event_name, timestamp, event_revenue_usd) = 1`).

### Дублікати рядків (ad_revenue_raw)

**Query 1 — точний natural key (firebase_analytic_app_id + timestamp + ad_unit_id + event_revenue_usd):** `sql/02_data_quality.sql`
| duplicate_groups | total_duplicate_rows | excess_rows | excess_revenue_impact |
|---|---|---|---|
| 288680 | 3763349 | 3474669 | $88.62 |

**Query 2 — пояснення грубого ключа:** `sql/02_data_quality.sql`
| distinct_ad_unit_ids | null_revenue_rows | total_rows | null_revenue_pct |
|---|---|---|---|
| 12 | 2379315 | 5955170 | 40.0% |

**Висновок:** попри величезну кількість "дублікатів" за рядками (58% таблиці), фінансовий вплив мізерний ($88.62 з мільйонів доларів обороту). Причина — занадто грубий ключ: лише 12 унікальних `ad_unit_id` і 40% рядків без доходу, тобто ключ не розрізняє тисячі реально різних показів реклами. Ймовірно, артефакт mock-даних цього sandbox-датасету, а не реальний ETL-дублікат. **Дедуплікація не потрібна** для розрахунку revenue — матеріального впливу немає.

### Аномалії cost_usd та коректність конвертації валют (cost_table)

**Query 1 — перевірка cost_usd на аномалії:** `sql/02_data_quality.sql`
| min_cost_usd | max_cost_usd | negative_cost_rows | avg_cost_usd |
|---|---|---|---|
| 0.0 | 8.82 | 0 | 0.0 |

**Query 2 — чи є більше однієї валюти:**
| cost_currency | row_count |
|---|---|
| EUR | 894763 |
| USD | 4358661 |

**Query 3 — коректність конвертації (cost_usd / cost за валютою):**
| cost_currency | avg_conversion_rate | min_conversion_rate | max_conversion_rate |
|---|---|---|---|
| EUR | 1.1478 | 1.1354 | 1.1648 |
| USD | 1.0 | 1.0 | 1.0 |

**Висновок:** `cost_usd` ніколи не від'ємний, максимум адекватний ($8.82 на найдетальнішому рівні гранульності). 17% рядків (894763) спочатку в EUR — конвертація стабільна, курс у вузькому реалістичному діапазоні. USD-рядки коректно мають коефіцієнт 1.0. **Перевірено, проблем не знайдено.**

**Інші перевірки чеклиста:**
- ~~Повнота ключів з'єднання (NULL-rate campaign_id/media_source)~~ — виконано під час профайлінгу, див. 2.1-2.4 (cost_table 0%, installs 57.7%, ad_revenue_raw 5.9%, in_app_events_report 10.9%).
- ~~Від'ємні/аномальні значення cost_usd, коректність конвертації валют~~ — виконано вище, проблем не знайдено.
- Логічна узгодженість дат (event_date >= install_date) — **свідомо винесено за межі обсягу тестового завдання**: вимагає дорогого device-level JOIN, не потрібного для campaign-level вітрини.

## 3. Журнал гіпотез (Hypothesis Log)

| # | Гіпотеза | Як перевірено | Результат | Статус |
|---|---|---|---|---|
| 1 | `analytics_installation_id` — Firebase Analytics ID, не завжди проставляється в момент інсталу, тому NULL структурно | Перевірено NULL-rate на non_org_installs_report і ad_revenue_raw | 100% NULL в обох таблицях | емпірично підтверджено; причина (SDK timing) — припущення, не підтверджена документально |
| 2 | `firebase_analytic_app_id` — стабільний device-level ідентифікатор, придатний як join-ключ між installs і revenue-таблицями | Перевірено заповненість і кардинальність на всіх таблицях | 100%/95.9% заповнено, кардинальність узгоджена з поведінкою device ID | **підтверджено й ОБРАНО як основний ключ методу** — центральний елемент когортної атрибуції доходу (не побічна знахідка, а ядро розрахунку) |
| 3 | campaign_id в cost_table і non_org_installs_report — різні системи нумерації (ad network ID vs attribution ID) | Overlap-запит: 46 з 48 campaign_id з cost_table збігаються з installs | Переважна більшість збігається — це той самий простір ID, різниця мінімальна (2 кампанії) | спростовано як "різні системи нумерації"; підтверджено як робочий спільний ключ |
| 4 | media_source = "other"/"unknown" в non_org_installs_report — службові категорії атрибуції, а не реальні платні мережі з відсутнім cost-трекінгом | Не перевірено окремим запитом | — | залишається відкритим, малий пріоритет — при обраному методі ці когорти однаково не матимуть cost (cost_table покриває лише googleadwords_int) |
| 5 | Вітрина будується на рівні grain = campaign (+ media_source), без user-level join | Переглянуто після рішення про метод | — | **СКАСОВАНО.** Фінальний grain залишається campaign-рівнем, але досягається через проміжний device-level join (когортна атрибуція за firebase_analytic_app_id), а не напряму через campaign_id у revenue-таблицях |
| 6 | distinct_campaigns у ad_revenue_raw (137) перевищує installs (54) і cost_table (48) через дохід від installs, здійснених до початку періоду даних | Не перевірено install_date напряму | — | **ВИРІШЕНО вибором методу**, доводити причину більше не потрібно: когортна атрибуція (installs → revenue через firebase_analytic_app_id) природно виключає дохід від пристроїв, яких немає в non_org_installs_report (тобто інстальованих до 1.06) — окремий фільтр не потрібен, це побічний ефект напрямку JOIN |

## 4. Ключі з'єднання (Join Key Mapping)


**Обраний метод: когортна атрибуція доходу (cohort-based revenue attribution).**
Дохід прив'язую до кампанії за когортним принципом: беру campaign_id з install-події
(яка кампанія залучила користувача), а не з самого revenue-рядка.

**Архітектура — два етапи:**

**Етап 1 — атрибуція доходу на рівні пристрою.** Агрегуємо `ad_revenue_raw` і дедуплікований `in_app_events_report` по `firebase_analytic_app_id` (SUM revenue на пристрій). 

**Етап 2 — приєднання до когорти інсталу.** JOIN агрегованого доходу з Етапу 1 до `non_org_installs_report` через `firebase_analytic_app_id`. Беремо лише installs із заповненим `campaign_id` (42.3% рядків — решта 57.7% без campaign_id виключаються, бо не можуть бути прив'язані до жодної кампанії). Кожен інстал тепер несе **весь** дохід свого пристрою, незалежно від того, який campaign_id стояв у самому revenue-рядку.

**Етап 3 — згортання до рівня кампанії.** `GROUP BY campaign_id, media_source` (з installs) → сума когортного доходу, кількість інсталів.

**Етап 4 — приєднання витрат.** `LEFT JOIN` результату Етапу 3 до агрегованого `cost_table` (по campaign_id + media_source). `cost_table` лишається anchor — усі 48 кампаній з витратами присутні у фінальній вітрині, навіть якщо когортний дохід = 0.

**Побічний ефект напрямку JOIN, який вирішує гіпотезу №6 без додаткового фільтра:** оскільки ми йдемо від installs (обмежені періодом 1.06–26.07) до revenue, а не навпаки, дохід від пристроїв, які встановили застосунок ДО 1 червня, автоматично не знаходить пари (такого пристрою просто немає в non_org_installs_report) — і природно виключається. Окремо виключати "orphan"-кампанії з revenue-таблиць більше не потрібно.

**Обмеження методу (right-censoring), яке лишається і варто явно проговорити в звіті:** навіть при когортній атрибуції кампанія, що стартувала 20 липня, має лише ~6 днів спостереження доходу проти ~8 тижнів для кампанії з 1 червня. Це не помилка методу, а межа доступних даних (вікно закінчується 26.07). Рекомендація: додати в вітрину похідну колонку "вік кампанії" (днів від першої дати в cost_table до 26.07) і позначати дуже молоді кампанії як "недостатньо даних для висновку" замість змішування їх без розбору з визрілими.

**Пов'язані гіпотези:** №2 (обрано як ядро методу), №5 (скасовано — grain campaign досягається через проміжний device-level join), №6 (вирішено вибором методу).
---

## 5. Відомі обмеження вітрини

| Обмеження | Опис | Вплив на результат |
|---|---|---|
| Покриття cost за джерелом | cost_table містить витрати лише по googleadwords_int | Рентабельність не може бути порахована для кампаній із media_source = other/unknown — вони структурно поза розрахунком |
| Неатрибутовані інстали | 57.7% install-подій не мають campaign_id | Ці інстали (і весь дохід від них) не входять у жодну когорту кампанії |
| Right-censoring (обрізаний період) | Дані обмежені 26.07.2026 | Кампанії, що стартували ближче до кінця періоду, мають менше часу на дохід — пряме порівняння з давнішими кампаніями може вводити в оману без урахування "віку" кампанії |

---

## 6. Визначення метрик (Metric Definitions)

## 6. Визначення метрик (Metric Definitions)

Query reference: `sql/03_mart.sql`

| Метрика | Формула | Опис |
|---|---|---|
| Cost | SUM(cost_usd) по campaign_id + media_source | Загальні витрати на кампанію за весь період (з cost_table) |
| Total Revenue | total_ad_revenue + total_iap_revenue | Дохід, атрибутований інсталам кампанії: реклама (ad_revenue_raw) + підписки/покупки (in_app_events_report), очищені від дублікатів |
| Profit | Total Revenue − Cost | Абсолютний прибуток - збиток кампанії в доларах |
| ROAS | Total Revenue / Cost | Скільки повертається на кожен вкладений долар. |
| CAC | Cost / install_count | Середня вартість залучення одного інсталу.|


## 7. Фінальна схема вітрини (Mart Schema)

Query reference: `sql/03_mart.sql`
Grain: один рядок = одна кампанія (campaign_id + media_source). Рядків: 48.

| Поле | Тип | Опис |
|---|---|---|
| campaign_id | INT64 | Ідентифікатор кампанії (з cost_table) |
| media_source | STRING | Джерело трафіку (в даних представлено лише googleadwords_int) |
| total_cost_usd | FLOAT64 | Сумарні витрати на кампанію за весь період (з cost_table) |
| install_count | INT64 | Кількість інсталів, атрибутованих кампанії. 0 для 2 кампаній без відповідних інсталів у non_org_installs_report |
| cac | FLOAT64 | Вартість залучення одного інсталу (total_cost_usd / install_count). NULL, якщо install_count = 0 |
| total_ad_revenue | FLOAT64 | Сумарний дохід від реклами (ad_revenue_raw), атрибутований інсталам кампанії |
| total_iap_revenue | FLOAT64 | Сумарний дохід від підписок/покупок (in_app_events_report), очищений від дублікатів; повернення (refund) вже враховані як від'ємні значення |
| total_revenue | FLOAT64 | total_ad_revenue + total_iap_revenue |
| profit | FLOAT64 | total_revenue − total_cost_usd |
| roas | FLOAT64 | total_revenue / total_cost_usd. NULL, якщо total_cost_usd = 0 |

---


## 8. Дашборд у Tableau

*(заповнити на етапі побудови дашборду)*

- Візуалізація 1: ... — навіщо
- Візуалізація 2: ... — навіщо
- Візуалізація 3: ... — навіщо

---

## 9. Висновки і рекомендації

*(заповнити в кінці)*