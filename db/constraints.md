# Обоснование ограничений

## Как заполнять

Для каждого ограничения указаны таблица, столбцы, бизнес-правило и причина выбора. Очевидная обязательность PK и обычных обязательных FK отдельно не дублируется.

---

## Enum-типы

Созданы восемь типов в схеме `melnikov_food`. Значения соответствуют бизнес-правилам без изменений; ENUM исключает произвольные строки и опечатки по BR-11.5.

| Тип | Значения | BR |
|---|---|---|
| `restaurant_status` | `активен`, `неактивен` | BR-4.3, BR-11.5 |
| `product_status` | `доступно`, `нет_в_наличии`, `архив` | BR-5.5, BR-11.5 |
| `courier_status` | `свободен`, `занят`, `на_доставке`, `уволен` | BR-6.2, BR-11.5 |
| `order_status` | `создан`, `готовится`, `в_доставке`, `доставлен`, `отменён` | BR-7.7, BR-11.5 |
| `order_pay_status` | `ожидает`, `оплачен`, `ошибка` | BR-7.9, BR-11.5 |
| `payment_status` | `успех`, `ошибка`, `в_обработке` | BR-8.2, BR-11.5 |
| `payment_type` | `карта`, `наличные`, `безнал` | BR-8.2, BR-11.5 |
| `review_entity_type` | `блюдо`, `ресторан`, `заказ` | BR-9.1, BR-11.5 |

---

## Ловушки

### Ловушка 1: `payment` — неполная сущность

**Какие атрибуты добавил в `payment` и почему** (BR-8.2):

В попытке оплаты хранятся `pay_type`, `amount`, `transaction_reference`, `transaction_timestamp` и `status`, потому что BR-8.2 требует способ оплаты, сумму, идентификатор транзакции, дату/время и статус. `transaction_reference` уникален по BR-8.3. Сумма сверяется с `order.total_amount` составным FK по BR-8.4. Данные карты не сохраняются по BR-8.5.

По BR-8.7 статус оплаты заказа вычисляется по попыткам: есть успех — «оплачен»; иначе есть обработка — «ожидает»; иначе есть только ошибки — «ошибка». При отсутствии попыток используется «ожидает»: BR-8.7 этот случай явно не определяет. Пересчёт обеспечивают `12_pay_status.sql` и обработчик TRUNCATE payment из `15_aggregate_integrity.sql`.

**Где хранится тип оплаты — `payment` или `order`** (BR-8.6):

Тип оплаты хранится в `payment.pay_type`, потому что BR-8.6 разрешает разные способы у разных попыток одного заказа. Тип не переносится в заказ.

### Ловушка 2: `order.address_id` — принадлежность клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**

Используется составной `order_client_address_fk`:

```sql
FOREIGN KEY (client_id, address_id)
REFERENCES melnikov_food.client_address (client_id, address_id)
```

Заказ ссылается на зарегистрированную пару клиента и адреса, потому что BR-7.4 требует адрес именно этого клиента. Обычный FK только на `address_id` проверял бы существование адреса, но не его принадлежность. Один адрес разрешено связывать с разными клиентами по BR-2.4. Составной `client_address_pkey (client_id,address_id)` исключает повтор одной пары по BR-2.5.

### Ловушка 3: `order_structure` — один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**

Функция `check_order_restaurant()` из `04_constraints.sql` сравнивает ресторан блюда с рестораном заказа при INSERT и изменении ссылок позиции. Дополнительные триггеры проверяют смену ресторана самого заказа или блюда. Операция отклоняется, если она нарушает BR-7.3.

Составной `order_structure_pkey (order_id,product_id)` запрещает повтор блюда в заказе по BR-7.16. Триггеры из `14_order_contents.sql` проверяют наличие хотя бы одной позиции по BR-7.14 и равенство `order_amount = round(sum(product.price * quantity),2)` по BR-7.10. Проверка выполняется в конце транзакции, когда добавлены и заказ, и позиции; изменения состава, суммы и цены, включая очистку состава через TRUNCATE, также учитываются.

### Ловушка 4: `review` — полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**

