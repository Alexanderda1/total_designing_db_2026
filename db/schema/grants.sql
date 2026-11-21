-- FOOD-109:
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'inspector') THEN
        CREATE USER inspector WITH PASSWORD 'NetoSQL2025';
    END IF;

    EXECUTE 'GRANT CONNECT ON DATABASE ' || quote_ident(current_database()) || ' TO inspector';
END;
$$;

GRANT ALL PRIVILEGES ON SCHEMA melnikov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA melnikov_food TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA melnikov_food TO inspector;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA melnikov_food TO inspector;

GRANT USAGE ON SCHEMA exts, information_schema, pg_catalog TO inspector;
GRANT EXECUTE ON FUNCTION exts.uuid_generate_v4() TO inspector;

