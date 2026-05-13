# System Components

Global reference for durable building blocks in this repository. Feature-specific sequences live in Feature specs only.

---

## Client_Sso_Routing__mdt (Custom Metadata Type)

**Purpose:** Map a **marker permission set** (by API name or label) to a **SAML Single Sign-On Setting** so new SSO clients are added with metadata and permission set assignments only.

**Public surface (schema):**

| Field API name | Type | Notes |
| --- | --- | --- |
| `Permission_Set_Name__c` | Text | Required. Must equal **`PermissionSet.Name`** (API name) or **`PermissionSet.Label`** on the user’s marker assignment (case-sensitive). |
| `Saml_Setting_Api_Name__c` | Text | Required. **`DeveloperName`** of the **SamlSsoConfig** row (**Setup → Single Sign-On Settings**). Apex resolves **`SamlSsoConfig.Id`** with **`WHERE DeveloperName = :Saml_Setting_Api_Name__c`** for **`Auth.AuthConfiguration.getSamlSsoUrl`**. |
| `Is_Active__c` | Checkbox | Inactive rows are ignored by routing SOQL. |

**Dependencies:** Marker permission sets assigned to users; **SAML** enabled in the org and a valid **SAML Single Sign-On Setting** row; **Experience Guest** must be able to read **SamlSsoConfig** for the SSO path to succeed.

---

## LoginRouter (Apex)

**Purpose:** **`@AuraEnabled`** entrypoints for **emailFirstLogin** running as **Experience Guest**: **`discover`** (identifier routing and SAML initiation URL) and **`passwordLogin`** (**`Site.login`**). **`without sharing`** so **User** and **PermissionSetAssignment** reads succeed for Guest per typical org configuration.

**Public interface:**

- `@AuraEnabled(cacheable=false) static DiscoverResponse discover(String identifier, String communityBaseUrl)` — returns **`route`** **`SSO`**, **`PASSWORD`**, or **`NONE`**; when **`SSO`**, sets **`redirectUrl`** to the SAML initiation URL. **`communityBaseUrl`** is typically **`window.location.origin`** from the LWC; when blank, Apex uses **`Site.getBaseUrl()`** trimmed for **`getSamlSsoUrl`**. Post-login relay for SAML and for **`Site.login`** is server-pinned **`/s/`** (not supplied by the client).
- `@AuraEnabled(cacheable=false) static LoginResult passwordLogin(String identifier, String password)` — resolves a unique active **User** by **Username** or **Email**, then **`Site.login(Username, password, '/s/')`**; returns **`success`**, **`redirectUrl`**, and on failure a generic **`message`**.

Inner types: **`DiscoverResponse`** (`route`, `redirectUrl`); **`LoginResult`** (`success`, `redirectUrl`, `message`).

**Dependencies:** **`User`**, **`PermissionSetAssignment`**, **`Client_Sso_Routing__mdt`**, **`SamlSsoConfig`**, **`Site`**, **`Auth.AuthConfiguration`**.

**Usage constraints:** Do not log passwords. **`@TestVisible`** static test seams **`TEST_ROUTING_ROWS`**, **`TEST_SSO_URL_OVERRIDE`**, **`TEST_COMMUNITY_BASE_URL`** exist for **`@IsTest`** only; production leaves them **`null`**.

---

## emailFirstLogin (LWC)

**Purpose:** Experience Builder **Login** page UI: email step, optional SAML redirect, password step on the same surface; calls **`LoginRouter`**.

**Public surface:** Exposed to **Experience Builder** via target **`lightningCommunity__Page`**. Place on the site **Login** page. Invokes **`discover({ identifier, communityBaseUrl: window.location.origin })`** and **`passwordLogin({ identifier, password })`**.

**Dependencies:** **`LoginRouter`** Apex; site Guest must have Apex and data access per org policy.

---

## Login_Router_Guest (Permission Set)

**Purpose:** Grant **Apex class access** on **`LoginRouter`** to the Experience Cloud **Guest** user. It does **not** ship **`User`** object permissions; many orgs use **User** **Public Read Only** for external users (see [README.md](../README.md)) and **`Login_Router_Guest`** for Apex only.

**Dependencies:** Assigned to the site’s Guest User when using **`emailFirstLogin`**.
