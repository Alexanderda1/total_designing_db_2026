-- FOOD-104:
-- BR-9.7
CREATE OR REPLACE PROCEDURE melnikov_food.add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar(150),
    p_price numeric(12,2),
    p_rating numeric(3,2),
    p_status melnikov_food.product_status,
    p_description text,
    p_photo_url text DEFAULT NULL
)
AS $$
BEGIN
    IF p_restaurant_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM melnikov_food.restaurant
        WHERE restaurant_id = p_restaurant_id
    ) THEN
        RAISE EXCEPTION 'Ресторан с ID % не существует', p_restaurant_id;
    END IF;

    IF p_product_category_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM melnikov_food.product_category
        WHERE product_category_id = p_product_category_id
    ) THEN
        RAISE EXCEPTION 'Категория блюд с ID % не существует', p_product_category_id;
    END IF;

    IF p_price < 0 THEN
        RAISE EXCEPTION 'Цена блюда не может быть отрицательной';
    END IF;

    IF p_rating IS NOT NULL THEN
        RAISE EXCEPTION 'Рейтинг нового блюда должен быть NULL: без отзывов рейтинг отсутствует (BR-9.7)';
    END IF;

    INSERT INTO melnikov_food.product(
        product_name, product_category_id, price, restaurant_id,
        photo_url, rating, status, description
    ) VALUES (
        p_name, p_product_category_id, p_price, p_restaurant_id,
        p_photo_url, p_rating, p_status, p_description
    );
END;
$$ LANGUAGE plpgsql;
