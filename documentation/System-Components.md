# System Components

Global reference for durable building blocks in this repository. Feature-specific sequences live in Feature specs only.

---

## Client_Sso_Routing__mdt (Custom Metadata Type)

**Purpose:** Map a **marker permission set** (by API name or label) to a **SAML Single Sign-On Setting** so new SSO clients are added with metadata and assignments only.

**Public surface (schema):**

| Field API name | Type | Notes |
| --- | --- | --- |
| `Permission_Set_Name__c` | Text | Required. Must equal **`PermissionSet.Name`** (API name) or **`PermissionSet.Label`** on the user’s marker assignment (case-sensitive). |
| `Protocol__c` | Picklist | **`SAML`** for the routing implemented in **`LoginRouteResolver`**. |
| `Saml_Setting_Api_Name__c` | Text | Required. **`DeveloperName`** of the **SamlSsoConfig** row (**Setup → Single Sign-On Settings**). Used when resolving the config Id if **`Saml_Sso_Config_Id__c`** is blank. |
| `Saml_Sso_Config_Id__c` | Text (18) | **SamlSsoConfig** record **Id** used as the third argument to **`Auth.AuthConfiguration.getSamlSsoUrl`**. When blank, the resolver loads the Id with **`SELECT Id FROM SamlSsoConfig WHERE DeveloperName = :Saml_Setting_Api_Name__c`**. Set this field when the calling user cannot read **SamlSsoConfig** (for example **Experience Guest**). Obtain as admin: `SELECT Id, DeveloperName FROM SamlSsoConfig WHERE DeveloperName = '…'`. |
| `Is_Active__c` | Checkbox | Inactive rows ignored. |
| `Priority__c` | Number | Higher wins when multiple marker sets match. |

**Dependencies:** Marker permission sets assigned to users; **SAML** enabled in the org and a valid **SAML Single Sign-On Setting** row.

---

## LoginRouteResolver (Apex)

**Purpose:** Shared resolution of identifier (email-shaped or username) → **SSO** vs **password** vs **none**, using **`Client_Sso_Routing__mdt`**, marker permission sets, and **`Auth.AuthConfiguration.getSamlSsoUrl`**. Used by **`LoginRouterService`**.

**Public interface:**

- `static DiscoverOutcome resolveDiscover(String identifier)` — **`resolveDiscover(identifier, null)`**; **`getSamlSsoUrl`** uses **`Site.getBaseUrl()`** as **communityBase** when no override is supplied.
- `static DiscoverOutcome resolveDiscover(String identifier, String experienceBaseUrlOverride)` — validates identifier shape; loads up to two active **`User`** rows by **Username** or **Email**; if exactly one user and SAML initiation URL is non-blank → **`routeType`** **`SSO`** and **`redirectUrl`**; if one user but SAML URL is blank or CMDT does not select SAML → **`PASSWORD`**; zero or multiple users or invalid input → **`NONE`**. When **`experienceBaseUrlOverride`** is non-blank (normalized with **`normalizeExperienceBaseUrl`**), it is **communityBase** for **`getSamlSsoUrl`**. **`matchedUserId`** is set when exactly one user matches.
- `static String normalizeExperienceBaseUrl(String raw)` — trims trailing slashes and trailing **`/login`**, **`/s/login`**, **`/discover`** for the Experience root used in **`getSamlSsoUrl`**; returns **`null`** when input is blank or normalizes to empty.
- `static String maskIdentifier(String raw)` — masks identifiers for safe logging.
- `static Boolean isIdentifierPlausible(String identifier)` — length and shape checks before **`User`** lookup.
- `static List<User> findActiveUsersByLoginIdentifier(String loginIdentifier)` — SOQL by **Username** or **Email** (**`LIMIT 2`**).
- Constants: **`POST_LOGIN_START_URL`** (`/s/`), **`ROUTE_SSO`**, **`ROUTE_PASSWORD`**, **`ROUTE_NONE`**.

**Dependencies:** **`User`**, **`PermissionSetAssignment`**, **`Client_Sso_Routing__mdt`**, **`SamlSsoConfig`** (when **`Saml_Sso_Config_Id__c`** is blank), **`Site`**, **`Auth.AuthConfiguration`**. Class is **`without sharing`**.

**Usage constraints:** Do not log secrets (passwords). **`@TestVisible`** static test seams **`TEST_ROUTING_ROWS`**, **`TEST_SSO_URL_OVERRIDE`**, **`TEST_COMMUNITY_BASE_URL`** exist for **`@IsTest`** only; production leaves them **`null`**.

---

## LoginRouterService (Apex)

**Purpose:** **`@AuraEnabled`** entrypoints for **emailFirstLogin** running as **Experience Guest**: **`discover`** and **`passwordLogin`** (**`Site.login`**).

**Public interface:**

- `@AuraEnabled(cacheable=false) static DiscoverResult discover(String email, String communityBaseUrl)` — passes **`LoginRouteResolver.normalizeExperienceBaseUrl(communityBaseUrl)`** into **`LoginRouteResolver.resolveDiscover`**. From the LWC, pass **`window.location.origin`** as **`communityBaseUrl`** (or **`null`** to rely on **`Site.getBaseUrl()`** only). Maps outcome to **`DiscoverResult`** (**`type`**, **`redirectUrl`**, **`correlationId`**).
- `@AuraEnabled(cacheable=false) static LoginResult passwordLogin(String email, String password)` — unique active user by **Username** or **Email**, then **`Site.login(Username, password, POST_LOGIN_START_URL)`**; returns success and redirect URL or a generic failure **`message`**.

**Dependencies:** **`LoginRouteResolver`**, **`Site`**, **`User`**. **`without sharing`**. Test seams on **`LoginRouteResolver`**: **`TEST_ROUTING_ROWS`**, **`TEST_SSO_URL_OVERRIDE`**, **`TEST_COMMUNITY_BASE_URL`**.

**Usage constraints:** **Guest** must have **`User`** and **`PermissionSetAssignment`** access per org policy (see README). **`passwordLogin`** signs in with **`Site.login`** only.

---

## emailFirstLogin (LWC)

**Purpose:** Experience Builder **Login** page UI: identifier step, SAML redirect, password step on the same surface; calls **`LoginRouterService`**.

**Public surface:** Exposed to **Experience Builder** via target **`lightningCommunity__Page`**. Place on the site **Login** page. **`discover`** is invoked with **`communityBaseUrl: window.location.origin`**.

**Dependencies:** **`LoginRouterService`** Apex; site Guest must have Apex and data access per org policy.

---

## Login_Router_Guest (Permission Set)

**Purpose:** Grant **Apex class access** on **`LoginRouterService`** to the Experience Cloud **Guest** user. It does **not** ship **`User`** object permissions; many orgs use **User** **Public Read Only** for external users (see [README.md](../README.md)) and **`Login_Router_Guest`** for Apex only.

**Dependencies:** Assigned to the site’s Guest User when using **`emailFirstLogin`**.
