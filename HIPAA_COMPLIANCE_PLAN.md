# Better HIPAA And Research Compliance Plan

This document is a future planning guide, not legal advice. HIPAA compliance depends on Better's business model, customers, data flows, vendors, and research partners. Before Better handles PHI for a covered entity, business associate, clinic, employer, insurer, university, or formal research study, get healthcare privacy counsel and compliance review.

## Core Position

Better should remain local-first until there is a reviewed compliance program.

Current safest posture:

- Apple Health data is read on device.
- Derived sleep, biometric, protocol, and research rows stay local.
- Exports are user-triggered.
- No backend receives identifiable health data.
- No analytics, crash, support, or logging vendor receives health data.

Important HIPAA boundary:

- A direct-to-consumer Apple Health app is not automatically HIPAA-regulated.
- Better becomes HIPAA-relevant when it creates, receives, maintains, or transmits PHI on behalf of a covered entity or business associate.
- Research use has separate consent, authorization, IRB, privacy board, de-identification, and data-use requirements depending on the study design.

## Phase 0 - Applicability Decision

Goal: decide whether HIPAA applies before building cloud sync, clinician access, or research uploads.

Questions to answer:

- Is Better only a consumer app chosen by users directly?
- Is Better provided by, through, or on behalf of a clinic, doctor, health plan, employer health program, lab, university, or researcher?
- Will Better receive EHR, claims, clinical, or study data from a covered entity?
- Will Better transmit user health data to a backend controlled by Better?
- Will Better provide dashboards or exports to clinicians, researchers, coaches, protocol operators, or study sponsors?
- Will Better sign BAAs with customers or vendors?

Required outputs:

- HIPAA applicability memo.
- Data-flow diagram for current and planned features.
- List of data categories: Apple Health samples, derived sleep sessions, protocol logs, symptoms, illness/injury flags, exports, account data, device identifiers, support data, logs.
- Decision record: consumer-only, HIPAA-capable, or HIPAA-regulated.

Exit criteria:

- No backend or research upload work starts until applicability is documented.

## Phase 1 - Local-Only Privacy Baseline

Goal: make the non-cloud app defensible before any HIPAA-regulated use.

Product requirements:

- Keep HealthKit data local unless the user explicitly exports or opts into a reviewed upload flow.
- Make research mode opt-in and reversible.
- Keep export tools user-triggered.
- Explain that protocol impact is correlation unless a study design supports causal claims.
- Do not collect more HealthKit types than the app can explain and use.

iOS requirements:

- Use precise HealthKit purpose strings.
- Store local health-derived data with iOS data protection enabled.
- Use Keychain for tokens or secrets.
- Do not place health data in notification payloads, logs, screenshots, analytics events, or crash breadcrumbs.
- Exclude temporary export files from backup where appropriate.
- Add clear delete/export controls for local user data.

Engineering requirements:

- Create a health-data classification enum for models and export fields.
- Add tests that exports exclude raw HealthKit identifiers.
- Add a logging policy that forbids PHI and health-derived values in logs.
- Review all third-party SDKs before adding them.

Exit criteria:

- Better can honestly say health data stays local unless the user explicitly exports it.

## Phase 2 - Consent And Research Readiness

Goal: prepare research mode without silently converting consumer data into research data.

Research requirements:

- Separate product consent from research consent.
- Version every consent form.
- Store consent timestamp, consent version, withdrawal timestamp, and allowed data categories.
- Allow users to withdraw from future research collection.
- Define whether exported/uploaded data is identifiable, limited data set, coded, pseudonymized, or de-identified.
- Define retention and deletion rules.

UX requirements:

- Research opt-in must explain purpose, data categories, risks, sharing, retention, withdrawal, and contact path.
- Export/upload controls must show the date range and data categories before action.
- Avoid broad language such as "improve research" without concrete data use.

Engineering requirements:

- Add `ResearchConsentRecord`.
- Add an export manifest with consent version, export date, date range, included categories, and de-identification status.
- Gate any research export/upload behind active consent.
- Keep a test fixture proving revoked consent blocks upload.

Exit criteria:

- Research data cannot leave the device without explicit, versioned consent.

## Phase 3 - De-Identification And Dataset Design

Goal: reduce re-identification risk before using health data for analytics or research.

Dataset rules:

- Prefer derived nightly rows over raw HealthKit samples.
- Remove direct identifiers from research exports by default.
- Avoid exact timestamps when day-level or week-level buckets are enough.
- Generalize age, location, device, and rare-condition fields.
- Treat sleep and wearable time series as potentially re-identifiable.
- Keep linkage keys separate from research datasets.

HIPAA de-identification paths:

- Safe Harbor: remove the listed identifiers and avoid actual knowledge that the remaining data can identify a person.
- Expert Determination: have a qualified expert document that re-identification risk is very small for the intended recipient and context.

Engineering requirements:

- Add a research export schema that marks each field as direct identifier, quasi-identifier, health measure, protocol measure, or metadata.
- Add automated checks that disallowed identifiers are absent from de-identified exports.
- Add aggregation options for small cohorts.
- Add suppression rules for rare combinations.

Exit criteria:

- Every research export is labeled as identifiable, limited, coded, pseudonymized, or de-identified.

