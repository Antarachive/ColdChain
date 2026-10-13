-- Run ONCE as an admin user (SYSTEM) inside the pluggable DB (FREEPDB1 / XEPDB1 / ORCLPDB1).
-- Creates the schema owner used by the application.
CREATE USER coldstorage IDENTIFIED BY "ColdStorage#2026"
  DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE TRIGGER TO coldstorage;
