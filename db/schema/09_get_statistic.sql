-- FOOD-106:
-- BR-11.8, BR-13.2
CREATE OR REPLACE FUNCTION melnikov_food.get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
AS $$
BEGIN
    RETURN QUERY
    WITH delivered_orders AS MATERIALIZED (
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
        FROM melnikov_food."order" o
        WHERE o.status = 'доставлен'
    ),
    order_totals AS (
        SELECT d.restaurant_id, sum(d.total_amount) AS sum_amount,
               avg(d.total_amount) AS mean_amount
        FROM delivered_orders d
        GROUP BY d.restaurant_id
    ),
    product_quantities AS (
        SELECT d.restaurant_id, s.product_id, sum(s.quantity) AS quantity_sold
        FROM delivered_orders d
        JOIN melnikov_food.order_structure s ON s.order_id = d.order_id
        GROUP BY d.restaurant_id, s.product_id
    ),
    best_products AS (
        SELECT DISTINCT ON (q.restaurant_id) q.restaurant_id, q.product_id
        FROM product_quantities q
        ORDER BY q.restaurant_id, q.quantity_sold DESC, random()
    ),
    client_counts AS (
        SELECT d.restaurant_id, d.client_id, count(*) AS order_count
        FROM delivered_orders d
        GROUP BY d.restaurant_id, d.client_id
    ),
    best_clients AS (
        SELECT DISTINCT ON (c.restaurant_id) c.restaurant_id, c.client_id
        FROM client_counts c
        ORDER BY c.restaurant_id, c.order_count DESC, random()
    )
    SELECT r.restaurant_name, p.product_name, coalesce(t.sum_amount, 0),
           t.mean_amount, c.login
    FROM melnikov_food.restaurant r
    LEFT JOIN order_totals t ON t.restaurant_id = r.restaurant_id
    LEFT JOIN best_products bp ON bp.restaurant_id = r.restaurant_id
    LEFT JOIN melnikov_food.product p ON p.product_id = bp.product_id
    LEFT JOIN best_clients bc ON bc.restaurant_id = r.restaurant_id
    LEFT JOIN melnikov_food.client c ON c.client_id = bc.client_id;
END;
$$ LANGUAGE plpgsql;
