-- FOOD-102:
CREATE OR REPLACE PROCEDURE melnikov_food.insert_test_data(value integer)
AS $$
DECLARE
    v_alphabet text := 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
    v_categories uuid[] := ARRAY[]::uuid[];
    v_clients uuid[] := ARRAY[]::uuid[];
    v_couriers uuid[] := ARRAY[]::uuid[];
    v_addresses uuid[] := ARRAY[]::uuid[];
    v_restaurants uuid[] := ARRAY[]::uuid[];
    v_menu uuid[];
    v_available uuid[];
    v_selected uuid[];
    v_quantities numeric[];
    v_restaurant_statuses melnikov_food.restaurant_status[] := enum_range(NULL::melnikov_food.restaurant_status);
    v_product_statuses melnikov_food.product_status[] := enum_range(NULL::melnikov_food.product_status);
    v_courier_statuses melnikov_food.courier_status[] := enum_range(NULL::melnikov_food.courier_status);
    v_order_statuses melnikov_food.order_status[] := enum_range(NULL::melnikov_food.order_status);
    v_order_pay_statuses melnikov_food.order_pay_status[] := enum_range(NULL::melnikov_food.order_pay_status);
    v_payment_statuses melnikov_food.payment_status[] := enum_range(NULL::melnikov_food.payment_status);
    v_payment_types melnikov_food.payment_type[] := enum_range(NULL::melnikov_food.payment_type);
    v_review_types melnikov_food.review_entity_type[] := enum_range(NULL::melnikov_food.review_entity_type);
    v_first_date date := greatest(date_trunc('month', current_date - interval '5 months')::date, current_date - 179);
    v_i integer;
    v_j integer;
    v_k integer;
    v_index integer;
    v_client_index integer;
    v_item_count integer;
    v_id uuid;
    v_client_id uuid;
    v_courier_id uuid;
    v_order_id uuid;
    v_product_id uuid;
    v_entity_id uuid;
    v_login varchar(50);
    v_phone varchar(20);
    v_street varchar(150);
    v_house varchar(20);
    v_apartment varchar(20);
    v_transaction_reference text;
    v_courier_status melnikov_food.courier_status;
    v_order_status melnikov_food.order_status;
    v_review_type melnikov_food.review_entity_type;
    v_hire_date date;
    v_dismissal_date date;
    v_last_date date;
    v_work_start time;
    v_work_end time;
    v_order_at timestamp;
    v_delivery_at timestamp;
    v_price numeric;
    v_quantity numeric;
    v_sum numeric;
    v_order_amount numeric;
    v_total_amount numeric;
    v_month record;
    v_coefficient numeric;
    v_delivered bigint;
    v_commission_sum numeric;
