-- Synthetic GardenWorld business for 2025-01-01 .. 2026-11-13, added to the iDempiere 12 seed so the
-- marts have this year and last year to show. GardenWorld's own documents are from 2002–2003 and
-- number a few dozen; everything below is generated, and says so: every generated document's
-- description starts with "synthetic (ekos-lakehouse-duckdb)".
--
-- How: each document is a copy of one of the seed's own documents (jsonb of the template row with
-- the fields that make it a new document replaced), so every column iDempiere requires is filled
-- the way the application fills it. Prices are the seed's price lists, taxes its tax rates.
-- Deterministic: setseed() and fixed dates, so every reset of the demo produces the same rows.
--
-- What it makes: sales orders + lines + order tax, AR invoices + lines + invoice tax, purchase
-- orders + lines, AP invoices + lines + tax, AR receipts / AP payments with allocations.
-- What it does not: shipments and receipts of goods (M_InOut), accounting facts (Fact_Acct —
-- documents are left Posted = 'N'), stock (M_Storage). The demo's marts do not read them.
SET search_path = adempiere;

CREATE OR REPLACE FUNCTION pg_temp.copy_row(tbl regclass, template jsonb, changes jsonb)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('INSERT INTO %s SELECT (jsonb_populate_record(NULL::%s, $1)).*', tbl, tbl)
    USING template || changes;
END $$;

CREATE TEMP TABLE lines (orderline int, line int, product int, uom int, qty numeric, price numeric,
                         pricelist numeric, pricelimit numeric, amt numeric);

DO $$
DECLARE
  first_day  CONSTANT date := DATE '2025-01-01';
  last_day   CONSTANT date := DATE '2026-11-13';
  marker     CONSTANT text := 'synthetic (ekos-lakehouse-duckdb)';
  -- templates: the seed's own documents
  t_so   jsonb := (SELECT to_jsonb(o) FROM c_order o WHERE c_order_id = 100);
  t_sol  jsonb := (SELECT to_jsonb(l) FROM c_orderline l WHERE c_orderline_id = 100);
  t_sot  jsonb := (SELECT to_jsonb(t) FROM c_ordertax t WHERE c_order_id = 100 ORDER BY c_tax_id LIMIT 1);
  t_po   jsonb := (SELECT to_jsonb(o) FROM c_order o WHERE c_order_id = 104);
  t_pol  jsonb := (SELECT to_jsonb(l) FROM c_orderline l WHERE c_orderline_id = 105);
  t_pot  jsonb := (SELECT to_jsonb(t) FROM c_ordertax t WHERE c_order_id = 104 ORDER BY c_tax_id LIMIT 1);
  t_ari  jsonb := (SELECT to_jsonb(i) FROM c_invoice i WHERE c_invoice_id = 109);
  t_aril jsonb := (SELECT to_jsonb(l) FROM c_invoiceline l WHERE c_invoice_id = 109 ORDER BY line LIMIT 1);
  t_arit jsonb := (SELECT to_jsonb(t) FROM c_invoicetax t WHERE c_invoice_id = 109);
  t_api  jsonb := (SELECT to_jsonb(i) FROM c_invoice i WHERE c_invoice_id = 106);
  t_apil jsonb := (SELECT to_jsonb(l) FROM c_invoiceline l WHERE c_invoice_id = 106 ORDER BY line LIMIT 1);
  t_apit jsonb := (SELECT to_jsonb(t) FROM c_invoicetax t WHERE c_invoice_id = 106);
  t_pay  jsonb := (SELECT to_jsonb(p) FROM c_payment p WHERE c_payment_id = 100);
  t_alh  jsonb := (SELECT to_jsonb(h) FROM c_allocationhdr h WHERE c_allocationhdr_id = 100);
  t_all  jsonb := (SELECT to_jsonb(l) FROM c_allocationline l WHERE c_allocationline_id = 101);
  customers int[] := ARRAY[117, 118, 119, 120, 121, 200000];
  cust_w    numeric[] := ARRAY[0.30, 0.18, 0.07, 0.15, 0.20, 0.10];
  vendors   int[] := ARRAY[114, 120, 121, 50000, 50003];
  -- ids above anything the seed or iDempiere's own sequences hand out in this demo
  id_order int := 5000000; id_oline int := 5000000; id_inv int := 5000000; id_iline int := 5000000;
  id_pay   int := 5000000; id_alh   int := 5000000; id_all  int := 5000000;
  doc_so int := 500000; doc_po int := 900000; doc_ari int := 600000; doc_api int := 700000;
  doc_pay int := 800000;
  d date; month_start date; n_docs int; season numeric; growth numeric;
  bp int; loc int; is_sale boolean; n_lines int; p record; qty numeric; amt numeric;
  total numeric; tax_rate numeric; tax_id int; paid_on date; k int; r numeric; acc numeric;
  ts timestamptz; due_days int; pick numeric;
