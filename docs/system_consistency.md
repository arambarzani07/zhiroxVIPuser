# ZHIROX System Consistency

This file records UI conventions that should stay consistent across Owner and User editions.

## Sorani financial wording

- New debt action: `قەرز پێدان`
- Payment/collection action: `پارە وەرگرتنەوە`
- Received amount: `بڕی پارەی وەرگیراو`
- Debt limit: `سنووری قەرز`
- Unlimited: `بێ سنوور`
- Debt creation success: `قەرز پێدان تۆمار کرا ✅`
- Full collection action: `پارە وەرگرتنەوەی تەواو`

## Input direction

- Password and phone input are LTR.
- Kurdish names and ordinary Kurdish text remain RTL.
- Passwords are hidden by default and have a visibility toggle.

## Verification

- CI verification markers must follow the same user-facing terminology as the current UI.
- A wording-only cleanup must not weaken online-only, authorization, payment, or update checks.

## Edition boundary

Owner and User remain separate branches/app identities. Shared UI conventions may be kept aligned, but branch-specific capabilities must not be merged blindly.