## Phase 4 - HIPAA-Capable Backend Foundation

Goal: build backend infrastructure that can support ePHI before receiving health data.

Architecture requirements:

- Use a cloud provider and database services that will sign a BAA.
- Keep production, staging, and development data isolated.
- Encrypt data in transit.
- Encrypt data at rest.
- Use managed keys or documented key management.
- Use tenant-aware authorization if serving clinics, studies, or organizations.
- Prevent PHI from entering logs, traces, analytics, support tools, and queues unless each system is approved.

Security requirements:

- Strong authentication for users and admins.
- MFA for workforce/admin access.
- Role-based access control.
- Least-privilege service accounts.
- Audit logs for access, export, update, delete, admin actions, and failed access attempts.
- Immutable or tamper-evident audit storage.
- Secret management outside source control.
- Backup encryption and restore testing.

Operational requirements:

- Incident response process.
- Breach assessment workflow.
- Vendor inventory.
- BAA inventory.
- Access review process.
- Employee onboarding/offboarding checklist.

Exit criteria:

- Backend can pass a basic HIPAA Security Rule safeguard review before first ePHI upload.

## Phase 5 - HIPAA Policies And Governance

Goal: build the administrative program, because HIPAA is not only code.

Required policies:

- Security management process.
- Risk analysis and risk management.
- Workforce access policy.
- Sanction policy.
- Information access management.
- Security awareness and training.
- Incident response.
- Contingency plan and backups.
- Device and media controls.
- Vendor and BAA management.
- Data retention and deletion.
- Breach notification procedure.
- User support and identity verification.

Required roles:

- Security official.
- Privacy owner.
- Incident response owner.
- Vendor/compliance owner.

Required recurring work:

- Annual risk analysis.
- Access reviews.
- Vendor reviews.
- Security training.
- Disaster recovery test.
- Audit-log review.
- Policy review.

Exit criteria:

- Better has a documented compliance program, not just secure code.

## Phase 6 - Clinical, Research, Or Partner Launch

Goal: support regulated research or covered-entity partnerships safely.

Before launch:

- Determine whether Better is a business associate.
- Execute BAAs where required.
- Confirm whether IRB or Privacy Board review is required.
- Confirm whether HIPAA authorization, waiver, or limited data set/data use agreement applies.
- Approve study protocol, consent, retention, data sharing, and withdrawal flow.
- Run threat model and privacy review for the exact study workflow.
- Run penetration test or independent security review.
- Prepare customer-facing security and privacy documentation.

Product requirements:

- Organization/study-specific consent.
- Study-specific data collection scopes.
- Participant withdrawal flow.
- Research export audit trail.
- Admin access audit trail.
- Data retention and deletion by study.

Exit criteria:

- No regulated partner or study receives health data until legal, privacy, security, and research review are complete.

## Phase 7 - Ongoing Compliance And Evidence

Goal: maintain proof, because compliance has to be operated continuously.

Evidence to retain:

- Risk analyses and remediation plans.
- Access review records.
- Audit-log review records.
- Security training records.
- Incident reports and breach assessments.
- BAA and vendor review records.
- Pen test and vulnerability remediation records.
- Consent version history.
- Data deletion and withdrawal records.
- Backup and restore test records.

Engineering cadence:

- Review data flows before each major feature.
- Review new SDKs before adoption.
- Run dependency and secrets scanning.
- Maintain audit-log tests.
- Maintain export de-identification tests.
- Verify no PHI appears in logs or crash reports.

Exit criteria:

- Better can demonstrate what data was collected, why, who accessed it, where it went, and how it was protected.

## Technical Guardrails For Future PRs

Any PR that adds one of these must include a privacy/compliance review:

- Backend sync.
- Account system.
- Research upload.
- Clinician, coach, researcher, or admin dashboard.
- Third-party analytics, crash, support, or messaging SDK.
- Cloud storage.
- Push notifications containing health context.
- Export format changes.
- New HealthKit data categories.
- Any connection to EHR, FHIR, claims, lab, clinic, university, employer, insurer, or study sponsor systems.

Any PR that touches health data should answer:

- What data is collected?
- Why is it necessary?
- Where is it stored?
- Who can access it?
- Is it transmitted?
- Is it identifiable?
- What consent covers it?
- How can the user delete or withdraw it?
- Does any vendor receive it?
- Does the change affect HIPAA applicability?

## Source References

- HHS Security Rule: https://www.hhs.gov/hipaa/for-professionals/security/index.html
- HHS Business Associates: https://www.hhs.gov/hipaa/for-professionals/privacy/guidance/business-associates/index.html
- HHS Health Apps Guidance: https://www.hhs.gov/hipaa/for-professionals/special-topics/health-apps/index.html
- HHS Health Apps And APIs: https://www.hhs.gov/hipaa/for-professionals/privacy/guidance/access-right-health-apps-apis/index.html
- HHS Research Guidance: https://www.hhs.gov/hipaa/for-professionals/privacy/guidance/research/index.html
- HHS De-identification Guidance: https://www.hhs.gov/hipaa/for-professionals/privacy/special-topics/de-identification/
- HHS Cloud Computing Guidance: https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html
