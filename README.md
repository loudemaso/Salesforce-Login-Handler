# Salesforce Login Handler

Salesforce metadata and Apex for **email-first** Experience Cloud login on the **Experience Builder Login** page. The **`emailFirstLogin`** LWC calls **`LoginRouter.discover`** (identifier + **`window.location.origin`**) to route members to **SSO** (SAML initiation URL) or the **password** step on the same component, then **`LoginRouter.passwordLogin`** completes sign-in with **`Site.login`**.

For the formal runtime and UI contract, see [documentation/Feature-Email-first-Experience-login.md](documentation/Feature-Email-first-Experience-login.md). For CMDT and Apex surfaces, see [documentation/System-Components.md](documentation/System-Components.md).

Specs follow **[Documentation Spec.md](Documentation%20Spec.md)** (required section headers and editing rules).

## Security

This package adds **Guest-facing Apex** and an **LWC** on the public **Login** page. Security is enforced by **how you configure the org** (profiles, permission sets, organization-wide defaults, field-level security, and Experience membership)—not by hiding data inside the LWC alone.

**`without sharing` on `LoginRouter`.** The class is declared **`without sharing`** so **Experience Guest** can complete the SOQL needed for routing (`User`, `PermissionSetAssignment`, `SamlSsoConfig`, and custom metadata). That means **row-level sharing rules on those objects do not restrict what this Apex reads** while Guest runs it. Treat Guest as a **privileged reader** for whatever object and field access you grant it: grant **only** what routing requires, and avoid attaching unrelated permission sets to Guest.

**Least privilege for Guest.** **`Login_Router_Guest`** should grant **Apex class access** to **`LoginRouter`** only. Do **not** use it as a dumping ground for broad **User** CRUD, **Modify All Data**, or unrelated object permissions. Prefer **User** organization-wide default / **external user** access and **field-level security** so Guest can read **`Username`** and **`Email`** (and **`PermissionSetAssignment`** / **`SamlSsoConfig`** if your SSO path needs them) without opening every field or every user type you do not intend to expose.

**What Guest can infer.** **`discover`** returns only **`route`** (`SSO` | `PASSWORD` | `NONE`) and, for SSO, a **`redirectUrl`**. It does **not** return user lists. The LWC shows a **generic** error for **`NONE`** so callers cannot distinguish “no user” from “ambiguous user” from transport failure. **`passwordLogin`** returns a **generic** failure message on any unsuccessful sign-in so callers cannot use the API to confirm whether an identifier exists. You should still assume **identifier probing** is possible at the network layer; rate limiting and WAF policy are org-level controls outside this repo.

**Routing and SAML.** SSO URLs are built only when **exactly one** active user matches the identifier **and** a **marker permission set** on that user matches an **active** **`Client_Sso_Routing__mdt`** row. Routing metadata is **admin-controlled** (CMDT + permission set assignments). Guests cannot create or edit CMDT; they only read rows the platform exposes to Guest for metadata types your org allows.

**Passwords and sessions.** Passwords are **never** logged by this package’s Apex. **`Site.login`** and the SAML redirect are standard Salesforce flows; after success, normal **session and cookie** rules for your Experience domain apply.

**Post-login destination.** The relay path passed to **`getSamlSsoUrl`** and **`Site.login`** is **fixed in Apex** (`/s/`), not taken from the client, so Guest cannot steer the browser to an arbitrary internal path via those parameters.

**Membership.** Only users who are **valid Experience members** (licensing and site membership per your org) should be able to complete sign-in. Configure **Login & Registration** and **member** settings so anonymous visitors cannot escalate beyond what your product allows.

## What gets deployed

| Artifact | Role |
| --- | --- |
| `LoginRouter` | **`@AuraEnabled`** **`discover`** and **`passwordLogin`** for Guest; CMDT + marker sets + SAML URL build |
| `emailFirstLogin` | LWC target **`lightningCommunity__Page`** — site **Login** page |
| `Client_Sso_Routing__mdt` | Routing rows (create records per org; none shipped in the package) |
| `Login_Router_Guest` | Permission set — **Apex class access** to **`LoginRouter`** for **Guest** |

## Administrator setup (Experience Cloud)

Use this checklist **per Experience site** after each deploy.

1. **Verify deployed components**  
   In **Setup**, confirm **`LoginRouter`**, **`emailFirstLogin`**, **`Client_Sso_Routing__mdt`**, and permission set **`Login_Router_Guest`** are present.

2. **Enable SAML at the org**  
   **Setup → Single Sign-On Settings** → ensure **SAML** is enabled on the main screen. Create or identify **SAML Single Sign-On Setting** rows and record each row’s **`DeveloperName`** (this value goes in CMDT **`Saml_Setting_Api_Name__c`**).

3. **Configure the Login page**  
   **Experience Builder** → **Workspaces → Administration → Login & Registration** → set **Login Page Type** to **Experience Builder Page** (wording may vary by template). Open the **Login** page, add **Email First Login** (**`emailFirstLogin`**), publish the site.

4. **Guest User — Apex**  
   Open the site’s **Guest User** → assign **`Login_Router_Guest`** (grants **`LoginRouter`** only).

5. **Guest User — data access for routing**  
   **`LoginRouter`** queries **`User`** (by **Username** / **Email**), **`PermissionSetAssignment`** (marker names), and **`SamlSsoConfig`** (by **DeveloperName** for SSO). Configure **organization-wide defaults**, **profile** or **additional permission sets**, and **field-level security** so Guest can read only the fields and objects required. If SSO never resolves, confirm Guest has **read** access to **`SamlSsoConfig`** (object) in your org.

6. **CMDT rows**  
   Create **`Client_Sso_Routing__mdt`** records: **`Permission_Set_Name__c`** (must match the marker permission set **Name** or **Label** exactly), **`Saml_Setting_Api_Name__c`** (SAML row **`DeveloperName`**), **`Is_Active__c = true`**.

7. **Marker permission sets**  
   Create **marker** permission sets (no privileges required). Assign them only to users who should use the mapped SSO route.

8. **Members and validation**  
   Add **site members** with appropriate licenses. Smoke-test: SSO user → IdP; password user → same LWC then **Sign in**; unknown identifier → generic error on the email step. Use **incognito** to avoid stale sessions.

## Local setup (developers)

1. Open this folder in your editor (or add it to a multi-root workspace).
2. Authenticate to a dev org or sandbox: `sf org login web` (or your usual flow).
3. Deploy: `sf project deploy start --source-dir force-app --target-org <alias>`, then complete **[Administrator setup (Experience Cloud)](#administrator-setup-experience-cloud)** for each target site.

## Project shape

Salesforce DX: [sfdx-project.json](sfdx-project.json) and `force-app/main/default`.
