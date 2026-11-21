-- FOOD-108:
-- BR-11.9
CREATE OR REPLACE VIEW melnikov_food.how_much_money AS
WITH RECURSIVE order_months AS (
    SELECT date_trunc('month', o.order_timestamp)::date AS month_start,
           sum(o.order_amount) AS sum_no_commission,
           sum(o.total_amount) AS sum_with_commission
    FROM melnikov_food."order" o
    WHERE o.status = 'доставлен'
    GROUP BY date_trunc('month', o.order_timestamp)::date
),
bounds AS (
    SELECT min(o.month_start) AS first_month, max(o.month_start) AS last_month
    FROM order_months o
),
months(month_start) AS (
    SELECT b.first_month
    FROM bounds b
    WHERE b.first_month IS NOT NULL
    UNION ALL
    SELECT (m.month_start + interval '1 month')::date
    FROM months m
    CROSS JOIN bounds b
    WHERE m.month_start < b.last_month
),
salary_months AS (
    SELECT p.year, p.month, sum(p.amount) AS pay_amount
    FROM melnikov_food.courier_pay p
    GROUP BY p.year, p.month
),
amounts AS (
    SELECT m.month_start,
           coalesce(o.sum_no_commission, 0) AS sum_no_commission,
           coalesce(o.sum_with_commission, 0) AS sum_with_commission,
           coalesce(o.sum_with_commission - o.sum_no_commission, 0) AS commission,
           coalesce(s.pay_amount, 0) AS courier_pay
    FROM months m
    LEFT JOIN order_months o ON o.month_start = m.month_start
    LEFT JOIN salary_months s
        ON s.year = extract(year FROM m.month_start)
       AND s.month = extract(month FROM m.month_start)
),
with_previous AS (
    SELECT a.*, lag(a.commission, 1, NULL) OVER (ORDER BY a.month_start) AS prev_commission
    FROM amounts a
)
SELECT extract(year FROM a.month_start)::int::text || '-' ||
       CASE WHEN extract(month FROM a.month_start) < 10 THEN '0' ELSE '' END ||
       extract(month FROM a.month_start)::int::text AS year_month,
       a.sum_no_commission,
       a.sum_with_commission,
       a.commission,
       a.prev_commission,
       a.commission - a.prev_commission AS commission_diff,
       a.courier_pay,
       a.commission - a.courier_pay AS net_profit
FROM with_previous a;
