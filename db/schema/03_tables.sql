-- FOOD-101:

-- BR-2.1–2.3, BR-11.1, BR-11.3
CREATE TABLE melnikov_food.client (
    client_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    login varchar(50) NOT NULL,
    password varchar(32) NOT NULL,
    phone_number varchar(20) NOT NULL,
    CONSTRAINT client_login_unique UNIQUE (login),
    CONSTRAINT client_phone_number_unique UNIQUE (phone_number)
);

-- BR-3.1–3.2, BR-11.1, BR-11.3
CREATE TABLE melnikov_food.address (
    address_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    street varchar(150) NOT NULL,
    house_number varchar(20) NOT NULL,
    apartment_office varchar(20)
);

-- BR-5.7, BR-11.1, BR-11.3
CREATE TABLE melnikov_food.product_category (
    product_category_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    product_category_name varchar(100) NOT NULL
);

-- BR-6.1–6.5, BR-11.1, BR-11.3
CREATE TABLE melnikov_food.courier (
    courier_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    fio varchar(150) NOT NULL,
    phone_number varchar(20) NOT NULL,
    status melnikov_food.courier_status NOT NULL,
    hire_date date NOT NULL,
    dismissal_date date,
    coefficient numeric(3,2) DEFAULT 0.10 NOT NULL,
    CONSTRAINT courier_coefficient_check
        CHECK (coefficient BETWEEN 0.10 AND 0.50),
    CONSTRAINT courier_dismissed_date_check
        CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL),
    CONSTRAINT courier_dates_check
        CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)
);

-- BR-2.4–2.5
CREATE TABLE melnikov_food.client_address (
    client_id uuid NOT NULL,
    address_id uuid NOT NULL,
    CONSTRAINT client_address_pkey PRIMARY KEY (client_id, address_id),
    CONSTRAINT client_address_client_fk FOREIGN KEY (client_id)
        REFERENCES melnikov_food.client (client_id),
    CONSTRAINT client_address_address_fk FOREIGN KEY (address_id)
        REFERENCES melnikov_food.address (address_id)
);

-- BR-3.3–3.5, BR-4.1–4.5, BR-9.7, BR-11.1–11.3
CREATE TABLE melnikov_food.restaurant (
    restaurant_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    restaurant_name varchar(150) NOT NULL,
    address_id uuid NOT NULL,
    description text NOT NULL,
    work_start time NOT NULL,
    work_end time NOT NULL,
    company_details text NOT NULL,
    rating numeric(3,2),
    status melnikov_food.restaurant_status NOT NULL,
    CONSTRAINT restaurant_address_fk FOREIGN KEY (address_id)
        REFERENCES melnikov_food.address (address_id),
    CONSTRAINT restaurant_address_unique UNIQUE (address_id),
    CONSTRAINT restaurant_work_time_check CHECK (work_end > work_start),
    CONSTRAINT restaurant_rating_check CHECK (rating BETWEEN 0 AND 5)
);

-- BR-5.1–5.6, BR-9.7, BR-11.1, BR-11.3
CREATE TABLE melnikov_food.product (
    product_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    product_name varchar(150) NOT NULL,
    product_category_id uuid NOT NULL,
    price numeric(12,2) NOT NULL,
    restaurant_id uuid NOT NULL,
    photo_url text,
    rating numeric(3,2),
    status melnikov_food.product_status NOT NULL,
    description text NOT NULL,
    CONSTRAINT product_category_fk FOREIGN KEY (product_category_id)
        REFERENCES melnikov_food.product_category (product_category_id),
    CONSTRAINT product_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES melnikov_food.restaurant (restaurant_id),
    CONSTRAINT product_price_check CHECK (price >= 0),
    CONSTRAINT product_rating_check CHECK (rating BETWEEN 0 AND 5)
);

-- BR-10.2–10.4, BR-6.4, BR-11.3
CREATE TABLE melnikov_food.courier_pay (
    year integer NOT NULL,
    month integer NOT NULL,
    courier_id uuid NOT NULL,
    amount numeric(12,2) NOT NULL,
    coefficient_used numeric(3,2) NOT NULL,
    CONSTRAINT courier_pay_pkey PRIMARY KEY (year, month, courier_id),
    CONSTRAINT courier_pay_courier_fk FOREIGN KEY (courier_id)
        REFERENCES melnikov_food.courier (courier_id),
    CONSTRAINT courier_pay_month_check CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT courier_pay_amount_check CHECK (amount >= 0),
    CONSTRAINT courier_pay_coefficient_check
        CHECK (coefficient_used BETWEEN 0.10 AND 0.50)
);

