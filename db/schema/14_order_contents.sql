-- BR-7.10, BR-7.14
CREATE OR REPLACE FUNCTION melnikov_food.check_order_contents()
RETURNS trigger AS $$
DECLARE
    v_old_id uuid;
    v_new_id uuid;
    v_order_id uuid;
    v_order_amount numeric;
    v_contents_amount numeric;
    v_count bigint;
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        UPDATE melnikov_food."order" SET order_amount = order_amount;
        RETURN NULL;
    END IF;

    IF TG_TABLE_NAME = 'product' THEN
        v_old_id := OLD.product_id;
        v_new_id := NEW.product_id;
    ELSE
        IF TG_OP <> 'INSERT' THEN
            v_old_id := OLD.order_id;
        END IF;
        IF TG_OP <> 'DELETE' THEN
            v_new_id := NEW.order_id;
        END IF;
    END IF;

    FOR v_order_id IN
        SELECT s.order_id
        FROM melnikov_food.order_structure s
        WHERE TG_TABLE_NAME = 'product'
          AND s.product_id IN (v_old_id, v_new_id)
        UNION
        SELECT v_old_id WHERE TG_TABLE_NAME <> 'product' AND v_old_id IS NOT NULL
        UNION
        SELECT v_new_id WHERE TG_TABLE_NAME <> 'product' AND v_new_id IS NOT NULL
        ORDER BY 1
    LOOP
        SELECT o.order_amount INTO v_order_amount
        FROM melnikov_food."order" o
        WHERE o.order_id = v_order_id
        FOR UPDATE;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        SELECT count(*), round(sum(p.price * s.quantity), 2)
        INTO v_count, v_contents_amount
        FROM melnikov_food.order_structure s
        JOIN melnikov_food.product p ON p.product_id = s.product_id
        WHERE s.order_id = v_order_id;

        IF v_count = 0 THEN
            RAISE EXCEPTION 'Заказ должен содержать хотя бы одну позицию (BR-7.14)';
        END IF;
        IF v_order_amount <> v_contents_amount THEN
            RAISE EXCEPTION 'Сумма заказа не соответствует стоимости его позиций (BR-7.10)';
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER order_contents_check_trg
AFTER INSERT OR UPDATE OF order_id, order_amount ON melnikov_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_order_contents();

CREATE TRIGGER order_structure_contents_truncate_trg
AFTER TRUNCATE ON melnikov_food.order_structure
FOR EACH STATEMENT EXECUTE FUNCTION melnikov_food.check_order_contents();

CREATE CONSTRAINT TRIGGER order_structure_contents_check_trg
AFTER INSERT OR UPDATE OR DELETE ON melnikov_food.order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_order_contents();

CREATE CONSTRAINT TRIGGER product_contents_check_trg
AFTER UPDATE OF price ON melnikov_food.product
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_order_contents();
