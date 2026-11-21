-- FOOD-101:
-- BR-9.2, BR-8.4, BR-8.1, BR-7.3

ALTER TABLE melnikov_food."order"
    ADD CONSTRAINT order_client_pair_unique UNIQUE (order_id, client_id);

ALTER TABLE melnikov_food."order"
    ADD CONSTRAINT order_total_pair_unique UNIQUE (order_id, total_amount);

-- BR-9.2
ALTER TABLE melnikov_food.review
    ADD CONSTRAINT review_order_client_fk
    FOREIGN KEY (order_id, client_id)
    REFERENCES melnikov_food."order" (order_id, client_id);

-- BR-8.4
ALTER TABLE melnikov_food.payment
    ADD CONSTRAINT payment_order_amount_fk
    FOREIGN KEY (order_id, amount)
    REFERENCES melnikov_food."order" (order_id, total_amount);

-- BR-8.1
CREATE UNIQUE INDEX payment_one_success_per_order_idx
    ON melnikov_food.payment (order_id)
    WHERE status = 'успех';

-- BR-7.3
CREATE OR REPLACE FUNCTION melnikov_food.check_order_restaurant()
RETURNS trigger AS $$
DECLARE
    v_order_restaurant uuid;
    v_product_restaurant uuid;
BEGIN
    IF TG_TABLE_NAME = 'order_structure' THEN
        SELECT restaurant_id INTO v_order_restaurant
        FROM melnikov_food."order"
        WHERE order_id = NEW.order_id
        FOR SHARE;

        SELECT restaurant_id INTO v_product_restaurant
        FROM melnikov_food.product
        WHERE product_id = NEW.product_id
        FOR SHARE;

        IF v_order_restaurant <> v_product_restaurant THEN
            RAISE EXCEPTION
                'Блюдо не принадлежит ресторану заказа (BR-7.3)';
        END IF;

    ELSIF TG_TABLE_NAME = 'order' THEN
        IF NEW.restaurant_id <> OLD.restaurant_id AND EXISTS (
            SELECT 1
            FROM melnikov_food.order_structure s
            JOIN melnikov_food.product p ON p.product_id = s.product_id
            WHERE s.order_id = OLD.order_id
              AND p.restaurant_id <> NEW.restaurant_id
        ) THEN
            RAISE EXCEPTION
                'Нельзя сменить ресторан заказа: его позиции содержат блюда другого ресторана (BR-7.3)';
        END IF;

    ELSIF TG_TABLE_NAME = 'product' THEN
        IF NEW.restaurant_id <> OLD.restaurant_id AND EXISTS (
            SELECT 1
            FROM melnikov_food.order_structure s
            JOIN melnikov_food."order" o ON o.order_id = s.order_id
            WHERE s.product_id = OLD.product_id
              AND o.restaurant_id <> NEW.restaurant_id
        ) THEN
            RAISE EXCEPTION
                'Нельзя сменить ресторан блюда: оно используется в заказах другого ресторана (BR-7.3)';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_structure_restaurant_check_trg
BEFORE INSERT OR UPDATE OF order_id, product_id
ON melnikov_food.order_structure
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_order_restaurant();

CREATE TRIGGER order_restaurant_check_trg
BEFORE UPDATE OF restaurant_id ON melnikov_food."order"
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_order_restaurant();

CREATE TRIGGER product_restaurant_check_trg
BEFORE UPDATE OF restaurant_id ON melnikov_food.product
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_order_restaurant();

-- BR-9.1, BR-9.2
CREATE OR REPLACE FUNCTION melnikov_food.check_review_entity()
RETURNS trigger AS $$
DECLARE
    v_order_restaurant uuid;
    v_product uuid;
    v_remove_position boolean := false;
BEGIN
    IF TG_TABLE_NAME = 'review' THEN
        IF NEW.order_id IS NULL OR NEW.entity_id IS NULL
           OR NEW.entity_type IS NULL THEN
            RETURN NEW;
        END IF;

        SELECT restaurant_id INTO v_order_restaurant
        FROM melnikov_food."order"
        WHERE order_id = NEW.order_id
        FOR SHARE;

        IF v_order_restaurant IS NULL THEN
            RETURN NEW;
        END IF;

        IF NEW.entity_type = 'блюдо' THEN
            SELECT product_id INTO v_product
            FROM melnikov_food.order_structure
            WHERE order_id = NEW.order_id
              AND product_id = NEW.entity_id
            FOR SHARE;

            IF v_product IS NULL THEN
                RAISE EXCEPTION
                    'Отзыв можно оставить только на блюдо из указанного заказа (BR-9.2)';
            END IF;
        ELSIF NEW.entity_type = 'ресторан' THEN
            IF NEW.entity_id <> v_order_restaurant THEN
                RAISE EXCEPTION
                    'Ресторан отзыва не совпадает с рестораном заказа (BR-9.2)';
            END IF;
        ELSIF NEW.entity_type = 'заказ' THEN
            IF NEW.entity_id <> NEW.order_id THEN
                RAISE EXCEPTION
                    'Отзыв должен относиться к указанному заказу (BR-9.2)';
            END IF;
        END IF;

    ELSIF TG_TABLE_NAME = 'order_structure' THEN
        IF TG_OP = 'DELETE' THEN
            v_remove_position := true;
        ELSE
            v_remove_position := NEW.order_id <> OLD.order_id
                                 OR NEW.product_id <> OLD.product_id;
        END IF;

        IF v_remove_position AND EXISTS (
            SELECT 1
            FROM melnikov_food.review r
            WHERE r.order_id = OLD.order_id
              AND r.entity_type = 'блюдо'
              AND r.entity_id = OLD.product_id
        ) THEN
            RAISE EXCEPTION
                'Нельзя удалить или заменить позицию, на которую есть отзыв (BR-9.2)';
        END IF;

        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;

    ELSIF TG_TABLE_NAME = 'order' THEN
        IF NEW.restaurant_id <> OLD.restaurant_id AND EXISTS (
            SELECT 1
            FROM melnikov_food.review r
            WHERE r.order_id = OLD.order_id
              AND r.entity_type = 'ресторан'
              AND r.entity_id <> NEW.restaurant_id
        ) THEN
            RAISE EXCEPTION
                'Нельзя сменить ресторан заказа, если это нарушит связь с отзывом (BR-9.2)';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER review_entity_check_trg
BEFORE INSERT OR UPDATE OF order_id, entity_id, entity_type
ON melnikov_food.review
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_review_entity();

CREATE TRIGGER order_structure_review_check_trg
BEFORE DELETE OR UPDATE OF order_id, product_id
ON melnikov_food.order_structure
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_review_entity();

CREATE TRIGGER order_review_entity_check_trg
BEFORE UPDATE OF restaurant_id ON melnikov_food."order"
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_review_entity();
