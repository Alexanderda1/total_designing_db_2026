-- BR-8.7, BR-9.2, BR-9.6–9.7
CREATE OR REPLACE FUNCTION melnikov_food.sync_after_truncate()
RETURNS trigger AS $$
BEGIN
    IF TG_TABLE_NAME = 'payment' THEN
        UPDATE melnikov_food."order" SET pay_status = pay_status;
    ELSIF TG_TABLE_NAME = 'review' THEN
        UPDATE melnikov_food.product SET rating = NULL;
        UPDATE melnikov_food.restaurant SET rating = NULL;
    ELSIF TG_TABLE_NAME = 'order_structure' THEN
        IF EXISTS (
            SELECT 1
            FROM melnikov_food.review r
            WHERE r.entity_type = 'блюдо'
              AND NOT EXISTS (
                  SELECT 1 FROM melnikov_food.order_structure s
                  WHERE s.order_id = r.order_id AND s.product_id = r.entity_id
              )
        ) THEN
            RAISE EXCEPTION 'Нельзя удалить из заказа блюдо, на которое есть отзыв (BR-9.2)';
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER payment_status_truncate_trg
AFTER TRUNCATE ON melnikov_food.payment
FOR EACH STATEMENT EXECUTE FUNCTION melnikov_food.sync_after_truncate();

CREATE TRIGGER review_rating_truncate_trg
AFTER TRUNCATE ON melnikov_food.review
FOR EACH STATEMENT EXECUTE FUNCTION melnikov_food.sync_after_truncate();

CREATE TRIGGER order_structure_review_truncate_trg
AFTER TRUNCATE ON melnikov_food.order_structure
FOR EACH STATEMENT EXECUTE FUNCTION melnikov_food.sync_after_truncate();

CREATE OR REPLACE FUNCTION melnikov_food.calculate_rating_before_write()
RETURNS trigger AS $$
BEGIN
    IF TG_TABLE_NAME = 'product' THEN
        SELECT round(avg(r.rating), 2) INTO NEW.rating
        FROM melnikov_food.review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = NEW.product_id;
    ELSE
        SELECT round(avg(r.rating), 2) INTO NEW.rating
        FROM melnikov_food.review r
        WHERE r.entity_type = 'ресторан' AND r.entity_id = NEW.restaurant_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER product_rating_value_trg
BEFORE INSERT OR UPDATE OF rating ON melnikov_food.product
FOR EACH ROW EXECUTE FUNCTION melnikov_food.calculate_rating_before_write();

CREATE TRIGGER restaurant_rating_value_trg
BEFORE INSERT OR UPDATE OF rating ON melnikov_food.restaurant
FOR EACH ROW EXECUTE FUNCTION melnikov_food.calculate_rating_before_write();
