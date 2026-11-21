-- FOOD-105:
-- BR-9.6–9.7
CREATE OR REPLACE FUNCTION melnikov_food.rating_change()
RETURNS trigger AS $$
DECLARE
    v_old_type melnikov_food.review_entity_type;
    v_old_id uuid;
    v_new_type melnikov_food.review_entity_type;
    v_new_id uuid;
    v_target record;
    v_locked_id uuid;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        v_old_type := OLD.entity_type;
        v_old_id := OLD.entity_id;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        v_new_type := NEW.entity_type;
        v_new_id := NEW.entity_id;
    END IF;

    FOR v_target IN
        SELECT t.entity_type, t.entity_id
        FROM (
            SELECT v_old_type AS entity_type, v_old_id AS entity_id
            UNION
            SELECT v_new_type, v_new_id
        ) t
        WHERE t.entity_type IN ('блюдо', 'ресторан')
          AND t.entity_id IS NOT NULL
        ORDER BY t.entity_type, t.entity_id
    LOOP
        IF v_target.entity_type = 'блюдо' THEN
            SELECT product_id INTO v_locked_id
            FROM melnikov_food.product
            WHERE product_id = v_target.entity_id
            FOR UPDATE;

            UPDATE melnikov_food.product
            SET rating = (
                SELECT round(avg(r.rating), 2)
                FROM melnikov_food.review r
                WHERE r.entity_type = 'блюдо'
                  AND r.entity_id = v_target.entity_id
            )
            WHERE product_id = v_locked_id;

        ELSIF v_target.entity_type = 'ресторан' THEN
            SELECT restaurant_id INTO v_locked_id
            FROM melnikov_food.restaurant
            WHERE restaurant_id = v_target.entity_id
            FOR UPDATE;

            UPDATE melnikov_food.restaurant
            SET rating = (
                SELECT round(avg(r.rating), 2)
                FROM melnikov_food.review r
                WHERE r.entity_type = 'ресторан'
                  AND r.entity_id = v_target.entity_id
            )
            WHERE restaurant_id = v_locked_id;
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER review_rating_change_trg
AFTER INSERT OR UPDATE OR DELETE ON melnikov_food.review
FOR EACH ROW EXECUTE FUNCTION melnikov_food.rating_change();
