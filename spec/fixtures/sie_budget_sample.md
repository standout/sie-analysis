# Budget fixture provenance

Minimal sample for parser and overview tests. Account/object names are synthetic.
The four `#PSALDO` records are synthetic comparison amounts, not a real ledger.

Verified amounts (Skarptest-style 2026 income budget for account 3001):

- account total 185,000 for the year
- cost centers 123 = 25,000 and ABC = 10,000
- object amounts must not be added on top of the account total

Shape covered by specs:

- account-total budget rows only (default overview path)
- account totals plus cost-center object rows (cost_center dimension)
- no project budget rows in the company sample

Keep implementation details out of MCP tool text and public product docs.
This file is for maintainers and tests only.
