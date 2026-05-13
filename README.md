# Salesforce Login Handler

Salesforce metadata and Apex for **email-first** Experience Cloud login: after the visitor enters an identifier, **login discovery** calls **`CommunityLoginDiscoveryHandler`**, which uses **`LoginRouteResolver`** (CMDT + marker permission sets + **`Auth.AuthConfiguration.getSamlSsoUrl`**) to send **SSO** users to the IdP or **password** users to a **Guest** Builder **handoff** page where **`emailFirstLogin`** completes sign-in with **`LoginRouterService.passwordLogin`** (**`Site.login`**). You can also place **emailFirstLogin** on the main **Login** page in Builder when **Login Page Type** is **Experience Builder Page** (same resolver and CMDT; no **`Auth.LoginDiscoveryHandler`**).

## Local setup

1. Open this folder in your editor (or add it to a multi-root workspace).
2. Authenticate to a dev org or sandbox: `sf org login web` (or your usual flow).
3. Deploy metadata: `sf project deploy start --source-dir force-app --target-org <alias>`, then follow **[Experience Cloud setup](#experience-cloud-setup)** below for each org.

## What gets deployed

| Artifact | Role |
| --- | --- |
| `CommunityLoginDiscoveryHandler` | **`global`** **`Auth.LoginDiscoveryHandler`** — assign in **Login & Registration** |
| `LoginRouteResolver` | Shared CMDT + SAML URL resolution (discovery + LWC) |
| `LoginRouterService` | **`discover`** + **`passwordLogin`** for **emailFirstLogin** (Guest) |
| `emailFirstLogin` LWC | Target `lightningCommunity__Page` — handoff page (required with discovery) and optional **Login** page |
| `Client_Sso_Routing__mdt` | Routing rows (create records per org; none shipped in the package) |
| `Login_Router_Guest` | Permission set — **Apex class access** to **`LoginRouterService`** for **Guest** |

## Experience Cloud setup

After you deploy, configure **each** target org in this order.

**1. Deploy this repository**

```bash
sf project deploy start --source-dir force-app --target-org <alias>
```

In **Setup**, confirm **`CommunityLoginDiscoveryHandler`**, **`LoginRouteResolver`**, **`LoginRouterService`**, **`emailFirstLogin`**, **`Client_Sso_Routing__mdt`**, and permission set **`Login_Router_Guest`** are present.

**2. Login discovery**

1. Open the **Experience Cloud** site → **Experience Builder**, then **Workspaces → Administration → Login & Registration** (wording can vary slightly by **Aura** vs **LWR** template).
2. Set **Login Discovery Handler** to **`CommunityLoginDiscoveryHandler`** and **Execute Login As** to the user Salesforce requires for this feature.
3. Set **Login Page Type** to **Login Discovery Page** (or equivalent) so visitors use the platform identifier step described in the [**LoginDiscoveryHandler**](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_interface_Auth_LoginDiscoveryHandler.htm) documentation.
4. **Password handoff page (required):** In Builder, create a page whose URL matches **`CommunityLoginDiscoveryHandler.PASSWORD_HANDOFF_PAGE_PATH`** (default **`/s/finish-email-login`** → slug **`finish-email-login`**). Add the **Email First Login** LWC, publish, and make that page **public for unauthenticated (Guest) users**. If Guest cannot load the page, the browser may redirect to **`/login?ec=302&startURL=...`** with **`startURL`** pointing at the handoff URL; fix page visibility, then verify in **incognito** by opening the handoff path directly and confirming the LWC loads. After discovery, **password** users arrive with **`?handoffEmail=`**; they sign in via **`Site.login`** on that page.
5. **Publish** when prompted.

**3. Optional: custom Login page in Builder**

1. Set **Login Page Type** to **Experience Builder Page** where applicable.
2. Open the **Login** page in Builder, add **Email First Login**, adjust layout, **Publish**.
3. Continue with **Guest** steps (**4–5**) so **`LoginRouterService`** can run.

**4. `User` visibility for Guest (LWC + password handoff)**

**`LoginRouterService`** runs as **Guest** on the handoff page and (when used) on the custom **Login** page. It queries **`User`** by **Username** or **Email** for **`discover`** and **`passwordLogin`**.

- Configure **User** sharing so **external** / Experience **Guest** access matches your security model. A common pattern is **User** organization-wide default / **external user** access **Public Read Only** so Guest can read rows needed for routing without granting **User** on **`Login_Router_Guest`**.
- Ensure Guest can read **`User.Email`** and **`User.Username`** (field-level security).

**5. Guest user: Apex + Permission Set rows**

1. Open the site **Guest User**.
2. Assign **`Login_Router_Guest`** (**`LoginRouterService`** Apex only).
3. Grant **`PermissionSet`** / **`PermissionSetAssignment`** read to Guest via profile or another permission set if **`discover`** cannot read assignments.

**6. Org SAML, CMDT, and markers**

1. In **Setup → Single Sign-On Settings**, ensure **SAML** is enabled for the org (**SAML Enabled** on the main Single Sign-On screen). Create or identify **SAML Single Sign-On Setting** rows; note each **`DeveloperName`** and **`SamlSsoConfig` Id** (`SELECT Id, DeveloperName FROM SamlSsoConfig`).
2. Create **`Client_Sso_Routing__mdt`** records: **`Permission_Set_Name__c`** (must match the marker permission set’s **`Name`** (API) or **`Label`** exactly), **`Saml_Setting_Api_Name__c`** (that SAML row’s **`DeveloperName`**), **`Saml_Sso_Config_Id__c`** (the **SamlSsoConfig** **Id** — set this when Guest or other callers cannot resolve the config via SOQL), **`Protocol__c = SAML`**, **`Is_Active__c`**, **`Priority__c`**.
3. Create **marker permission sets** (no privileges required), assign them to users who should use that SSO route, and keep CMDT rows **active**.

**7. Members and smoke tests**

1. Add test users as **Experience site members** with a valid **login license**.
2. Members can enter **`User.Email`** or **`User.Username`** as long as it **uniquely** matches one **active** user.
3. Test **SSO** redirect to the client IdP. Test **password** via discovery → handoff → **Sign in** without landing on **`PasswordVerificationUi`**. Unknown or ambiguous identifiers: discovery throws **invalid identifier**; LWC **`discover`** returns **`NONE`**. Use **incognito** to avoid session noise.

## Documentation

Specs follow **[Documentation Spec.md](Documentation%20Spec.md)** (required section headers and editing rules).

- [documentation/Feature-Email-first-Experience-login.md](documentation/Feature-Email-first-Experience-login.md) — runtime, UI contract, components.
- [documentation/System-Components.md](documentation/System-Components.md) — CMDT fields and Apex/LWC contracts.
- [documentation/Platform-login-discovery.md](documentation/Platform-login-discovery.md) — **`CommunityLoginDiscoveryHandler`** and login discovery contract.

## Project shape

Salesforce DX: [sfdx-project.json](sfdx-project.json) and `force-app/main/default`.
