# Протокол для самопроверки

Заполняется по желанию. 

По данному протоколу работа будет проверяться преподавателем.

**Если на каком-то этапе функционал оказывается нерабочим, значит учащийся проигнорировал обязательное тестирование и работа может быть отправлена на доработку без проверки и комментариев или по работе может быть проставлен незачет, если лимит доработок исчерпан.**

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | PostgreSQL 17.2, x86_64-windows, 64-bit |
| Дата проверки | 21.11.2026–22.11.2026 |
| Схема | `melnikov_food` |
| Роль-аудитор | `inspector` |

Все проверки — под `inspector`, если не указано иное.

Заполняй «Факт» и «Вердикт» по каждой проверке. «Вердикт»: `OK` / `FAIL: <что именно>`.

---

## A. Подготовка

### A.1. Восстановление бэкапа

Ожидается: без ошибок.
Факт: Архив foodexpress_melnikov.backup восстановлен в БД foodexpress_check без ошибок.
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO melnikov_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.
Факт: current_database = foodexpress_check, current_user = inspector.
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `melnikov_food`.
Факт: Запрос вернул одну строку: melnikov_food.
Вердикт: OK

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.
Факт: Запрос вернул uuid-ossp в схеме exts.
Вердикт: OK

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'melnikov_food'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 + N штук).
Факт: Получены все 12 исходных таблиц и представление how_much_money: всего 13 строк. information_schema.tables включает также представления.
Вердикт: OK

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'melnikov_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.
Факт: Запрос не вернул строк: все столбцы с именами, оканчивающимися на _id, имеют тип uuid.
Вердикт: OK

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'melnikov_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.
Факт: Получены восемь ENUM-типов; их значения совпадают с constraints.md.
Вердикт: OK

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'melnikov_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.
Факт: Получены все 18 внешних ключей, включая составные order_client_address_fk, payment_order_amount_fk и review_order_client_fk.
Вердикт: OK

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.
Факт: В пяти полученных строках len = 32; password состоит из шестнадцатеричных символов.
Вердикт: OK

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: Вызов erase_test_data() завершился без ошибки.
Вердикт: OK

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.
Факт: Первый CALL insert_test_data(10) после очистки выполнен без ошибки.
Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: 10, 10, 10, 10, 50, 50, 50, 50, 50.
Факт: client = 10, courier = 10, product_category = 10, restaurant = 10; address = 50, product = 50, order = 50, review = 50, payment = 50.
Вердикт: OK

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего → 40 клиентских.
Факт: Получено 10 адресов ресторанов и 50 адресов всего; оставшиеся 40 адресов предназначены клиентам.
Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT count(*) FROM client WHERE login = '' OR password = '' OR phone_number = '';
-- и аналогично для других varchar-полей с NOT NULL
```

Ожидается: 0.
Факт: Пустых строк в обязательных текстовых полях нет: violations = 0 во всех девяти таблицах.
Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(*) FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL
  OR courier_id IS NULL OR address_id IS NULL OR total_amount IS NULL;
-- и аналогично для других NOT NULL полей
```

Ожидается: 0.
Факт: NULL в обязательных полях отсутствуют: violations = 0 во всех 12 таблицах.
Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.
Факт: Получено 7 курьеров со статусом, отличным от «уволен»; требование минимум одного работающего выполнено.
Вердикт: OK

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp
LIMIT 20;
```

Ожидается: `amount = expected_amount` в каждой строке.
Факт: Во всех 20 проверенных строках amount = expected_amount; расхождений нет.
Вердикт: OK

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются или заменяются (по решению студента, задокументированному в constraints.md).
Факт: Десять повторных вызовов insert_test_data(10) добавили данные без очистки существующих: client = 110, order = 550, product = 550, courier_pay = 660. Ошибок нет.
Вердикт: OK

---

## D. Проверки бизнес-правил на сгенерированных данных

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'order_structure → order' AS fk, count(*) AS orphans
FROM order_structure os
LEFT JOIN "order" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure → product', count(*)
FROM order_structure os
LEFT JOIN product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment → order', count(*)
FROM payment pmt
LEFT JOIN "order" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review → order', count(*)
FROM review r
LEFT JOIN "order" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay → courier', count(*)
FROM courier_pay cp
LEFT JOIN courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address → client', count(*)
FROM client_address ca
LEFT JOIN client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address → address', count(*)
FROM client_address ca
LEFT JOIN address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все 0.
Факт: Все семь проверенных ссылок вернули orphans = 0; строк со ссылками на отсутствующие записи в этих проверках нет.
Вердикт: OK

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.
Факт: Количество заказов с total_amount < 1000 равно 0.
Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.
Факт: Расхождений между commission и round(order_amount * 0.10, 2) нет: результат 0.
Вердикт: OK

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.
Факт: Расхождений между total_amount и round(order_amount + commission, 2) нет: результат 0.
Вердикт: OK

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.
Факт: Заказов с доставкой раньше создания нет: результат 0.
Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.
Факт: Заказов с адресом, не связанным с их клиентом, нет: результат 0.
Вердикт: OK

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.
Факт: Заказов с блюдом другого ресторана нет: результат 0.
Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;
```

