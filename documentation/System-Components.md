# System Components

Global reference for durable building blocks in this repository. Feature-specific sequences live in Feature specs only.

---

## Client_Sso_Routing__mdt (Custom Metadata Type)

**Purpose:** Map a **marker permission set** (by API name) to a **SAML Single Sign-On Setting** (by `DeveloperName`) so new SSO clients are added with metadata and assignments only.

**Public surface (schema):**

| Field API name | Type | Notes |
| --- | --- | --- |
| `Permission_Set_Name__c` | Text | Required. Marker permission set API name. |
| `Protocol__c` | Picklist | `SAML` (v1); `OIDC` reserved. |
| `Saml_Setting_Api_Name__c` | Text | Required for v1. `DeveloperName` of the **SamlSsoConfig** row in that org (Setup → Single Sign-On Settings). |
| `Is_Active__c` | Checkbox | Inactive rows ignored. |
| `Priority__c` | Number | Higher wins when multiple marker sets match. |

**Dependencies:** Marker permission sets assigned to users; SAML settings configured in Setup.

---

## LoginRouterService (Apex)

**Purpose:** Server-side routing for email-first login and password authentication using **`Site.login`**, avoiding **`Site.passwordlessLogin(PASSWORD)`** and internal PasswordVerificationUi loops described in the handoff.

**Public interface:**

- `@AuraEnabled(cacheable=false) static DiscoverResult discover(String email)` — returns `type` **`SSO`** or **`PASSWORD`**, optional `redirectUrl` for SSO, and `correlationId`. Emits one **INFO** debug line per call (`corr=<id> email=<masked> route=<SSO|PASSWORD> [samlSetting=<api>]`).
- `@AuraEnabled(cacheable=false) static LoginResult passwordLogin(String email, String password)` — returns `success`, optional `redirectUrl`, and generic `message` on failure. Emits one **INFO** debug line per call (`email=<masked> success=<bool>`).

**Dependencies:** `SamlSsoConfig`, `Auth.AuthConfiguration.getSamlSsoUrl`, `Site`, `User`, `PermissionSetAssignment`, `Client_Sso_Routing__mdt`. Class is **`without sharing`** so Experience **Guest** can resolve users by email; **CRUD/FLS still apply** — Guest profile and permission sets must be configured deliberately.

**Usage constraints:** Do not log secrets; do not return different discover outcomes for unknown vs known email; post-auth landing is server-pinned to `/s/` (no client-supplied redirect parameter is accepted). On unexpected exceptions, **`System.debug` at WARN** records exception type (and discover **correlationId** where applicable) for diagnosis; `@AuraEnabled` responses still collapse to the safe PASSWORD route / generic error message regardless of internal failure mode.

**Testability:** Three `@TestVisible` static seams (`TEST_ROUTING_ROWS`, `TEST_SSO_URL_OVERRIDE`, `TEST_COMMUNITY_BASE_URL`) let tests substitute the CMDT routing rows, the platform SAML URL build, and the community base URL — none of which are addressable from `@IsTest` directly. All seams default to `null` so production code follows the live path.

---

## emailFirstLogin (LWC)

**Purpose:** Experience Builder login UI: email step, optional SSO redirect, password step, calls `LoginRouterService`.

**Public surface:** Not `global` for embedding outside package; exposed to **Experience Builder** via target **`lightningCommunity__Page`** (add the component to the **Login** page in Builder; Login Page Type must be **Experience Builder Page**).

**Dependencies:** `LoginRouterService` Apex; site Guest must have Apex + data access per org policy.

---

## Login_Router_Guest (Permission Set)

**Purpose:** Grant **Apex class access** on `LoginRouterService` to the Experience Cloud **Guest** user. It does **not** ship with **`User`** object permissions: many orgs rely on **User** **Public Read Only** for **external users** (see [README.md](README.md) setup step 3) and use **`Login_Router_Guest`** only for Apex. **`PermissionSet`** / **`PermissionSetAssignment`** access for Guest is **org-specific** (Guest profile or another permission set) when OWD does not already allow those reads.

**Dependencies:** Assigned to the site’s Guest User in Setup.
