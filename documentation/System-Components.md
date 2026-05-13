# System Components

Global reference for durable building blocks in this repository. Feature-specific sequences live in Feature specs only.

---

## Client_Sso_Routing__mdt (Custom Metadata Type)

**Purpose:** Map a **marker permission set** (by API name) to a **SAML Single Sign-On Setting** (by `DeveloperName`) so new SSO clients are added with metadata and assignments only.

**Public surface (schema):**

| Field API name | Type | Notes |
| --- | --- | --- |
| `Permission_Set_Name__c` | Text | Required. Must equal **`PermissionSet.Name`** (API name) or **`PermissionSet.Label`** on the user’s marker assignment (case-sensitive). |
| `Protocol__c` | Picklist | `SAML` (v1); `OIDC` reserved. |
| `Saml_Setting_Api_Name__c` | Text | Required for v1. `DeveloperName` of the **SamlSsoConfig** row in that org (Setup → Single Sign-On Settings). Used for logging and, when **`Saml_Sso_Config_Id__c`** is blank, to resolve the config Id (that query usually **fails for Experience Guest** — prefer **`Saml_Sso_Config_Id__c`**). |
| `Saml_Sso_Config_Id__c` | Text (18) | Optional. Salesforce **Id** of the **SamlSsoConfig** record. When set, **`Auth.AuthConfiguration.getSamlSsoUrl`** uses this Id and **does not** query **SamlSsoConfig** by name — **required for typical community Guest** users, who cannot read **SamlSsoConfig**. Obtain as admin: `SELECT Id, DeveloperName FROM SamlSsoConfig WHERE DeveloperName = '…'`. |
| `Is_Active__c` | Checkbox | Inactive rows ignored. |
| `Priority__c` | Number | Higher wins when multiple marker sets match. |

**Dependencies:** Marker permission sets assigned to users; SAML settings configured in Setup.

---

## LoginRouterService (Apex)

**Purpose:** Server-side routing for email-first login and password authentication using **`Site.login`**, avoiding **`Site.passwordlessLogin(PASSWORD)`** and internal PasswordVerificationUi loops described in the handoff.

**Public interface:**

- `@AuraEnabled(cacheable=false) static DiscoverResult discover(String email)` — parameter is the first-step identifier (trimmed in Apex); may match **`User.Email`** or **`User.Username`**. Returns **`DiscoverResult`**: `correlationId` (String), `type` (String: **`SSO`**, **`PASSWORD`**, or **`NONE`**), `redirectUrl` (String, set only for **`SSO`**). Emits one **INFO** debug line per call (`corr=<id> email=<masked> route=<SSO|PASSWORD|NONE> [samlSetting=<api>]`).
- `@AuraEnabled(cacheable=false) static LoginResult passwordLogin(String email, String password)` — same first-step string as **discover**; returns **`LoginResult`**: `success` (Boolean), `redirectUrl` (String on success), `message` (generic text on failure). Emits one **INFO** debug line per call (`email=<masked> success=<bool>`).

**Dependencies:** `SamlSsoConfig` (optional when **`Saml_Sso_Config_Id__c`** is populated on routing rows), `Auth.AuthConfiguration.getSamlSsoUrl`, `Site`, `User` (including **`Username`** and **`Email`** for lookup), `PermissionSetAssignment`, `Client_Sso_Routing__mdt`. Class is **`without sharing`** so Experience **Guest** can resolve users for routing; **CRUD/FLS still apply** — Guest profile and permission sets must be configured deliberately.

**Usage constraints:** Do not log secrets. **discover** must not let callers infer whether an identifier exists for **unknown** vs **ambiguous** cases: **`NONE`** covers zero matches, multiple matches, malformed input, and unexpected errors. Post-auth landing is server-pinned to **`/s/`** (no client-supplied redirect). On unexpected **discover** exceptions, **`System.debug` at WARN** records exception type and **correlationId**; the returned **`type`** is **`NONE`** (never **`PASSWORD`** for error collapse). When exactly one user matches and CMDT selects SAML but the initiation URL is blank, **`type`** is **`PASSWORD`** (password fallback; **WARN** logs the SAML setting). **passwordLogin** always returns the same generic **`message`** on failure regardless of cause.

**Testability:** Three `@TestVisible` static seams (`TEST_ROUTING_ROWS`, `TEST_SSO_URL_OVERRIDE`, `TEST_COMMUNITY_BASE_URL`) let tests substitute the CMDT routing rows, the platform SAML URL build, and the community base URL — none of which are addressable from `@IsTest` directly. All seams default to `null` so production code follows the live path.

---

## emailFirstLogin (LWC)

**Purpose:** Experience Builder login UI: identifier step, optional SAML redirect, optional password step; calls **`LoginRouterService`**.

**Public surface:** Not `global` for embedding outside package; exposed to **Experience Builder** via target **`lightningCommunity__Page`** (add the component to the **Login** page in Builder; Login Page Type must be **Experience Builder Page**). Layout: centered card, **`max-width: 480px`**, **`width: 100%`**, white background, bordered; first field is **`lightning-input`** with **`type="email"`** and label **Email**.

**Dependencies:** `LoginRouterService` Apex; site Guest must have Apex + data access per org policy.

---

## Login_Router_Guest (Permission Set)

**Purpose:** Grant **Apex class access** on `LoginRouterService` to the Experience Cloud **Guest** user. It does **not** ship with **`User`** object permissions: many orgs rely on **User** **Public Read Only** for **external users** (see [README.md](README.md) setup step 3) and use **`Login_Router_Guest`** only for Apex. **`PermissionSet`** / **`PermissionSetAssignment`** access for Guest is **org-specific** (Guest profile or another permission set) when OWD does not already allow those reads.

**Dependencies:** Assigned to the site’s Guest User in Setup.