Ожидается: пусто.
Факт: У каждого заказа ровно одна успешная оплата; запрос нарушений вернул пустой результат.
Вердикт: OK

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.
Факт: Несовпадений payment.amount и order.total_amount нет: результат 0.
Вердикт: OK

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: Проверка повторов пар client_id/address_id вернула пустой результат.
Вердикт: OK

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: Проверка повторов пар order_id/product_id вернула пустой результат.
Вердикт: OK

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.
Факт: Ресторанов с work_end <= work_start нет: результат 0.
Вердикт: OK

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.
Факт: Курьеров с датой увольнения раньше даты приёма нет: результат 0.
Вердикт: OK

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
-- product.rating = AVG(review.rating) по отзывам на блюдо
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE p.rating IS NOT NULL
LIMIT 20;
```

Ожидается: `rating = expected`.
Факт: product: mismatches = 0; restaurant: mismatches = 0. Расхождений нет, включая NULL при отсутствии отзывов.
Вердикт: OK

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов

```sql
SELECT count(*) AS before FROM product;

CALL add_product(
    p_restaurant_id => (SELECT restaurant_id FROM restaurant LIMIT 1),
    p_product_category_id => (SELECT product_category_id FROM product_category LIMIT 1),
    p_name => 'Тестовое блюдо',
    p_price => 250,
    p_rating => 4.5,
    p_status => 'доступно',
    p_description => 'Описание'
    -- + photo_url если есть
);

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.
Факт: При p_rating = NULL по BR-9.7 добавлено одно блюдо без ошибки: before = 550, after = 551.
Вердикт: OK

### E.2. `add_product` — падает на несуществующий ресторан

```sql
CALL add_product(
    p_restaurant_id => '00000000-0000-0000-0000-000000000000',
    -- остальные аргументы
);
```

Ожидается: ошибка с внятным сообщением.
Факт: Получена ожидаемая ошибка SQLSTATE P0001: «Ресторан с ID 00000000-0000-0000-0000-000000000000 не существует».
Вердикт: OK

### E.3. `rating_change` — пересчитывает рейтинг

```sql
-- Выбрать заказ, блюдо и клиента
SELECT p.product_id, p.rating FROM product p WHERE p.rating IS NOT NULL LIMIT 1;

-- Вставить отзыв на это блюдо
INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
VALUES (
    exts.uuid_generate_v4(),
    (SELECT client_id FROM client LIMIT 1),
    localtimestamp,
    <product_id>,
    'блюдо',
    (SELECT order_id FROM "order" LIMIT 1),
    'Тестовый отзыв',
    5
);

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: `rating` пересчитан.
Факт: Получен один тестовый отзыв: review_id = f3f9e8bf-34bf-4217-93f0-bd4da88fd804, product_id = 65fec4db-4e92-413d-b95b-87cd033d408e. Рейтинг блюда = 5, рассчитанное среднее expected = 5.
Вердикт: OK

### E.4. `rating_change` — удаление отзыва

```sql
-- Удалить отзыв из E.3
DELETE FROM review WHERE review_id = <review_id>;

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: если других отзывов нет — `rating IS NULL`; иначе — пересчитан.
Факт: После удаления отзыва f3f9e8bf-34bf-4217-93f0-bd4da88fd804 рейтинг блюда 65fec4db-4e92-413d-b95b-87cd033d408e стал NULL.
Вердикт: OK

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии заказов).

Факт: Функция вернула 110 строк: statistic_rows = 110, restaurants = 110, unknown_logins = 0. Все непустые best_user соответствуют существующим client.login.
Вердикт: OK

### E.6. `courier_salary()`

