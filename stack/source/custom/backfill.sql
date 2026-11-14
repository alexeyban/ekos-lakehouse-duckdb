-- The programme starts with this year's completed customer invoices, posted once.
SET search_path = adempiere;
SELECT xx_loyalty_post(c_invoice_id)
  FROM c_invoice
 WHERE issotrx = 'Y' AND docstatus = 'CO' AND dateinvoiced >= DATE '2026-01-01'
 ORDER BY c_invoice_id;
SELECT count(*) AS transactions, sum(points) AS points FROM xx_loyalty_txn;
