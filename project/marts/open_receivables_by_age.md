---
mart: open_receivables_by_age
grain:
- invoice_month
- customer
dimensions:
  invoice_month: month of c_invoice.dateinvoiced
  customer: c_bpartner.name via c_invoice.c_bpartner_id
measures:
  open_amount: sum of c_invoice.grandtotal
  open_invoices: count of c_invoice
filters:
- c_invoice.issotrx is true
- c_invoice.docstatus = 'CO'
- c_invoice.ispaid is false
---

Completed customer invoices not yet paid, by the month they were invoiced (their age) and customer.
