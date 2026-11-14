---
mart: sales_by_category_month
grain:
- month
- product_category
dimensions:
  month: month of c_invoice.dateinvoiced
  product_category: m_product_category.name via c_invoiceline.m_product_id, m_product.m_product_category_id
measures:
  revenue: sum of c_invoiceline.linenetamt
filters:
- c_invoice.issotrx is true
- c_invoice.docstatus = 'CO'
---

Revenue (invoiced, net of tax) of completed customer invoices per month and product category.