BEGIN
    IF value IS NULL OR value <= 0 THEN
        RAISE EXCEPTION 'Параметр value должен быть положительным целым числом';
    END IF;

    -- Разделы 1, 2, 3, 5, 6, 7:
    FOR v_i IN 1..value LOOP
        INSERT INTO melnikov_food.product_category(product_category_name)
        VALUES (repeat(substring(v_alphabet, 1, 1 + floor(random() * 33)::int),
                       1 + floor(random() * 3)::int))
        RETURNING product_category_id INTO v_id;
        v_categories := array_append(v_categories, v_id);

        LOOP
            v_login := substring(md5(random()::text), 1, 1 + floor(random() * 32)::int);
            v_phone := '+7' || (9000000000::bigint + floor(random() * 1000000000)::bigint)::text;
            v_id := NULL;
            INSERT INTO melnikov_food.client(login, password, phone_number)
            VALUES (v_login, md5(random()::text), v_phone)
            ON CONFLICT DO NOTHING
            RETURNING client_id INTO v_id;
            EXIT WHEN v_id IS NOT NULL;
        END LOOP;
        v_clients := array_append(v_clients, v_id);

        v_courier_status := v_courier_statuses[1 + floor(random() * cardinality(v_courier_statuses))::int];
        IF v_i = 1 THEN
            v_courier_status := v_courier_statuses[1];
            v_hire_date := v_first_date;
        ELSE
            v_hire_date := v_first_date + floor(random() * (current_date - v_first_date))::int;
        END IF;
        v_dismissal_date := NULL;
        IF v_courier_status = 'уволен' THEN
            v_dismissal_date := v_hire_date + floor(random() * (current_date - v_hire_date))::int;
        END IF;

        INSERT INTO melnikov_food.courier(fio, phone_number, status, hire_date, dismissal_date)
        VALUES (
            substring(v_alphabet, 1, 1 + floor(random() * 33)::int) || ' ' ||
            substring(v_alphabet, 1, 1 + floor(random() * 33)::int) || ' ' ||
            substring(v_alphabet, 1, 1 + floor(random() * 33)::int),
            '+7' || (9000000000::bigint + floor(random() * 1000000000)::bigint)::text,
            v_courier_status, v_hire_date, v_dismissal_date
        )
        RETURNING courier_id INTO v_id;
        v_couriers := array_append(v_couriers, v_id);
    END LOOP;

    -- Разделы 2, 5, 7d:
    FOR v_i IN 1..(value * 5) LOOP
        LOOP
            v_street := repeat(substring(v_alphabet, 1, 1 + floor(random() * 33)::int),
                               1 + floor(random() * 3)::int);
            v_house := (1 + floor(random() * 500)::int)::text;
            v_apartment := CASE WHEN random() < 0.25 THEN NULL
                                ELSE (1 + floor(random() * 200)::int)::text END;
            EXIT WHEN NOT EXISTS (
                SELECT 1 FROM melnikov_food.address a
                WHERE a.street = v_street AND a.house_number = v_house
                  AND (a.apartment_office = v_apartment
                       OR (a.apartment_office IS NULL AND v_apartment IS NULL))
            );
        END LOOP;
        INSERT INTO melnikov_food.address(street, house_number, apartment_office)
        VALUES (v_street, v_house, v_apartment)
        RETURNING address_id INTO v_id;
        v_addresses := array_append(v_addresses, v_id);
    END LOOP;

    -- Разделы 4, 7, 8a, 11:
    FOR v_i IN 1..value LOOP
        v_work_start := time '08:00' + floor(random() * 4)::int * interval '1 hour';
        v_work_end := v_work_start + (8 + floor(random() * 4)::int) * interval '1 hour';
        INSERT INTO melnikov_food.restaurant(
            restaurant_name, address_id, description, work_start, work_end,
            company_details, rating, status
        ) VALUES (
            repeat(substring(v_alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int),
            v_addresses[v_i], md5(random()::text), v_work_start, v_work_end,
            md5(random()::text), NULL,
            v_restaurant_statuses[1 + floor(random() * cardinality(v_restaurant_statuses))::int]
        )
        RETURNING restaurant_id INTO v_id;
        v_restaurants := array_append(v_restaurants, v_id);

        FOR v_j IN 1..4 LOOP
            INSERT INTO melnikov_food.client_address(client_id, address_id)
            VALUES (v_clients[v_i], v_addresses[value + (v_i - 1) * 4 + v_j]);
        END LOOP;

        FOR v_j IN 1..5 LOOP
            INSERT INTO melnikov_food.product(
                product_name, product_category_id, price, restaurant_id,
                photo_url, rating, status, description
            ) VALUES (
                repeat(substring(v_alphabet, 1, 1 + floor(random() * 33)::int), 1 + floor(random() * 3)::int),
                v_categories[1 + floor(random() * cardinality(v_categories))::int],
                round((100 + random() * 900)::numeric, 2), v_id,
                CASE WHEN random() < 0.3 THEN NULL
                     ELSE 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,
                NULL, v_product_statuses[1 + floor(random() * cardinality(v_product_statuses))::int],
                md5(random()::text)
            );
        END LOOP;
    END LOOP;

    -- Разделы 5, 7, 8b:
    FOR v_i IN 1..value LOOP
        SELECT array_agg(p.product_id ORDER BY p.product_id) INTO v_menu
        FROM melnikov_food.product p WHERE p.restaurant_id = v_restaurants[v_i];

        FOR v_j IN 1..5 LOOP
            LOOP
                v_available := v_menu;
                v_selected := ARRAY[]::uuid[];
                v_quantities := ARRAY[]::numeric[];
                v_sum := 0;
                v_item_count := 1 + floor(random() * least(5, cardinality(v_menu)))::int;
                FOR v_k IN 1..v_item_count LOOP
                    v_index := 1 + floor(random() * cardinality(v_available))::int;
                    v_product_id := v_available[v_index];
                    v_available := array_remove(v_available, v_product_id);
                    v_quantity := round((0.1 + random() * 4.9)::numeric, 3);
                    SELECT p.price INTO v_price FROM melnikov_food.product p
                    WHERE p.product_id = v_product_id;
                    v_selected := array_append(v_selected, v_product_id);
                    v_quantities := array_append(v_quantities, v_quantity);
                    v_sum := v_sum + v_price * v_quantity;
                END LOOP;
                v_order_amount := round(v_sum, 2);
                EXIT WHEN v_order_amount + round(v_order_amount * 0.10, 2) >= 1000;
            END LOOP;

            v_client_index := 1 + floor(random() * cardinality(v_clients))::int;
            v_client_id := v_clients[v_client_index];
            v_courier_id := v_couriers[1 + floor(random() * cardinality(v_couriers))::int];
            SELECT c.hire_date, c.dismissal_date INTO v_hire_date, v_dismissal_date
            FROM melnikov_food.courier c WHERE c.courier_id = v_courier_id;
            v_last_date := coalesce(v_dismissal_date, current_date - 1);
            v_order_at := (v_last_date - floor(random() * (v_last_date - v_hire_date + 1))::int)
                          + time '12:00' + floor(random() * 120)::int * interval '1 minute';
            v_order_status := v_order_statuses[1 + floor(random() * cardinality(v_order_statuses))::int];
            v_delivery_at := NULL;
            IF v_order_status = 'доставлен' THEN
                v_delivery_at := v_order_at + (1 + floor(random() * 120)::int) * interval '1 minute';
            END IF;

            INSERT INTO melnikov_food."order"(
                courier_id, client_id, address_id, restaurant_id, order_timestamp,
                delivery_timestamp, order_amount, status, pay_status, description
            ) VALUES (
                v_courier_id, v_client_id,
                v_addresses[value + (v_client_index - 1) * 4 + 1 + floor(random() * 4)::int],
                v_restaurants[v_i], v_order_at, v_delivery_at, v_order_amount,
                v_order_status, v_order_pay_statuses[1], md5(random()::text)
            )
            RETURNING order_id, total_amount INTO v_order_id, v_total_amount;

            FOR v_k IN 1..cardinality(v_selected) LOOP
                INSERT INTO melnikov_food.order_structure(order_id, product_id, quantity)
                VALUES (v_order_id, v_selected[v_k], v_quantities[v_k]);
            END LOOP;

            -- Раздел 8c:
            -- BR-11.7, BR-8.1
            LOOP
                v_transaction_reference := md5(random()::text);
                v_id := NULL;
                INSERT INTO melnikov_food.payment(
                    order_id, pay_type, amount, transaction_reference, transaction_timestamp, status
                ) VALUES (
                    v_order_id, v_payment_types[1 + floor(random() * cardinality(v_payment_types))::int],
                    v_total_amount, v_transaction_reference,
                    v_order_at + (1 + floor(random() * 60)::int) * interval '1 minute',
                    v_payment_statuses[1]
                )
                ON CONFLICT (transaction_reference) DO NOTHING
                RETURNING payment_id INTO v_id;
                EXIT WHEN v_id IS NOT NULL;
            END LOOP;
            UPDATE melnikov_food."order" SET pay_status = v_order_pay_statuses[2]
            WHERE order_id = v_order_id;

            v_review_type := v_review_types[1 + floor(random() * cardinality(v_review_types))::int];
            IF v_review_type = 'блюдо' THEN
                v_entity_id := v_selected[1 + floor(random() * cardinality(v_selected))::int];
            ELSIF v_review_type = 'ресторан' THEN
                v_entity_id := v_restaurants[v_i];
            ELSE
                v_entity_id := v_order_id;
            END IF;
            INSERT INTO melnikov_food.review(
                client_id, review_timestamp, entity_id, entity_type, order_id,
                description, photo_url, rating
            ) VALUES (
                v_client_id, v_order_at + (120 + floor(random() * 481)::int) * interval '1 minute',
                v_entity_id, v_review_type, v_order_id, md5(random()::text),
                CASE WHEN random() < 0.3 THEN NULL
                     ELSE 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,
                round((1 + random() * 4)::numeric, 2)
            );
        END LOOP;
    END LOOP;

    -- Раздел 9:
    FOR v_i IN 1..value LOOP
        v_courier_id := v_couriers[v_i];
        SELECT c.dismissal_date INTO v_dismissal_date
        FROM melnikov_food.courier c WHERE c.courier_id = v_courier_id;
        v_coefficient := 0.1;
        FOR v_month IN
            SELECT m::date AS month_start
            FROM generate_series(
                date_trunc('month', current_date - interval '5 months'),
                date_trunc('month', current_date), interval '1 month'
            ) m
        LOOP
            SELECT count(*), coalesce(sum(o.commission), 0)
            INTO v_delivered, v_commission_sum
            FROM melnikov_food."order" o
            WHERE o.courier_id = v_courier_id AND o.status = 'доставлен'
              AND o.order_timestamp >= v_month.month_start
              AND o.order_timestamp < v_month.month_start + interval '1 month';

            INSERT INTO melnikov_food.courier_pay(year, month, courier_id, amount, coefficient_used)
            VALUES (
                extract(year FROM v_month.month_start)::int,
                extract(month FROM v_month.month_start)::int, v_courier_id,
                round(v_coefficient * v_commission_sum, 2), v_coefficient
            );

            IF v_dismissal_date IS NULL
               OR v_dismissal_date >= (v_month.month_start + interval '1 month')::date THEN
                v_coefficient := CASE
                    WHEN v_delivered <= 150 THEN 0.1
                    WHEN v_delivered <= 250 THEN 0.2
                    WHEN v_delivered <= 500 THEN 0.3
                    ELSE 0.5
                END;
            END IF;
        END LOOP;
        UPDATE melnikov_food.courier SET coefficient = v_coefficient
        WHERE courier_id = v_courier_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
