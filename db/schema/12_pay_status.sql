-- BR-8.7
CREATE OR REPLACE FUNCTION melnikov_food.update_order_pay_status()
RETURNS trigger AS $$
DECLARE
    v_total bigint;
    v_success bigint;
    v_processing bigint;
    v_old_order_id uuid;
    v_new_order_id uuid;
    v_order_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'order' THEN
        SELECT count(*),
               count(*) FILTER (WHERE p.status = 'успех'),
               count(*) FILTER (WHERE p.status = 'в_обработке')
        INTO v_total, v_success, v_processing
        FROM melnikov_food.payment p
        WHERE p.order_id = NEW.order_id;

        NEW.pay_status := (CASE
            WHEN v_success > 0 THEN 'оплачен'
            WHEN v_processing > 0 THEN 'ожидает'
            WHEN v_total > 0 THEN 'ошибка'
            ELSE 'ожидает'
        END)::melnikov_food.order_pay_status;
        RETURN NEW;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        v_old_order_id := OLD.order_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        v_new_order_id := NEW.order_id;
    END IF;

    FOR v_order_id IN
        SELECT t.order_id
        FROM (
            SELECT v_old_order_id AS order_id
            UNION
            SELECT v_new_order_id
        ) t
        WHERE t.order_id IS NOT NULL
        ORDER BY t.order_id
    LOOP
        UPDATE melnikov_food."order" o
        SET pay_status = o.pay_status
        WHERE o.order_id = v_order_id;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_pay_status_calc_trg
BEFORE INSERT OR UPDATE OF order_id, pay_status ON melnikov_food."order"
FOR EACH ROW EXECUTE FUNCTION melnikov_food.update_order_pay_status();

CREATE TRIGGER payment_pay_status_change_trg
AFTER INSERT OR UPDATE OF order_id, status OR DELETE ON melnikov_food.payment
FOR EACH ROW EXECUTE FUNCTION melnikov_food.update_order_pay_status();

UPDATE melnikov_food."order" o SET pay_status = o.pay_status;
