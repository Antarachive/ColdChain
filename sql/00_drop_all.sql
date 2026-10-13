-- Connected as COLDSTORAGE: removes every table, sequence and view (use to reset the demo).
BEGIN
  FOR v IN (SELECT view_name FROM user_views) LOOP EXECUTE IMMEDIATE 'DROP VIEW "' || v.view_name || '"'; END LOOP;
  FOR t IN (SELECT table_name FROM user_tables) LOOP EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE'; END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences) LOOP EXECUTE IMMEDIATE 'DROP SEQUENCE "' || s.sequence_name || '"'; END LOOP;
END;
/
