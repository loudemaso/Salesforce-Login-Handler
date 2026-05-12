# Salesforce Login Handler

Salesforce-side metadata and code for an **email-first** Experience Cloud login: SAML routing via **Custom Metadata** + marker permission sets, and **password** sign-in via **`Site.login`** (see [SSO_ExperienceCloud_EmailFirst_Login_Handoff.txt](SSO_ExperienceCloud_EmailFirst_Login_Handoff.txt)).

## Local setup

1. Open this folder in your editor (or add it to a multi-root workspace).
2. Authenticate to a dev org or sandbox: `sf org login web` (or your usual flow).
3. Deploy metadata: `sf project deploy start --source-dir force-app --target-org <alias>`, then follow **[Experience Cloud setup](#experience-cloud-setup)** below for each org.

## What gets deployed

| Artifact | Role |
| --- | --- |
| `LoginRouterService` | `discover` + `passwordLogin` Apex |
| `emailFirstLogin` LWC | Target `lightningCommunity__Page` (drag onto **Login** page) |
| `Client_Sso_Routing__mdt` | Routing rows (create records per org; none shipped in the package) |
| `Login_Router_Guest` | Permission set — **Apex class access only** |

## Experience Cloud setup

After you deploy, configure **each** target org in this order.

**1. Deploy this repository**

```bash
sf project deploy start --source-dir force-app --target-org <alias>
```

In **Setup**, confirm **`LoginRouterService`**, **`emailFirstLogin`**, **`Client_Sso_Routing__mdt`**, and permission set **`Login_Router_Guest`** are present.

**2. Experience Builder login page**

1. Open the **Experience Cloud** site → **Experience Builder** (or **Digital Experiences → All Sites → Builder**).
2. Go **Workspaces → Administration → Login & Registration** (wording can vary slightly by **Aura** vs **LWR** template).
3. Set **Login Page Type** to **Experience Builder Page** (not Visualforce-only default, if you are replacing it).
4. Open the **Login** page in Builder, add the **Email First Login** component from the palette, adjust layout (e.g. logo) as needed, then **Publish** the site.
5. Use the site’s **`/s/…`** login URL for tests and bookmarks (for example `…/s/login`); that route serves the Builder login experience.

**3. `User` visibility for Guest (`discover` query)**

`LoginRouterService.discover` runs as the **Guest** user and queries **`User`** by email.

- In **Setup**, configure **User** sharing so **external** / Experience **Guest** access is appropriate for your org. The pattern we validated is **User** organization-wide default / **external user** access set to **Public Read Only** (so Guest can read `User` rows needed for email lookup **without** extra profile/permission-set grants on **User**).
- With **Public Read Only** for external users on **User**: **do not** add **User** object or **User** field permissions on the **`Login_Router_Guest`** permission set (and avoid redundant **User** object access on the Guest user solely for this feature). Rely on that OWD; then tune **PermissionSet** / **PermissionSetAssignment** only (see step 4).
- If your org **cannot** use **Public Read Only** on **User** for external users, you must agree another supported way for Guest to read `User` for login routing, then re-test with a Guest **debug log**.

**4. Guest user: Apex + Permission Set rows (not `User` on `Login_Router_Guest` when step 3 applies)**

1. Open the site **Guest User** (**Workspaces → Administration → Settings**, or equivalent, then the Guest user / profile link).
2. Assign the **`Login_Router_Guest`** permission set. That set ships with **Apex class access only**—it is **not** used to grant **`User`** access when step 3 is satisfied via **Public Read Only**.
3. **`PermissionSet`** and **`PermissionSetAssignment`** are separate from **User** OWD. Grant the Guest user **Read** (and minimal field access) on those objects via the **Guest profile** or **another** permission set if `discover` cannot read permission set assignments—follow your security review.

**5. CMDT and SAML (per org, per SSO client)**

1. Ensure **Single Sign-On Settings (SAML)** exist in Setup; note each row’s **`DeveloperName`**.
2. Create **`Client_Sso_Routing__mdt`** records: `Permission_Set_Name__c` (marker permission set API name), `Saml_Setting_Api_Name__c` (that SAML row’s `DeveloperName`), `Protocol__c = SAML`, `Is_Active__c`, `Priority__c`.
3. Create **marker permission sets** (no privileges required), assign them to users who should SSO, and keep CMDT rows **active** for production routes.

**6. Members and smoke tests**

1. Add test users as **Experience site members** with a valid **login license**.
2. Ensure **`User.Email`** matches what they type on step 1 of the component.
3. Test **password** login first (user **without** a marker permission set), then **SSO** (user **with** marker + active CMDT). Use an **incognito** window to avoid session noise.

## Documentation

- [documentation/Feature-Email-first-Experience-login.md](documentation/Feature-Email-first-Experience-login.md) — runtime, UI contract, components.
- [documentation/System-Components.md](documentation/System-Components.md) — CMDT fields and Apex/LWC contracts.

## Project shape

Salesforce DX: [sfdx-project.json](sfdx-project.json) and `force-app/main/default`.
