---
mart: purchase_spend_by_vendor
grain:
- month
- vendor
dimensions:
  month: month of c_invoice.dateinvoiced
  vendor: c_bpartner.name via c_invoice.c_bpartner_id
measures:
  spend: sum of c_invoice.grandtotal
  invoices: count of c_invoice
filters:
- c_invoice.issotrx is false
- c_invoice.docstatus = 'CO'
---

Completed vendor invoices per month and vendor: how many, and their grand total.
