-- FOOD-107:
-- BR-10.2–10.6
CREATE OR REPLACE PROCEDURE melnikov_food.courier_salary()
AS $$
DECLARE
    v_month_start date := date_trunc('month', current_date)::date;
    v_month_end date := (v_month_start + interval '1 month')::date;
    v_year integer := extract(year FROM v_month_start)::int;
    v_month integer := extract(month FROM v_month_start)::int;
    v_courier record;
    v_delivered bigint;
    v_commission_sum numeric;
    v_applied_coefficient numeric;
BEGIN
    FOR v_courier IN
        SELECT c.courier_id, c.status, c.coefficient
        FROM melnikov_food.courier c
        ORDER BY c.courier_id
        FOR UPDATE
    LOOP
        SELECT count(*), coalesce(sum(o.commission), 0)
        INTO v_delivered, v_commission_sum
        FROM melnikov_food."order" o
        WHERE o.courier_id = v_courier.courier_id
          AND o.status = 'доставлен'
          AND o.order_timestamp >= v_month_start
          AND o.order_timestamp < v_month_end;

        SELECT p.coefficient_used INTO v_applied_coefficient
        FROM melnikov_food.courier_pay p
        WHERE p.year = v_year AND p.month = v_month
          AND p.courier_id = v_courier.courier_id;

        IF v_applied_coefficient IS NULL THEN
            v_applied_coefficient := v_courier.coefficient;
            INSERT INTO melnikov_food.courier_pay(
                year, month, courier_id, amount, coefficient_used
            ) VALUES (
                v_year, v_month, v_courier.courier_id,
                round(v_applied_coefficient * v_commission_sum, 2),
                v_applied_coefficient
            );
        ELSE
            UPDATE melnikov_food.courier_pay p
            SET amount = round(v_applied_coefficient * v_commission_sum, 2)
            WHERE p.year = v_year AND p.month = v_month
              AND p.courier_id = v_courier.courier_id;
        END IF;

        IF v_courier.status <> 'уволен' THEN
            UPDATE melnikov_food.courier
            SET coefficient = CASE
                WHEN v_delivered <= 150 THEN 0.1
                WHEN v_delivered <= 250 THEN 0.2
                WHEN v_delivered <= 500 THEN 0.3
                ELSE 0.5
            END
            WHERE courier_id = v_courier.courier_id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