Сохранена полиморфная пара `entity_type`/`entity_id`. Один обычный FK не может ссылаться то на блюдо, то на ресторан, то на заказ; допустимую цель проверяет `check_review_entity()` из `04_constraints.sql`:

- `блюдо`: в `order_structure` существует пара `review.order_id`/`review.entity_id`;
- `ресторан`: `entity_id` совпадает с рестораном указанного заказа;
- `заказ`: `entity_id` совпадает с `review.order_id`.

Эти проверки обеспечивают BR-9.1–9.2: отзыв относится к допустимому типу и к тому, что было заказано. `review_order_client_fk` обеспечивает совпадение автора с клиентом заказа. Изменение или удаление позиции с сохраняющимся отзывом и смена ресторана заказа с ресторанным отзывом отклоняются; отдельная проверка из `15_aggregate_integrity.sql` не позволяет обойти принадлежность через TRUNCATE состава. Условия оплаты или доставки для допуска отзыва не вводятся: BR-9.1–9.2 их не задают.

---

## CHECK-ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| `courier` | `coefficient` | `BETWEEN 0.10 AND 0.50` | BR-6.4 | Допустим только заданный диапазон коэффициента (`courier_coefficient_check`). |
| `courier` | `status`, `dismissal_date` | `status <> 'уволен' OR dismissal_date IS NOT NULL` | BR-6.3 | Дата увольнения обязательна у уволенного курьера (`courier_dismissed_date_check`). |
| `courier` | `hire_date`, `dismissal_date` | `dismissal_date IS NULL OR dismissal_date >= hire_date` | BR-6.1, BR-6.3 | Даты найма и увольнения должны быть согласованы; это также проверяет D.13 шаблона (`courier_dates_check`). |
| `restaurant` | `work_start`, `work_end` | `work_end > work_start` | BR-4.4 | Закрытие должно быть позже открытия (`restaurant_work_time_check`). |
| `restaurant` | `rating` | `BETWEEN 0 AND 5` | BR-4.2 | Заполненный рейтинг ограничен заданным диапазоном (`restaurant_rating_check`). |
| `product` | `price` | `price >= 0` | BR-5.3 | Отрицательная цена запрещена, нулевая разрешена (`product_price_check`). |
| `product` | `rating` | `BETWEEN 0 AND 5` | BR-5.4 | Заполненный рейтинг ограничен заданным диапазоном (`product_rating_check`). |
| `courier_pay` | `month` | `BETWEEN 1 AND 12` | BR-10.3 | Выплата относится к календарному месяцу (`courier_pay_month_check`). |
| `courier_pay` | `amount` | `amount >= 0` | BR-10.4 | Выплата не может быть отрицательной (`courier_pay_amount_check`). |
| `courier_pay` | `coefficient_used` | `BETWEEN 0.10 AND 0.50` | BR-6.4, BR-10.2 | Сохранённый применённый коэффициент находится в том же допустимом диапазоне (`courier_pay_coefficient_check`). |
| `order` | `total_amount` | `total_amount >= 1000` | BR-1.8, BR-7.11 | Итог заказа не может быть меньше минимальной суммы (`order_minimum_total_check`). |
| `order` | `order_timestamp`, `delivery_timestamp` | `delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp` | BR-7.13 | Окончание доставки не может предшествовать созданию (`order_delivery_time_check`). |
| `order` | `status`, `delivery_timestamp` | `status <> 'доставлен' OR delivery_timestamp IS NOT NULL` | BR-7.12 | У доставленного заказа обязательно заполнено время окончания доставки (`order_delivered_time_check`). |
| `order_structure` | `quantity` | `quantity > 0` | BR-7.15 | Количество строго положительное; дробные значения допускаются (`order_structure_quantity_check`). |
| `review` | `rating` | `BETWEEN 1 AND 5` | BR-9.4 | Оценка отзыва находится в заданном диапазоне (`review_rating_check`). |

