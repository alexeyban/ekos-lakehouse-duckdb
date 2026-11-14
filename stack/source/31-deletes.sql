-- Chapter 9, scenario A5: the 30 draft invoices of the synthetic data are deleted in the source, with
-- their lines and tax, and no deletion marker anywhere (iDempiere deletes drafts physically).
-- 30 of about 750 invoice keys: under `mass-delete-percent` (5), so `lakehouse deletes` applies them.
SET search_path = adempiere;
BEGIN;
DELETE FROM c_invoicetax  WHERE c_invoice_id IN (SELECT c_invoice_id FROM c_invoice WHERE description = 'synthetic (ekos-lakehouse-duckdb) draft');
DELETE FROM c_invoiceline WHERE c_invoice_id IN (SELECT c_invoice_id FROM c_invoice WHERE description = 'synthetic (ekos-lakehouse-duckdb) draft');
DELETE FROM c_invoice     WHERE description = 'synthetic (ekos-lakehouse-duckdb) draft';
COMMIT;
