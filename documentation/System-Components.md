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
| `Saml_Sso_Config_Id__c` | Text (18) | **SamlSsoConfig** record **Id** used as the third argument to **`Auth.AuthConfiguration.getSamlSsoUrl`**. When blank, the resolver loads the Id with **`SELECT Id FROM SamlSsoConfig WHERE DeveloperName = :Saml_Setting_Api_Name__c`**. Set this field when the calling user cannot read **SamlSsoConfig** (for example **Experience Guest** on the LWC path). Obtain as admin: `SELECT Id, DeveloperName FROM SamlSsoConfig WHERE DeveloperName = '…'`. |
| `Is_Active__c` | Checkbox | Inactive rows ignored. |
| `Priority__c` | Number | Higher wins when multiple marker sets match. |

**Dependencies:** Marker permission sets assigned to users; **SAML** enabled in the org and a valid **SAML Single Sign-On Setting** row.

---

## LoginRouteResolver (Apex)

**Purpose:** Shared resolution of identifier (email-shaped or username) → **SSO** vs **password** vs **none**, using **`Client_Sso_Routing__mdt`**, marker permission sets, and **`Auth.AuthConfiguration.getSamlSsoUrl`**. Used by **`CommunityLoginDiscoveryHandler`** and **`LoginRouterService`**.

**Public interface:**

- `static DiscoverOutcome resolveDiscover(String identifier)` — **`resolveDiscover(identifier, null)`**; **`getSamlSsoUrl`** uses **`Site.getBaseUrl()`** as **communityBase**.
- `static DiscoverOutcome resolveDiscover(String identifier, String samlCommunityBaseUrlOverride)` — validates identifier shape; loads up to two active **`User`** rows by **Username** or **Email**; if exactly one user and SAML initiation URL is non-blank → **`routeType`** **`SSO`** and **`redirectUrl`**; if one user but SAML URL is blank or CMDT does not select SAML → **`PASSWORD`**; zero or multiple users or invalid input → **`NONE`**. When **`samlCommunityBaseUrlOverride`** is non-blank, it is **communityBase** for **`getSamlSsoUrl`**. **`matchedUserId`** is set when exactly one user matches.
- `static PageReference buildSsoRedirectPageReference(Id userId)` — **`PageReference`** to the SAML initiation URL when resolution yields a non-blank URL; otherwise **`null`**.
- `static String maskIdentifier(String raw)` — masks identifiers for safe logging.
- `static Boolean isIdentifierPlausible(String identifier)` — length and shape checks before **`User`** lookup.
- `static List<User> findActiveUsersByLoginIdentifier(String loginIdentifier)` — SOQL by **Username** or **Email** (**`LIMIT 2`**).
- Constants: **`POST_LOGIN_START_URL`** (`/s/`), **`ROUTE_SSO`**, **`ROUTE_PASSWORD`**, **`ROUTE_NONE`**.

**Dependencies:** **`User`**, **`PermissionSetAssignment`**, **`Client_Sso_Routing__mdt`**, **`SamlSsoConfig`** (when **`Saml_Sso_Config_Id__c`** is blank), **`Site`**, **`Auth.AuthConfiguration`**. Class is **`without sharing`**.

**Usage constraints:** Do not log secrets (passwords). **`@TestVisible`** static test seams **`TEST_ROUTING_ROWS`**, **`TEST_SSO_URL_OVERRIDE`**, **`TEST_COMMUNITY_BASE_URL`** exist for **`@IsTest`** only; production leaves them **`null`**.

---

## CommunityLoginDiscoveryHandler (Apex)

**Purpose:** **`global`** implementation of **`Auth.LoginDiscoveryHandler`** for Experience Cloud **login discovery**.

**Public interface:**

- `global PageReference login(String identifier, String startUrl, Map<String, String> requestAttributes)` — **`LoginRouteResolver.resolveDiscover(identifier, communityRoot)`** with **`communityRoot`** from **`normalizeCommunityRootUrl(requestAttributes)`**. **SSO:** **`new PageReference(redirectUrl)`**. **Password:** **`PageReference`** to **handoff** (**`PASSWORD_HANDOFF_PAGE_PATH`** + **`?PASSWORD_HANDOFF_EMAIL_PARAM=`** encoded identifier). **NONE** or no matched user: **`Auth.LoginDiscoveryException('Invalid Identifier')`**. Null handoff build: same exception.

**Constants:** **`PASSWORD_HANDOFF_PAGE_PATH`** (default **`/s/finish-email-login`**), **`PASSWORD_HANDOFF_EMAIL_PARAM`** (default **`handoffEmail`**) — keep the Experience page URL slug and LWC query parsing aligned with these values.

**Dependencies:** **`LoginRouteResolver`**, **`Site`**, **`Auth.LoginDiscoveryHandler`**, **`Auth.LoginDiscoveryException`**.

**Usage constraints:** Assign in Experience **Login & Registration** (see [README.md](../README.md)). Publish a **Guest-accessible** Builder page at **`PASSWORD_HANDOFF_PAGE_PATH`** with **`emailFirstLogin`**.

---

## LoginRouterService (Apex)

**Purpose:** **`@AuraEnabled`** entrypoints for **emailFirstLogin** running as **Experience Guest**: **`discover`** and **`passwordLogin`** (**`Site.login`**).

**Public interface:**

- `@AuraEnabled(cacheable=false) static DiscoverResult discover(String email)` — maps **`LoginRouteResolver.resolveDiscover(email)`** to **`DiscoverResult`** (**`type`**, **`redirectUrl`**, **`correlationId`**).
- `@AuraEnabled(cacheable=false) static LoginResult passwordLogin(String email, String password)` — unique active user by **Username** or **Email**, then **`Site.login(Username, password, POST_LOGIN_START_URL)`**; returns success and redirect URL or a generic failure **`message`**.

**Dependencies:** **`LoginRouteResolver`**, **`Site`**, **`User`**. **`without sharing`**. Test seams on **`LoginRouteResolver`**: **`TEST_ROUTING_ROWS`**, **`TEST_SSO_URL_OVERRIDE`**, **`TEST_COMMUNITY_BASE_URL`**.

**Usage constraints:** **Guest** must have **`User`** and **`PermissionSetAssignment`** access per org policy (see README). **`passwordLogin`** does not use **`Site.passwordlessLogin`**.

---

## emailFirstLogin (LWC)

**Purpose:** Experience Builder UI for identifier and password steps; calls **`LoginRouterService`**.

**Public surface:** Exposed to **Experience Builder** via target **`lightningCommunity__Page`**. Required on the **password handoff** page (URL must match **`CommunityLoginDiscoveryHandler.PASSWORD_HANDOFF_PAGE_PATH`**). Optional on the **Login** page when not using discovery. Query **`handoffEmail`** (same name as **`PASSWORD_HANDOFF_EMAIL_PARAM`**) opens the password step with email read-only; **Back** goes to **`/login`** on the site origin.

**Dependencies:** **`LoginRouterService`** Apex; site Guest must have Apex and data access per org policy.

---

## Login_Router_Guest (Permission Set)

**Purpose:** Grant **Apex class access** on **`LoginRouterService`** to the Experience Cloud **Guest** user. It does **not** ship **`User`** object permissions; many orgs use **User** **Public Read Only** for external users (see [README.md](../README.md)) and **`Login_Router_Guest`** for Apex only. **`CommunityLoginDiscoveryHandler`** is not in this set.

**Dependencies:** Assigned to the site’s Guest User when using **`emailFirstLogin`**.
