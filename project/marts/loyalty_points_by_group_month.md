---
mart: loyalty_points_by_group_month
grain:
- month
- customer_group
dimensions:
  month: month of xx_loyalty_txn.datetrx
  customer_group: c_bp_group.name via xx_loyalty_txn.xx_loyalty_account_id, xx_loyalty_account.c_bpartner_id, c_bpartner.c_bp_group_id
measures:
  points: sum of xx_loyalty_txn.points
  transactions: count of xx_loyalty_txn
---

Loyalty points earned per month and customer group (chapter 9, scenario B: the CFO's question about the
new loyalty programme).