```sql
-- До
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;

CALL courier_salary();

-- После
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;
SELECT year, month, courier_id, amount, coefficient_used
FROM courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт: Выплаты рассчитаны без ошибки: couriers = 110, payments_this_month = 110, amount_errors = 0, coefficient_errors = 0. Коэффициенты всех 19 уволенных курьеров остались равны 0.10.
Вердикт: OK

### E.7. `courier_salary()` — повторный вызов

```sql
CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось (idempotency / обновление).
Факт: После повторного вызова courier_salary() количество выплат за текущий месяц осталось 110; дополнительных записей не появилось.
Вердикт: OK

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'melnikov_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Факт: Получены все восемь колонок в ожидаемом порядке: year_month имеет тип text, остальные семь — numeric.
Вердикт: OK

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).
Факт: Получены шесть последовательных месяцев: 2026-06, 2026-07, 2026-08, 2026-09, 2026-10, 2026-11. Границы доставленных заказов: first_month = 2026-06-01, last_month = 2026-11-01; начало и конец отчёта совпали, пропусков нет.
Вердикт: OK

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.
Факт: Месяц без доставленных заказов 2026-07 присутствует в отчёте: sum_no_commission = 0, sum_with_commission = 0, commission = 0, courier_pay = 0, net_profit = 0. prev_commission = 2826.91, commission_diff = -2826.91.
Вердикт: OK

### F.4. Корректность сумм

```sql
SELECT year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission_diff,
       courier_pay,
       net_profit
FROM how_much_money
ORDER BY year_month
LIMIT 10;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт: Во всех шести строках за 2026-06–2026-11 выполняются равенства commission = sum_with_commission - sum_no_commission, commission_diff = commission - prev_commission, net_profit = commission - courier_pay; расхождений нет. prev_commission совпадает с комиссией предыдущего месяца; для первого месяца prev_commission и commission_diff равны NULL.
Вердикт: OK

---

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT
    nspname AS schema_name,
    has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
    has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'melnikov_food';
```

Ожидается: `melnikov_food`, `true`, `true` (полный доступ).
Факт: Получена одна строка: schema_name = melnikov_food, usage = true, create = true.
Вердикт: OK

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'melnikov_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).
Факт: Получены 13 объектов: все 12 таблиц и представление how_much_money. У каждого присутствуют SELECT, INSERT, UPDATE, DELETE; также выданы TRUNCATE, REFERENCES, TRIGGER.
Вердикт: OK

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'melnikov_food';
RESET ROLE;
```

Ожидается: 12 + N (количество таблиц).
Факт: Под inspector запрос к information_schema.tables вернул 13: 12 базовых таблиц и представление how_much_money.
Вердикт: OK

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'melnikov_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: Под inspector запрос к pg_catalog.pg_tables вернул 12 базовых таблиц.
Вердикт: OK

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO melnikov_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.
Факт: erase_test_data(), insert_test_data(10), courier_salary(), get_statistic() и how_much_money доступны inspector; ошибок доступа и выполнения нет.
Вердикт: OK

---

## H. Оптимизация `get_statistic` (BR-11.8)

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`. Время растёт линейно от числа курьеров.
Факт: Execution Time = 0.201 мс, Planning Time = 0.138 мс. Seq Scan по courier вернул 10 строк; два SubPlan, в каждом Aggregate и Seq Scan по "order" с loops = 10. План соответствует повторному чтению "order" для каждого курьера.
Вердикт: OK

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Right Join` / `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.
Факт: Execution Time = 0.074 мс, Planning Time = 0.124 мс. HashAggregate и один Hash Right Join; Seq Scan по "order" с loops = 1, 11 доставленных заказов, по courier — 10 строк. Execution Time меньше H.1 (0.201 мс).
Вердикт: OK

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.
Факт: Внешний вызов: Function Scan on get_statistic, rows = 10, loops = 1, Planning Time = 0.019 мс, Execution Time = 0.301 мс. Внутренний SELECT: Planning Time = 0.624 мс, Execution Time = 0.284 мс, 10 строк результата. Seq Scan по каждой из пяти исходных таблиц ("order", order_structure, restaurant, product, client) встречается один раз с loops = 1. delivered_orders читается тремя CTE Scan; повторных чтений исходной "order" нет. В плане нет коррелированных SubPlan и WindowAgg; в запросе нет LATERAL.
Вердикт: OK

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.
Факт: После erase_test_data() все 12 таблиц пусты: client, courier, product_category, restaurant, address, product, "order", review, payment, order_structure, client_address, courier_pay — count = 0.
Вердикт: OK

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: Повторный вызов erase_test_data() для пустых таблиц завершился без ошибки.
Вердикт: OK

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.
Факт: После очистки insert_test_data(10) выполнен без ошибки; количество заказов — 50.
Вердикт: OK

