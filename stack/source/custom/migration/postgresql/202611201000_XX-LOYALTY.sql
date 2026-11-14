-- XX-LOYALTY: customer loyalty points. A completed customer invoice earns one point per 10 of its
-- grand total, credited to the customer's loyalty account.
SET search_path = adempiere;

CREATE TABLE xx_loyalty_account (
  xx_loyalty_account_id numeric(10) NOT NULL PRIMARY KEY,
  ad_client_id          numeric(10) NOT NULL,
  ad_org_id             numeric(10) NOT NULL,
  c_bpartner_id         numeric(10) NOT NULL REFERENCES c_bpartner (c_bpartner_id),
  points                numeric     NOT NULL DEFAULT 0,
  isactive              char(1)     NOT NULL DEFAULT 'Y',
  created               timestamp   NOT NULL DEFAULT now(),
  updated               timestamp   NOT NULL DEFAULT now(),
  CONSTRAINT xx_loyalty_account_bpartner UNIQUE (c_bpartner_id)
);
COMMENT ON TABLE xx_loyalty_account IS 'Loyalty account of a customer: the points balance.';

CREATE TABLE xx_loyalty_txn (
  xx_loyalty_txn_id     numeric(10) NOT NULL PRIMARY KEY,
  ad_client_id          numeric(10) NOT NULL,
  ad_org_id             numeric(10) NOT NULL,
  xx_loyalty_account_id numeric(10) NOT NULL REFERENCES xx_loyalty_account (xx_loyalty_account_id),
  c_invoice_id          numeric(10) NOT NULL REFERENCES c_invoice (c_invoice_id),
  points                numeric     NOT NULL,
  datetrx               date        NOT NULL,
  created               timestamp   NOT NULL DEFAULT now(),
  updated               timestamp   NOT NULL DEFAULT now(),
  CONSTRAINT xx_loyalty_txn_invoice UNIQUE (c_invoice_id)
);
COMMENT ON TABLE xx_loyalty_txn IS 'Loyalty points earned by a completed customer invoice.';

CREATE SEQUENCE xx_loyalty_account_sq START 1000000;
CREATE SEQUENCE xx_loyalty_txn_sq START 1000000;

-- Posts one completed customer invoice: opens the customer's account if needed, writes the points
-- transaction, adds the points to the balance. An invoice is posted once.
CREATE OR REPLACE FUNCTION xx_loyalty_post(p_invoice_id numeric) RETURNS void
LANGUAGE plpgsql SET search_path = adempiere AS $$
DECLARE
  inv     c_invoice%ROWTYPE;
  account numeric;
  earned  numeric;
BEGIN
  SELECT * INTO inv FROM c_invoice WHERE c_invoice_id = p_invoice_id;
  IF inv.issotrx <> 'Y' OR inv.docstatus <> 'CO' THEN
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM xx_loyalty_txn WHERE c_invoice_id = p_invoice_id) THEN
    RETURN;
  END IF;
  earned := floor(inv.grandtotal / 10);
  SELECT xx_loyalty_account_id INTO account FROM xx_loyalty_account WHERE c_bpartner_id = inv.c_bpartner_id;
  IF account IS NULL THEN
    account := nextval('xx_loyalty_account_sq');
    INSERT INTO xx_loyalty_account (xx_loyalty_account_id, ad_client_id, ad_org_id, c_bpartner_id)
    VALUES (account, inv.ad_client_id, inv.ad_org_id, inv.c_bpartner_id);
  END IF;
  INSERT INTO xx_loyalty_txn (xx_loyalty_txn_id, ad_client_id, ad_org_id, xx_loyalty_account_id,
                              c_invoice_id, points, datetrx)
  VALUES (nextval('xx_loyalty_txn_sq'), inv.ad_client_id, inv.ad_org_id, account, inv.c_invoice_id,
          earned, inv.dateinvoiced);
  UPDATE xx_loyalty_account SET points = points + earned, updated = now()
   WHERE xx_loyalty_account_id = account;
END $$;

CREATE OR REPLACE FUNCTION xx_loyalty_award() RETURNS trigger
LANGUAGE plpgsql SET search_path = adempiere AS $$
BEGIN
  IF NEW.docstatus = 'CO' AND OLD.docstatus IS DISTINCT FROM 'CO' AND NEW.issotrx = 'Y' THEN
    PERFORM xx_loyalty_post(NEW.c_invoice_id);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER xx_loyalty_award AFTER UPDATE OF docstatus ON c_invoice
  FOR EACH ROW EXECUTE FUNCTION xx_loyalty_award();
