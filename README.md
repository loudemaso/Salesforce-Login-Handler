# Salesforce Login Handler

Salesforce metadata and Apex for **email-first** Experience Cloud login on the **Experience Builder Login** page: **`emailFirstLogin`** calls **`LoginRouterService.discover`**, which uses **`LoginRouteResolver`** (CMDT + marker permission sets + **`Auth.AuthConfiguration.getSamlSsoUrl`**) to route **SSO** users to the client IdP or **password** users to the password step on the **same** LWC, then **`LoginRouterService.passwordLogin`** (**`Site.login`**). **`discover`** passes **`window.location.origin`** as **`communityBaseUrl`** so SAML URL generation uses the Experience **`my.site.com`** host even when **`Site.getBaseUrl()`** in the Guest transaction differs.

## Local setup

1. Open this folder in your editor (or add it to a multi-root workspace).
2. Authenticate to a dev org or sandbox: `sf org login web` (or your usual flow).
3. Deploy metadata: `sf project deploy start --source-dir force-app --target-org <alias>`, then follow **[Experience Cloud setup](#experience-cloud-setup)** below for each org.

## What gets deployed

| Artifact | Role |
| --- | --- |
| `LoginRouteResolver` | Shared CMDT + SAML URL resolution |
| `LoginRouterService` | Guest **`discover`** + **`passwordLogin`** for the LWC |
| `emailFirstLogin` LWC | Target `lightningCommunity__Page` — **Login** page |
| `Client_Sso_Routing__mdt` | Routing rows (create records per org; none shipped in the package) |
| `Login_Router_Guest` | Permission set — **Apex class access** to **`LoginRouterService`** for **Guest** |

## Experience Cloud setup

After you deploy, configure **each** target org in this order.

**1. Deploy this repository**

```bash
sf project deploy start --source-dir force-app --target-org <alias>
```

In **Setup**, confirm **`LoginRouteResolver`**, **`LoginRouterService`**, **`emailFirstLogin`**, **`Client_Sso_Routing__mdt`**, and permission set **`Login_Router_Guest`** are present.

**2. Login page in Experience Builder**

1. Open the **Experience Cloud** site → **Experience Builder**, then **Workspaces → Administration → Login & Registration**.
2. Set **Login Page Type** to **Experience Builder Page** (wording can vary slightly by **Aura** vs **LWR** template).
3. Open the **Login** page in Builder, add **Email First Login** (**`emailFirstLogin`**), adjust layout, **Publish**.

**3. `User` visibility for Guest**

**`LoginRouterService`** runs as **Guest** on the **Login** page. It queries **`User`** by **Username** or **Email** for **`discover`** and **`passwordLogin`**.

- Configure **User** sharing so **external** / Experience **Guest** access matches your security model. A common pattern is **User** organization-wide default / **external user** access **Public Read Only** so Guest can read rows needed for routing without granting **User** on **`Login_Router_Guest`**.
- Ensure Guest can read **`User.Email`** and **`User.Username`** (field-level security).

**4. Guest user: Apex + Permission Set rows**

1. Open the site **Guest User**.
2. Assign **`Login_Router_Guest`** (**`LoginRouterService`** Apex only).
3. Grant **`PermissionSet`** / **`PermissionSetAssignment`** read to Guest via profile or another permission set if **`discover`** cannot read assignments.

**5. Org SAML, CMDT, and markers**

1. In **Setup → Single Sign-On Settings**, ensure **SAML** is enabled for the org (**SAML Enabled** on the main Single Sign-On screen). Create or identify **SAML Single Sign-On Setting** rows; note each **`DeveloperName`** and **`SamlSsoConfig` Id** (`SELECT Id, DeveloperName FROM SamlSsoConfig`).
2. Create **`Client_Sso_Routing__mdt`** records: **`Permission_Set_Name__c`** (must match the marker permission set’s **`Name`** (API) or **`Label`** exactly), **`Saml_Setting_Api_Name__c`** (that SAML row’s **`DeveloperName`**), **`Saml_Sso_Config_Id__c`** (the **SamlSsoConfig** **Id** — set this when Guest cannot resolve the config via SOQL), **`Protocol__c = SAML`**, **`Is_Active__c`**, **`Priority__c`**.
3. Create **marker permission sets** (no privileges required), assign them to users who should use that SSO route, and keep CMDT rows **active**.

**6. Members and smoke tests**

1. Add test users as **Experience site members** with a valid **login license**.
2. Members can enter **`User.Email`** or **`User.Username`** as long as it **uniquely** matches one **active** user.
3. Test **SSO** redirect to the client IdP. Test **password** on the same LWC (**Next** → **Sign in**). Unknown or ambiguous identifiers: **`discover`** returns **`NONE`** with a generic error in the UI. Use **incognito** to avoid session noise.

## Documentation

Specs follow **[Documentation Spec.md](Documentation%20Spec.md)** (required section headers and editing rules).

- [documentation/Experience-email-first-login-design.md](documentation/Experience-email-first-login-design.md) — concise design summary for operators and agents.
- [documentation/Feature-Email-first-Experience-login.md](documentation/Feature-Email-first-Experience-login.md) — runtime, UI contract, components.
- [documentation/System-Components.md](documentation/System-Components.md) — CMDT fields and Apex/LWC contracts.

## Project shape

Salesforce DX: [sfdx-project.json](sfdx-project.json) and `force-app/main/default`.