-- BR-7.1–7.13, BR-11.1–11.3, BR-13.1
CREATE TABLE melnikov_food."order" (
    order_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    courier_id uuid NOT NULL,
    client_id uuid NOT NULL,
    address_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    order_timestamp timestamp NOT NULL,
    delivery_timestamp timestamp,
    order_amount numeric(12,2) NOT NULL,
    commission numeric(12,2) GENERATED ALWAYS AS
        (round(order_amount * 0.10, 2)) STORED NOT NULL,
    total_amount numeric(12,2) GENERATED ALWAYS AS
        (order_amount + round(order_amount * 0.10, 2)) STORED NOT NULL,
    status melnikov_food.order_status NOT NULL,
    pay_status melnikov_food.order_pay_status NOT NULL,
    description text NOT NULL,
    CONSTRAINT order_courier_fk FOREIGN KEY (courier_id)
        REFERENCES melnikov_food.courier (courier_id),
    CONSTRAINT order_client_fk FOREIGN KEY (client_id)
        REFERENCES melnikov_food.client (client_id),
    CONSTRAINT order_address_fk FOREIGN KEY (address_id)
        REFERENCES melnikov_food.address (address_id),
    CONSTRAINT order_restaurant_fk FOREIGN KEY (restaurant_id)
        REFERENCES melnikov_food.restaurant (restaurant_id),
    CONSTRAINT order_client_address_fk FOREIGN KEY (client_id, address_id)
        REFERENCES melnikov_food.client_address (client_id, address_id),
    CONSTRAINT order_minimum_total_check CHECK (total_amount >= 1000),
    CONSTRAINT order_delivery_time_check
        CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CONSTRAINT order_delivered_time_check
        CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL)
);

-- BR-7.14–7.16
CREATE TABLE melnikov_food.order_structure (
    order_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity numeric(12,3) NOT NULL,
    CONSTRAINT order_structure_pkey PRIMARY KEY (order_id, product_id),
    CONSTRAINT order_structure_order_fk FOREIGN KEY (order_id)
        REFERENCES melnikov_food."order" (order_id),
    CONSTRAINT order_structure_product_fk FOREIGN KEY (product_id)
        REFERENCES melnikov_food.product (product_id),
    CONSTRAINT order_structure_quantity_check CHECK (quantity > 0)
);

-- BR-8.1–8.6, BR-11.1–11.3
CREATE TABLE melnikov_food.payment (
    payment_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL,
    pay_type melnikov_food.payment_type NOT NULL,
    amount numeric(12,2) NOT NULL,
    transaction_reference text NOT NULL,
    transaction_timestamp timestamp NOT NULL,
    status melnikov_food.payment_status NOT NULL,
    CONSTRAINT payment_order_fk FOREIGN KEY (order_id)
        REFERENCES melnikov_food."order" (order_id),
    CONSTRAINT payment_transaction_reference_unique UNIQUE (transaction_reference)
);

-- BR-9.1–9.5, BR-11.1–11.3
CREATE TABLE melnikov_food.review (
    review_id uuid DEFAULT exts.uuid_generate_v4() PRIMARY KEY,
    client_id uuid NOT NULL,
    review_timestamp timestamp NOT NULL,
    entity_id uuid NOT NULL,
    entity_type melnikov_food.review_entity_type NOT NULL,
    order_id uuid NOT NULL,
    description text NOT NULL,
    photo_url text,
    rating numeric(3,2) NOT NULL,
    CONSTRAINT review_client_fk FOREIGN KEY (client_id)
        REFERENCES melnikov_food.client (client_id),
    CONSTRAINT review_order_fk FOREIGN KEY (order_id)
        REFERENCES melnikov_food."order" (order_id),
    CONSTRAINT review_order_entity_unique UNIQUE (order_id, entity_type, entity_id),
    CONSTRAINT review_rating_check CHECK (rating BETWEEN 1 AND 5)
);
