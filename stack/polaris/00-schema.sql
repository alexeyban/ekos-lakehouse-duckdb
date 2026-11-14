-- Polaris's relational-jdbc store needs its schema before it connects (it creates the tables).
-- The default `currentSchema=POLARIS_SCHEMA` is unquoted, so PostgreSQL reads it as polaris_schema.
CREATE SCHEMA IF NOT EXISTS polaris_schema;
