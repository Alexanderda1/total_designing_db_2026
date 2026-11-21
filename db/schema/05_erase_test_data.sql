-- FOOD-103:
CREATE OR REPLACE PROCEDURE melnikov_food.erase_test_data()
AS $$
BEGIN
    TRUNCATE TABLE
        melnikov_food.review,
        melnikov_food.payment,
        melnikov_food.order_structure,
        melnikov_food.courier_pay,
        melnikov_food.client_address,
        melnikov_food."order",
        melnikov_food.product,
        melnikov_food.restaurant,
        melnikov_food.courier,
        melnikov_food.product_category,
        melnikov_food.client,
        melnikov_food.address;
END;
$$ LANGUAGE plpgsql;