---

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | Один логин не может принадлежать двум клиентам (`client_login_unique`). |
| `client` | `phone_number` | BR-2.2 | Телефон клиента уникален (`client_phone_number_unique`). |
| `restaurant` | `address_id` | BR-3.3, BR-3.4 | Одна адресная запись используется только одним рестораном (`restaurant_address_unique`). Совпадение физических адресов с разными ID дополнительно проверяет `13_restaurant_address.sql` по улице, дому и квартире/офису; два NULL квартиры считаются совпадением. |
| `payment` | `transaction_reference` | BR-8.3 | Идентификатор финансовой транзакции провайдера не повторяется (`payment_transaction_reference_unique`). |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5 | В одном заказе разрешён один отзыв на конкретный объект (`review_order_entity_unique`). |
| `order` | `(order_id, client_id)` | BR-9.2 | Технический ключ для составного FK автора отзыва; новых запретов не добавляет, поскольку order_id уже PK (`order_client_pair_unique`). |
| `order` | `(order_id, total_amount)` | BR-8.4 | Технический ключ для составного FK суммы оплаты (`order_total_pair_unique`). |
| `payment` | `order_id WHERE status = 'успех'` | BR-8.1 | Частичный уникальный индекс запрещает вторую успешную попытку, не ограничивая число ошибок и обработок (`payment_one_success_per_order_idx`). Он обеспечивает «не более одной», но сам по себе не гарантирует наличие успеха. |

---

## FK-ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` | `client(client_id)` | BR-2.4 | Связь относится к существующему клиенту (`client_address_client_fk`). |
| `client_address` | `address_id` | `address(address_id)` | BR-2.4, BR-3.5 | Связь относится к существующему адресу (`client_address_address_fk`); удаление клиента не удаляет адрес каскадно. |
| `restaurant` | `address_id` | `address(address_id)` | BR-3.3, BR-3.5 | Ресторан имеет существующий адрес (`restaurant_address_fk`); удаление ресторана не удаляет адрес каскадно. |
| `product` | `product_category_id` | `product_category(product_category_id)` | BR-5.1 | Категория блюда должна существовать (`product_category_fk`). |
| `product` | `restaurant_id` | `restaurant(restaurant_id)` | BR-5.1 | Ресторан блюда должен существовать (`product_restaurant_fk`). |
| `courier_pay` | `courier_id` | `courier(courier_id)` | BR-10.2 | Выплата относится к существующему курьеру (`courier_pay_courier_fk`). |
| `order` | `courier_id` | `courier(courier_id)` | BR-7.5 | Доставка назначается существующему курьеру (`order_courier_fk`). |
| `order` | `client_id` | `client(client_id)` | BR-7.1, BR-7.2 | Заказ оформляется существующим клиентом (`order_client_fk`). |
| `order` | `address_id` | `address(address_id)` | BR-7.4 | Адрес доставки существует (`order_address_fk`). |
| `order` | `restaurant_id` | `restaurant(restaurant_id)` | BR-7.2 | Заказ относится к существующему ресторану (`order_restaurant_fk`). |
| `order` | `(client_id, address_id)` | `client_address(client_id, address_id)` | BR-7.4 | Адрес принадлежит клиенту заказа (`order_client_address_fk`). |
| `order_structure` | `order_id` | `order(order_id)` | BR-7.14 | Позиция принадлежит существующему заказу (`order_structure_order_fk`). |
| `order_structure` | `product_id` | `product(product_id)` | BR-7.14 | Заказанное блюдо существует (`order_structure_product_fk`). |
| `payment` | `order_id` | `order(order_id)` | BR-8.1 | Попытка оплаты относится к существующему заказу (`payment_order_fk`). |
| `payment` | `(order_id, amount)` | `order(order_id, total_amount)` | BR-8.4 | Сумма попытки равна итогу именно её заказа (`payment_order_amount_fk`). |
| `review` | `client_id` | `client(client_id)` | BR-9.2 | Автор отзыва существует (`review_client_fk`). |
| `review` | `order_id` | `order(order_id)` | BR-9.2 | Заказ отзыва существует (`review_order_fk`). |
| `review` | `(order_id, client_id)` | `order(order_id, client_id)` | BR-9.2 | Автор совпадает с клиентом этого заказа (`review_order_client_fk`). |

---

## NOT NULL (только бизнес-обязательные)

