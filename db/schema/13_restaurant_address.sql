-- BR-3.3
CREATE OR REPLACE FUNCTION melnikov_food.check_restaurant_physical_address()
RETURNS trigger AS $$
DECLARE
    v_restaurant_id uuid;
    v_address_id uuid;
    v_street text;
    v_house text;
    v_apartment text;
BEGIN
    LOCK TABLE melnikov_food.restaurant IN ACCESS EXCLUSIVE MODE;

    IF TG_TABLE_NAME = 'restaurant' THEN
        v_restaurant_id := NEW.restaurant_id;
        v_address_id := NEW.address_id;
        SELECT a.street, a.house_number, a.apartment_office
        INTO v_street, v_house, v_apartment
        FROM melnikov_food.address a
        WHERE a.address_id = v_address_id;
    ELSE
        v_address_id := OLD.address_id;
        SELECT r.restaurant_id INTO v_restaurant_id
        FROM melnikov_food.restaurant r
        WHERE r.address_id = v_address_id;

        IF v_restaurant_id IS NULL THEN
            RETURN NEW;
        END IF;
        v_street := NEW.street;
        v_house := NEW.house_number;
        v_apartment := NEW.apartment_office;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM melnikov_food.restaurant r
        JOIN melnikov_food.address a ON a.address_id = r.address_id
        WHERE r.restaurant_id <> v_restaurant_id
          AND r.address_id <> v_address_id
          AND a.street = v_street
          AND a.house_number = v_house
          AND (a.apartment_office = v_apartment
               OR (a.apartment_office IS NULL AND v_apartment IS NULL))
    ) THEN
        RAISE EXCEPTION 'Два ресторана не могут занимать один физический адрес (BR-3.3)';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER restaurant_physical_address_check_trg
BEFORE INSERT OR UPDATE OF address_id ON melnikov_food.restaurant
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_restaurant_physical_address();

CREATE TRIGGER address_restaurant_physical_check_trg
BEFORE UPDATE OF street, house_number, apartment_office ON melnikov_food.address
FOR EACH ROW EXECUTE FUNCTION melnikov_food.check_restaurant_physical_address();