BEGIN
  PERFORM setseed(0.4242);
  month_start := first_day;
  WHILE month_start <= last_day LOOP
    -- a garden business: spring peak, a quiet winter; 2026 about 15% above 2025
    season := (ARRAY[0.45, 0.6, 1.3, 1.8, 1.9, 1.5, 1.1, 0.95, 1.0, 0.85, 0.6, 0.5])[extract(month FROM month_start)::int];
    growth := CASE WHEN extract(year FROM month_start) = 2026 THEN 1.15 ELSE 1.0 END;
    n_docs := greatest(3, round(22 * season * growth + (random() - 0.5) * 6))::int;
    FOR k IN 1 .. n_docs + greatest(1, round(n_docs / 4.0))::int LOOP
      is_sale := k <= n_docs;
      d := month_start + floor(random() * ((month_start + interval '1 month')::date - month_start))::int;
      CONTINUE WHEN d > last_day;
      ts := d + time '09:00' + (random() * interval '8 hours');
      IF is_sale THEN
        r := random(); acc := 0; bp := customers[1];
        FOR i IN 1 .. array_length(customers, 1) LOOP
          acc := acc + cust_w[i];
          IF r <= acc THEN bp := customers[i]; EXIT; END IF;
        END LOOP;
      ELSE
        bp := vendors[1 + floor(random() * array_length(vendors, 1))::int];
      END IF;
      loc := (SELECT c_bpartner_location_id FROM c_bpartner_location WHERE c_bpartner_id = bp ORDER BY 1 LIMIT 1);
      tax_id := CASE WHEN is_sale THEN 105 ELSE 109 END;
      tax_rate := (SELECT rate FROM c_tax WHERE c_tax_id = tax_id) / 100.0;

      -- the order header first (totals filled in after its lines)
      id_order := id_order + 1;
      IF is_sale THEN doc_so := doc_so + 1; ELSE doc_po := doc_po + 1; END IF;
      PERFORM pg_temp.copy_row('c_order', CASE WHEN is_sale THEN t_so ELSE t_po END, jsonb_build_object(
        'c_order_id', id_order, 'c_order_uu', md5('order' || id_order)::uuid::text,
        'documentno', CASE WHEN is_sale THEN doc_so ELSE doc_po END::text,
        'c_doctype_id', CASE WHEN is_sale THEN 132 ELSE 126 END,
        'c_doctypetarget_id', CASE WHEN is_sale THEN 132 ELSE 126 END,
        'description', marker, 'docstatus', 'CO', 'docaction', 'CL', 'processed', 'Y', 'posted', 'N',
        'c_bpartner_id', bp, 'c_bpartner_location_id', loc, 'bill_bpartner_id', bp, 'bill_location_id', loc,
        'ad_user_id', NULL, 'bill_user_id', NULL,
        'dateordered', d, 'datepromised', d + 7, 'dateacct', d,
        'm_pricelist_id', CASE WHEN is_sale THEN 101 ELSE 102 END,
        'isinvoiced', 'Y', 'isdelivered', 'Y',
        'created', ts, 'updated', ts));

      -- 1–4 lines (sales) or 2–4 (purchases), each a product from the price list in force
      n_lines := CASE WHEN is_sale THEN 1 + floor(random() * 4)::int ELSE 2 + floor(random() * 3)::int END;
      total := 0;
      FOR i IN 1 .. n_lines LOOP
        -- one draw per line, then the product at that position by id: `ORDER BY random()` drew
        -- one number per row in scan order, which a different plan changes (pass 1 ≠ pass 2)
        pick := random();
        SELECT pr.m_product_id, pr.c_uom_id, pp.pricestd, pp.pricelist, pp.pricelimit INTO p
          FROM m_product pr JOIN m_productprice pp USING (m_product_id)
         WHERE pp.m_pricelist_version_id = CASE WHEN is_sale THEN 104 ELSE 103 END
           AND pr.m_product_id BETWEEN 123 AND 144 AND pp.pricestd > 0
         ORDER BY pr.m_product_id
        OFFSET floor(pick * (SELECT count(*) FROM m_product pr JOIN m_productprice pp USING (m_product_id)
                             WHERE pp.m_pricelist_version_id = CASE WHEN is_sale THEN 104 ELSE 103 END
                               AND pr.m_product_id BETWEEN 123 AND 144 AND pp.pricestd > 0))
         LIMIT 1;
        qty := CASE WHEN is_sale THEN 1 + floor(random() * 12) ELSE 5 + 5 * floor(random() * 3) END;
        amt := round(qty * p.pricestd, 2);
        total := total + amt;
        id_oline := id_oline + 1;
        PERFORM pg_temp.copy_row('c_orderline', CASE WHEN is_sale THEN t_sol ELSE t_pol END, jsonb_build_object(
          'c_orderline_id', id_oline, 'c_orderline_uu', md5('oline' || id_oline)::uuid::text,
          'c_order_id', id_order, 'line', i * 10, 'description', NULL,
          'c_bpartner_id', bp, 'c_bpartner_location_id', loc,
          'm_product_id', p.m_product_id, 'c_uom_id', p.c_uom_id, 'c_tax_id', tax_id,
          'qtyordered', qty, 'qtyentered', qty, 'qtydelivered', qty, 'qtyinvoiced', qty, 'qtyreserved', 0,
          'priceactual', p.pricestd, 'priceentered', p.pricestd, 'pricelist', p.pricelist,
          'pricelimit', p.pricelimit, 'linenetamt', amt, 'discount', 0,
          'dateordered', d, 'datepromised', d + 7, 'datedelivered', d + 2, 'dateinvoiced', d + 3,
          'processed', 'Y', 'created', ts, 'updated', ts));
        -- the invoice line comes with the invoice below; remember what to invoice
        INSERT INTO pg_temp.lines VALUES (id_oline, i * 10, p.m_product_id, p.c_uom_id, qty, p.pricestd, p.pricelist, p.pricelimit, amt);
      END LOOP;
      UPDATE c_order SET totallines = total, grandtotal = round(total * (1 + tax_rate), 2) WHERE c_order_id = id_order;
      PERFORM pg_temp.copy_row('c_ordertax', CASE WHEN is_sale THEN t_sot ELSE t_pot END, jsonb_build_object(
        'c_order_id', id_order, 'c_tax_id', tax_id, 'c_ordertax_uu', md5('otax' || id_order)::uuid::text,
        'taxbaseamt', total, 'taxamt', round(total * tax_rate, 2), 'created', ts, 'updated', ts));

      -- the invoice, three days later, with one line per order line
      id_inv := id_inv + 1;
      IF is_sale THEN doc_ari := doc_ari + 1; ELSE doc_api := doc_api + 1; END IF;
      due_days := 30;
      PERFORM pg_temp.copy_row('c_invoice', CASE WHEN is_sale THEN t_ari ELSE t_api END, jsonb_build_object(
        'c_invoice_id', id_inv, 'c_invoice_uu', md5('inv' || id_inv)::uuid::text,
        'documentno', CASE WHEN is_sale THEN doc_ari ELSE doc_api END::text,
        'c_doctype_id', CASE WHEN is_sale THEN 116 ELSE 123 END,
        'c_doctypetarget_id', CASE WHEN is_sale THEN 116 ELSE 123 END,
        'description', marker, 'docstatus', 'CO', 'docaction', 'CL', 'processed', 'Y', 'posted', 'N',
        'c_order_id', id_order, 'c_bpartner_id', bp, 'c_bpartner_location_id', loc, 'ad_user_id', NULL,
        'dateinvoiced', d + 3, 'dateacct', d + 3, 'dateordered', d,
        'm_pricelist_id', CASE WHEN is_sale THEN 101 ELSE 102 END,
        'c_paymentterm_id', (SELECT c_paymentterm_id FROM c_paymentterm WHERE ad_client_id = 11 AND netdays = 30 ORDER BY 1 LIMIT 1),
        'totallines', total, 'grandtotal', round(total * (1 + tax_rate), 2), 'ispaid', 'N',
        'created', ts + interval '3 days', 'updated', ts + interval '3 days'));
      INSERT INTO c_invoiceline SELECT (jsonb_populate_record(NULL::c_invoiceline,
          CASE WHEN is_sale THEN t_aril ELSE t_apil END || jsonb_build_object(
            'c_invoiceline_id', id_iline + row_number() OVER (ORDER BY l.line),
            'c_invoiceline_uu', md5('iline' || (id_iline + row_number() OVER (ORDER BY l.line)))::uuid::text,
            'c_invoice_id', id_inv, 'c_orderline_id', l.orderline, 'line', l.line, 'description', NULL,
            'm_inoutline_id', NULL, 'm_product_id', l.product, 'c_uom_id', l.uom, 'c_tax_id', tax_id,
            'qtyinvoiced', l.qty, 'qtyentered', l.qty, 'priceactual', l.price, 'priceentered', l.price,
            'pricelist', l.pricelist, 'pricelimit', l.pricelimit, 'linenetamt', l.amt, 'linetotalamt', l.amt,
            'taxamt', 0, 'processed', 'Y',
            'created', ts + interval '3 days', 'updated', ts + interval '3 days'))).*
        FROM pg_temp.lines l;
      id_iline := id_iline + n_lines;
      TRUNCATE pg_temp.lines;
      PERFORM pg_temp.copy_row('c_invoicetax', CASE WHEN is_sale THEN t_arit ELSE t_apit END, jsonb_build_object(
        'c_invoice_id', id_inv, 'c_tax_id', tax_id, 'c_invoicetax_uu', md5('itax' || id_inv)::uuid::text,
        'taxbaseamt', total, 'taxamt', round(total * tax_rate, 2),
        'created', ts + interval '3 days', 'updated', ts + interval '3 days'));

      -- paid after its term plus a customer's own delay; recent invoices are still open
      paid_on := d + 3 + due_days + floor(random() * 45)::int - 10;
      IF paid_on <= last_day AND random() < 0.94 THEN
        id_pay := id_pay + 1; doc_pay := doc_pay + 1;
        amt := round(total * (1 + tax_rate), 2);
        PERFORM pg_temp.copy_row('c_payment', t_pay, jsonb_build_object(
          'c_payment_id', id_pay, 'c_payment_uu', md5('pay' || id_pay)::uuid::text,
          'documentno', doc_pay::text, 'description', marker,
          'isreceipt', CASE WHEN is_sale THEN 'Y' ELSE 'N' END,
          'c_doctype_id', CASE WHEN is_sale THEN 119 ELSE 125 END,
          'c_bpartner_id', bp, 'c_invoice_id', id_inv, 'c_order_id', NULL,
          'payamt', amt, 'datetrx', paid_on, 'dateacct', paid_on, 'docstatus', 'CO', 'docaction', 'CL',
          'processed', 'Y', 'posted', 'N', 'isallocated', 'Y', 'isreconciled', 'N',
          'created', paid_on + time '10:00', 'updated', paid_on + time '10:00'));
        id_alh := id_alh + 1; id_all := id_all + 1;
        PERFORM pg_temp.copy_row('c_allocationhdr', t_alh, jsonb_build_object(
          'c_allocationhdr_id', id_alh, 'c_allocationhdr_uu', md5('alh' || id_alh)::uuid::text,
          'documentno', doc_pay::text, 'description', marker, 'datetrx', paid_on, 'dateacct', paid_on,
          'approvalamt', amt, 'docstatus', 'CO', 'docaction', 'CL', 'processed', 'Y', 'posted', 'N',
          'created', paid_on + time '10:00', 'updated', paid_on + time '10:00'));
        PERFORM pg_temp.copy_row('c_allocationline', t_all, jsonb_build_object(
          'c_allocationline_id', id_all, 'c_allocationline_uu', md5('all' || id_all)::uuid::text,
          'c_allocationhdr_id', id_alh, 'c_invoice_id', id_inv, 'c_payment_id', id_pay, 'c_order_id', NULL,
          'c_bpartner_id', bp, 'amount', CASE WHEN is_sale THEN amt ELSE -amt END,
          'datetrx', paid_on, 'created', paid_on + time '10:00', 'updated', paid_on + time '10:00'));
        UPDATE c_invoice SET ispaid = 'Y', updated = paid_on + time '10:00' WHERE c_invoice_id = id_inv;
      END IF;
    END LOOP;
    month_start := (month_start + interval '1 month')::date;
  END LOOP;
END $$;

-- What was added, as the restore log shows it.
SELECT issotrx, extract(year FROM dateinvoiced)::int AS year, count(*) AS invoices,
       sum(grandtotal) AS grand_total, sum(CASE WHEN ispaid = 'Y' THEN 0 ELSE grandtotal END) AS open_amount
  FROM c_invoice WHERE description LIKE 'synthetic (ekos-lakehouse-duckdb)%'
 GROUP BY 1, 2 ORDER BY 1, 2;
