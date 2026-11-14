-- Chapter 9, scenario A: an ERP update the developer ships without telling anyone. One change of each
-- class EKOS's sync tells apart (RFC 0194); `make change-a` applies it, the next scheduled run finds it.
--   A1 new nullable column  c_invoiceline.promocode          → applied automatically
--   A2 widening             c_bp_group.value 40 → 60 chars   → applied automatically
--   A3 rename               c_order.poreference → po_reference → proposed; c_order paused
--   A4 drop                 m_product_category.name           → proposed; m_product_category paused.
--                           The sales mart's product_category dimension and the CFO dashboard's revenue
--                           chart read it. Its one dependent view goes with it (CASCADE), as it would in
--                           a careless upgrade script.
SET search_path = adempiere;
BEGIN;
ALTER TABLE c_invoiceline ADD COLUMN promocode varchar(20);
ALTER TABLE c_bp_group ALTER COLUMN value TYPE varchar(60);
ALTER TABLE c_order RENAME COLUMN poreference TO po_reference;
ALTER TABLE m_product_category DROP COLUMN name CASCADE;
COMMIT;
