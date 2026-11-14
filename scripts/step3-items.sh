# Sourced by step3-review.sh: the items decided one by one, after reading them (2026-11-14).
# Identity: no candidates in this run. Relationships: not a subject (no discovery run).

# ── PII in the 42 in-scope tables: values about a person, or secrets → confirmed, redacted ──────
run step3-pii-confirm "${LH[@]}" review pii \
  ad_user.birthday ad_user.email ad_user.emailuser ad_user.emailuserpw ad_user.emailverify \
  ad_user.password ad_user.phone ad_user.phone2 ad_client.emailtest ad_client.requestemail \
  c_bankaccount.iban c_bpartner_location.phone c_bpartner_location.phone2 \
  c_location.address1 c_location.address2 c_location.address3 c_location.address4 c_location.address5 \
  c_payment.a_email c_payment.a_ident_ssn c_payment.a_street c_payment.creditcardnumber \
  c_payment.creditcardvv c_payment.creditcardexpmm c_payment.creditcardexpyy c_payment.iban \
  --confirm --mask redact --as "$BY" \
  --reason "a person's contact data, identity number, card or bank details, or a secret: never reaches the lakehouse in clear"

# ── Named like PII but holding none: flags, dates, keys, codes and country settings ─────────────
run step3-pii-reject "${LH[@]}" review pii \
  ad_client.ad_passwordrule_id ad_client.isserveremail ad_user.datepasswordchanged \
  ad_user.emailverifydate ad_user.isnopasswordreset c_bpartner.sendemail c_invoice.sendemail \
  c_order.sendemail m_inout.sendemail m_inout.isalternatereturnaddress \
  c_bpartner_location.customeraddressid c_payment.customeraddressid c_payment.creditcardtype \
  c_location.c_addressvalidation_id c_location.validateaddress \
  c_country.expressionphone c_country.isaddresslineslocalreverse c_country.isaddresslinesreverse \
  c_country.ispostcodelookup c_country.lookupclassname c_country.lookuppassword \
  c_country.placeholderaddress1 c_country.placeholderaddress2 c_country.placeholderaddress3 \
  c_country.placeholderaddress4 c_country.placeholderaddress5 \
  --reject --as "$BY" \
  --reason "the name matched a PII pattern, the column holds a Y/N flag, a date, a key, a code or a per-country setting"