Выделены случаи с отдельным бизнес-смыслом; PK и обычные обязательные FK не дублируются.

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `review` | `rating` | BR-9.4, BR-11.3 | Оценка самого отзыва обязательна, в отличие от агрегированного рейтинга без отзывов. |
| `review` | `entity_type`, `entity_id` | BR-9.1, BR-9.2, BR-11.3 | У каждого отзыва должна быть определена полиморфная цель; отсутствие обычного FK не делает её необязательной. |
| `courier` | `coefficient` | BR-6.4, BR-6.5 | DEFAULT задаёт начальное значение, но не должен позволять явно записать NULL вместо коэффициента. |
| `payment` | `transaction_reference` | BR-8.2, BR-8.3 | Каждая попытка имеет идентификатор транзакции; UNIQUE сам по себе не запрещает NULL. |

---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2 | Квартира/офис могут отсутствовать. |
| `courier` | `dismissal_date` | BR-6.3 | Работающий курьер не обязан иметь дату увольнения; у уволенного её требует CHECK. |
| `product` | `photo_url` | BR-5.6 | Фотография блюда необязательна. |
| `product` | `rating` | BR-9.7 | Без отзывов агрегированного рейтинга нет. |
| `restaurant` | `rating` | BR-9.7 | Без отзывов агрегированного рейтинга нет. |
| `order` | `delivery_timestamp` | BR-7.12 | До окончания доставки время может отсутствовать; у доставленного заказа его требует CHECK. |
| `review` | `photo_url` | BR-9.3 | Фотография отзыва необязательна. |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| `client` | `client_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует UUID, генерируемый на сервере. Схема exts с расширением подготовлена заранее по BR-13.3. Повторный вызов `insert_test_data` добавляет новую порцию строк без очистки прежних данных; для очистки используется отдельный `erase_test_data()`. |
| `address` | `address_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `product_category` | `product_category_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `courier` | `courier_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `restaurant` | `restaurant_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `product` | `product_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `order` | `order_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `payment` | `payment_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `review` | `review_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 требует серверную генерацию UUID. |
| `courier` | `coefficient` | `DEFAULT 0.10` | BR-6.5 задаёт начальный коэффициент нового курьера. |
| `order` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10,2)) STORED` | BR-1.4 и BR-7.10 задают комиссию 10%; вычисление исключает независимый ввод неправильной комиссии. |
| `order` | `total_amount` | `GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10,2)) STORED` | BR-7.10 требует сумму блюд с комиссией; формула не ссылается на другой GENERATED-столбец. |

---

## Нормализация (3НФ)

Данные клиента, адреса, ресторана, категории и блюда разделены по сущностям. Несколько адресов клиента представлены строками `client_address`, позиции — строками `order_structure`, выплаты — строками `courier_pay`. Составной `courier_pay_pkey (year,month,courier_id)` определяет одну выплату курьеру за конкретный месяц по BR-10.3.

Особые случаи:

- `order.commission` вычисляется как 10% от суммы заказа по BR-1.4 и BR-7.10. GENERATED исключает независимый ввод неправильной комиссии.
- `order.total_amount` вычисляется из суммы блюд и комиссии по BR-7.10; его значение не вводится независимо.
- `product.rating` и `restaurant.rating` — осознанно хранимые агрегаты по BR-9.6–9.7. Функция `rating_change()` из `08_rating_change.sql` пересчитывает среднее после изменения отзывов. Обработчики из `15_aggregate_integrity.sql` поддерживают NULL после TRUNCATE review и правильное среднее при прямой записи рейтинга. Без отзывов сохраняется NULL.
- `review.entity_type`/`entity_id` задают одну полиморфную цель. Разные типы цели не создают функциональную зависимость одного неключевого атрибута от другого; ссылочная корректность обеспечена проверками из ловушки 4.

В текущей структуре остаются два исключения относительно требования 3НФ: `review.order_id → review.client_id` и `payment.order_id → payment.amount`. Клиент и итог уже определены заказом, но повторно хранятся в отзыве и попытке оплаты согласно исходной ERD и атрибутам BR-8.2. Составные FK обеспечивают совпадение копий по BR-9.2 и BR-8.4, но не устраняют эти зависимости. Поэтому полное соответствие всех таблиц 3НФ для сохранённой структуры не заявляется.
