# GardenWorld loyalty programme (a customization)

A small customization of the ERP, the way a partner ships one: a migration script that adds two tables
and the routine that fills them. It is chapter 9's scenario B of the demo: new tables that arrive with new
logic in the source system.

- `xx_loyalty_account`: one row per customer, the points balance.
- `xx_loyalty_txn`: one row per points transaction.
- `xx_loyalty_post(invoice)`: when a customer invoice is completed, the customer earns one point per
  10 of the invoice's grand total. The trigger `xx_loyalty_award` on `c_invoice` calls it.

`backfill.sql` is data, not code: it posts this year's completed customer invoices once, as the partner
did when the programme started.
